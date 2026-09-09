import Foundation
internal import Combine
import UIKit

@MainActor
final class LobbyViewModel: ObservableObject {
    @Published var playerName: String = UIDevice.current.name
    @Published var host: String = "10.45.49.92"
    @Published var portText: String = "8080"
    @Published var message: String = "Olá servidor!"
    @Published var chatMessages: [ChatMessage] = []
    @Published var logs: [String] = []
    @Published var serverStatus: String = "Servidor parado"
    @Published var clientStatus: String = "Desconectado"
    @Published var connectedPlayerName: String = "Nenhum jogador"
    @Published var gameState: GameState = .waiting
    @Published var hostReady = false
    @Published var clientReady = false
    @Published var isServerRunning = false
    @Published var isClientConnected = false
    @Published var isStartingServer = false
    @Published var isStoppingServer = false
    @Published var isConnectingClient = false
    @Published var isSendingMessage = false
    @Published var isShowingGameScreen = false
    @Published var board = Board.initial()
    @Published var selectedPosition: BoardPosition?
    @Published var boardStatus: String = "Selecione uma peça"
    @Published var currentTurn: PieceOwner = .white
    @Published var winnerText: String = ""

    private let repository = LobbyRepository()

    init() {
        repository.onServerStateChange = { [weak self] status in
            DispatchQueue.main.async {
                self?.serverStatus = status
                self?.isServerRunning = status != "Servidor parado"
                self?.appendLog("HOST: \(status)")
            }
        }

        repository.onClientStateChange = { [weak self] status in
            DispatchQueue.main.async {
                self?.clientStatus = status
                self?.isClientConnected = status == "Cliente conectado"
                if status == "Cliente conectado" || status == "Erro na conexão" || status == "Desconectado" {
                    self?.isConnectingClient = false
                }
                self?.appendLog("CLIENTE: \(status)")
            }
        }

        repository.onServerMessageReceived = { [weak self] message in
            DispatchQueue.main.async {
                self?.handleServerMessage(message)
            }
        }

        repository.onClientMessageReceived = { [weak self] message in
            DispatchQueue.main.async {
                self?.handleClientMessage(message)
            }
        }
    }

    func startServer() {
        guard let port = UInt16(portText) else {
            appendLog("Porta inválida")
            return
        }

        isStartingServer = true
        dismissKeyboard()
        resetMatchState()
        isShowingGameScreen = false
        repository.startServer(port: port)
        serverStatus = "Servidor iniciado"
        isServerRunning = true
        appendLog("Servidor iniciado na porta \(port)")
        isStartingServer = false
    }

    func stopServer() {
        isStoppingServer = true
        repository.stopServer()
        serverStatus = "Servidor parado"
        isServerRunning = false
        if isShowingGameScreen {
            finishMatch()
        } else {
            resetLobbyState()
        }
        appendLog("Servidor parado")
        isStoppingServer = false
    }

    func toggleServer() {
        if isServerRunning {
            stopServer()
        } else {
            startServer()
        }
    }

    func connectClient() {
        guard let port = UInt16(portText) else {
            appendLog("Porta inválida")
            return
        }

        guard !isConnectingClient, !isClientConnected else {
            appendLog("Cliente já está conectando ou conectado")
            return
        }

        isConnectingClient = true
        dismissKeyboard()
        resetMatchState()
        isShowingGameScreen = false

        repository.connectClient(host: host, port: port, player: Player(name: resolvedPlayerName))
        clientStatus = "Conectando..."
        isClientConnected = false
        appendLog("Cliente conectando em \(host):\(port) como \(resolvedPlayerName)")
    }

    func disconnectClient() {
        repository.disconnectClient()
        clientStatus = "Desconectado"
        isClientConnected = false
        if isShowingGameScreen {
            finishMatch()
        } else {
            resetLobbyState()
        }
        appendLog("Cliente desconectado")
    }

    func toggleClient() {
        if isClientConnected {
            disconnectClient()
        } else {
            connectClient()
        }
    }

    func sendChatMessage() {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSendingMessage = true
        dismissKeyboard()
        sendToPeer(NetworkMessage(type: .message, text: text))
        chatMessages.append(ChatMessage(text: text, isMine: true))
        message = ""
        let sender = isServerRunning ? "Servidor" : "Cliente"
        appendLog("\(sender) enviou: \(text)")
        isSendingMessage = false
    }

    func readyAsHost() {
        guard isServerRunning else {
            appendLog("Servidor não está ativo")
            return
        }

        resetBoardForNewGame()
        hostReady = true
        isShowingGameScreen = true
        gameState = .playing
        let hostPlayer = Player(name: "HOST")
        sendToPeer(NetworkMessage(type: .playerReady, player: hostPlayer, gameState: .waiting))
        appendLog("HOST ficou pronto")
        attemptStartGame()
    }

    func readyAsClient() {
        guard isClientConnected else {
            appendLog("Cliente não está conectado")
            return
        }

        resetBoardForNewGame()
        clientReady = true
        isShowingGameScreen = true
        gameState = .playing
        sendToPeer(NetworkMessage(type: .playerReady, player: Player(name: resolvedPlayerName), gameState: .waiting))
        appendLog("CLIENTE ficou pronto")
    }

    func markReady() {
        if isServerRunning {
            readyAsHost()
        } else {
            readyAsClient()
        }
    }

    func disconnectFromGame() {
        if isServerRunning {
            stopServer()
        } else if isClientConnected {
            disconnectClient()
        } else {
            resetLobbyState()
        }
    }

    func resignMatch() {
        guard isShowingGameScreen else { return }

        let winner = localPieceOwner.opponent
        sendGameOver(winner: winner, reason: .resignation)
        finishMatch(winner: winner, reason: .resignation)
        appendLog("Você desistiu")
    }

    func handleBoardTap(_ position: BoardPosition) {
        guard isShowingGameScreen else { return }
        guard isLocalPlayersTurn else {
            boardStatus = "Aguarde sua vez"
            return
        }

        if let selectedPosition {
            if selectedPosition == position {
                self.selectedPosition = nil
                boardStatus = "Peça desmarcada"
                return
            }

            if board.isEmpty(at: position) {
                performLocalMove(from: selectedPosition, to: position)
            } else if let piece = board.piece(at: position), piece.owner == localPieceOwner {
                self.selectedPosition = position
                boardStatus = "Outra peça selecionada"
            } else {
                boardStatus = "Destino ocupado"
            }
            return
        }

        guard let piece = board.piece(at: position) else {
            boardStatus = "Selecione uma peça primeiro"
            return
        }

        guard piece.owner == localPieceOwner else {
            boardStatus = isLocalPlayersTurn ? "Selecione sua própria peça" : "Aguarde sua vez"
            return
        }

        selectedPosition = position
        boardStatus = "Peça selecionada"
    }

    var matchStatusText: String {
        switch gameState {
        case .waiting:
            if !isServerRunning && !isClientConnected {
                return "Aguardando servidor e cliente"
            }
            if isServerRunning && !isClientConnected {
                return "Servidor pronto. Aguardando cliente."
            }
            if !isServerRunning && isClientConnected {
                return "Cliente conectado. Aguardando host."
            }
            if hostReady && clientReady {
                return "Tudo pronto para começar"
            }
            if hostReady {
                return "HOST pronto. Aguardando CLIENTE."
            }
            if clientReady {
                return "CLIENTE pronto. Aguardando HOST."
            }
            return "Conecte os dois lados e marque Ready"
        case .playing:
            return "Tela de jogo aberta"
        case .finished:
            return winnerText.isEmpty ? "Partida encerrada" : winnerText
        }
    }

    var matchStatusDetail: String {
        switch gameState {
        case .waiting:
            return "A tela de jogo abre automaticamente quando HOST e CLIENTE estiverem prontos."
        case .playing:
            return "Você já está na tela do jogo."
        case .finished:
            return boardStatus
        }
    }

    var roleText: String {
        if isServerRunning {
            return "Servidor"
        }

        if isClientConnected || isConnectingClient {
            return "Cliente"
        }

        return "Escolha uma função"
    }

    var serverButtonTitle: String {
        isServerRunning ? "Parar servidor" : "Iniciar servidor"
    }

    var clientButtonTitle: String {
        isClientConnected ? "Desconectar" : "Conectar"
    }

    var readyButtonTitle: String {
        if isServerRunning && hostReady {
            return "Servidor pronto"
        }

        if isClientConnected && clientReady {
            return "Cliente pronto"
        }

        return "Estou pronto"
    }

    var isServerButtonDisabled: Bool {
        isStartingServer || isStoppingServer || (isClientConnected && !isServerRunning)
    }

    var isClientButtonDisabled: Bool {
        isConnectingClient || isServerRunning || (!isClientConnected && host.isEmpty)
    }

    var isReadyButtonDisabled: Bool {
        if isServerRunning {
            return hostReady
        }

        if isClientConnected {
            return clientReady
        }

        return true
    }

    var canSendChatMessage: Bool {
        !isSendingMessage
            && (isServerRunning || isClientConnected)
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handleServerMessage(_ message: NetworkMessage) {
        switch message.type {
        case .playerJoined:
            let name = message.player?.name ?? "Jogador"
            connectedPlayerName = name
            serverStatus = "Cliente conectado"
            isClientConnected = true
            appendLog("HOST recebeu playerJoined de \(name)")
        case .playerReady:
            clientReady = true
            appendLog("HOST recebeu playerReady de \(message.player?.name ?? "Jogador")")
            attemptStartGame()
        case .startGame:
            gameState = .playing
            appendLog("HOST recebeu startGame")
        case .move:
            applyRemoteMove(message)
        case .message:
            appendChatFromPeer(message.text)
            appendLog("HOST recebeu: \(message.text ?? "")")
        case .disconnect:
            let name = message.player?.name ?? "Jogador"
            connectedPlayerName = "Nenhum jogador"
            serverStatus = "Aguardando conexão"
            isClientConnected = false
            if isShowingGameScreen {
                finishMatch(winner: .white, reason: .disconnect)
            } else {
                resetLobbyState()
            }
            appendLog("HOST recebeu disconnect de \(name)")
        case .gameOver:
            applyGameOver(message)
        }
    }

    private func handleClientMessage(_ message: NetworkMessage) {
        switch message.type {
        case .playerJoined:
            appendLog("CLIENTE recebeu playerJoined de \(message.player?.name ?? "Jogador")")
        case .playerReady:
            hostReady = true
            appendLog("CLIENTE recebeu playerReady de \(message.player?.name ?? "Jogador")")
        case .startGame:
            gameState = .playing
            appendLog("CLIENTE recebeu startGame")
        case .move:
            applyRemoteMove(message)
        case .message:
            appendChatFromPeer(message.text)
            appendLog("CLIENTE recebeu: \(message.text ?? "")")
        case .disconnect:
            appendLog("CLIENTE recebeu disconnect")
            clientStatus = "Desconectado"
            isClientConnected = false
            if isShowingGameScreen {
                finishMatch(winner: .black, reason: .disconnect)
            } else {
                resetLobbyState()
            }
        case .gameOver:
            applyGameOver(message)
        }
    }

    private func attemptStartGame() {
        guard isServerRunning, isClientConnected, hostReady, clientReady else { return }
        guard gameState != .playing else { return }

        gameState = .playing
        sendToPeer(NetworkMessage(type: .startGame, gameState: .playing))
        appendLog("HOST enviou startGame")
    }

    private func resetMatchState() {
        gameState = .waiting
        hostReady = false
        clientReady = false
    }

    private func resetLobbyState() {
        gameState = .waiting
        hostReady = false
        clientReady = false
        isShowingGameScreen = false
        connectedPlayerName = "Nenhum jogador"
        selectedPosition = nil
        boardStatus = "Selecione uma peça"
        currentTurn = .white
        winnerText = ""
        chatMessages.removeAll()
        board = Board.initial()
    }

    private func finishMatch(winner: PieceOwner? = nil, reason: GameOverReason? = nil) {
        gameState = .finished
        hostReady = false
        clientReady = false
        isShowingGameScreen = false
        selectedPosition = nil
        if let winner {
            winnerText = "Vencedor: \(displayName(for: winner))"
            boardStatus = "\(winnerText) - \(reason?.title ?? "Fim de jogo")"
        } else {
            winnerText = ""
            boardStatus = "Partida encerrada"
        }
    }

    private var localPieceOwner: PieceOwner {
        isServerRunning ? .white : .black
    }

    private var isLocalPlayersTurn: Bool {
        currentTurn == localPieceOwner
    }

    private func resetBoardForNewGame() {
        board = Board.initial()
        selectedPosition = nil
        currentTurn = .white
        boardStatus = isLocalPlayersTurn ? "Sua vez" : "Aguardando oponente"
    }

    private func performLocalMove(from origin: BoardPosition, to destination: BoardPosition) {
        guard board.isValidStep(from: origin, to: destination) else {
            boardStatus = "Movimento inválido"
            return
        }

        guard board.isEmpty(at: destination) else {
            boardStatus = "Destino ocupado"
            return
        }

        let capture = board.resolvedCapture(from: origin, to: destination)
        let capturedPositions = capture.positions

        board.movePiece(from: origin, to: destination)
        board.removePieces(at: capturedPositions)
        selectedPosition = nil

        if let winner = board.winner {
            sendMove(
                origin: origin,
                destination: destination,
                captureKind: capture.kind,
                capturedPositions: capturedPositions
            )
            sendGameOver(winner: winner, reason: .noPieces)
            finishMatch(winner: winner, reason: .noPieces)
            appendMoveLog(origin: origin, destination: destination, captureKind: capture.kind, capturedPositions: capturedPositions)
            return
        }

        currentTurn = currentTurn == .white ? .black : .white
        boardStatus = statusTextAfterMove(capturedCount: capturedPositions.count)
        appendMoveLog(origin: origin, destination: destination, captureKind: capture.kind, capturedPositions: capturedPositions)

        sendMove(
            origin: origin,
            destination: destination,
            captureKind: capture.kind,
            capturedPositions: capturedPositions
        )
    }

    private func sendMove(
        origin: BoardPosition,
        destination: BoardPosition,
        captureKind: CaptureKind?,
        capturedPositions: [BoardPosition]
    ) {
        let message = NetworkMessage(
            type: .move,
            origin: origin,
            destination: destination,
            captureKind: captureKind,
            capturedPositions: capturedPositions,
            boardPieces: Array(board.pieces.values)
        )
        sendToPeer(message)
    }

    private func applyRemoteMove(_ message: NetworkMessage) {
        let capturedPositions = message.capturedPositions
        guard let origin = message.origin, let destination = message.destination else {
            appendLog("Move inválido recebido")
            return
        }

        guard board.contains(origin), board.contains(destination) else {
            appendLog("Move inválido recebido")
            return
        }

        if let boardPieces = message.boardPieces {
            applyBoardSnapshot(boardPieces)
        } else {
            guard board.isValidStep(from: origin, to: destination),
                  board.piece(at: origin) != nil,
                  board.isEmpty(at: destination) else {
                appendLog("Move inválido recebido")
                return
            }

            board.movePiece(from: origin, to: destination)
            board.removePieces(at: capturedPositions)
        }
        selectedPosition = nil

        if let winner = message.winner ?? board.winner {
            finishMatch(winner: winner, reason: message.gameOverReason ?? .noPieces)
            appendLog("Fim de jogo recebido")
            return
        }

        currentTurn = currentTurn == .white ? .black : .white
        boardStatus = isLocalPlayersTurn ? "Sua vez" : "Aguardando oponente"
        appendLog("Movimento recebido: \(origin.row),\(origin.column) -> \(destination.row),\(destination.column)")
        if !capturedPositions.isEmpty {
            let captureKind = message.captureKind?.title.lowercased() ?? "captura"
            appendLog("Captura recebida por \(captureKind): \(capturedPositions.count)")
        }
    }

    private func statusTextAfterMove(capturedCount: Int) -> String {
        if capturedCount > 0 {
            return "Captura realizada. \(isLocalPlayersTurn ? "Sua vez" : "Aguardando oponente")"
        }

        return isLocalPlayersTurn ? "Sua vez" : "Aguardando oponente"
    }

    private func applyBoardSnapshot(_ pieces: [Piece]) {
        var updatedPieces: [BoardPosition: Piece] = [:]
        for piece in pieces {
            updatedPieces[piece.position] = piece
        }
        board = Board(positions: board.positions, pieces: updatedPieces)
    }

    private func appendMoveLog(
        origin: BoardPosition,
        destination: BoardPosition,
        captureKind: CaptureKind?,
        capturedPositions: [BoardPosition]
    ) {
        appendLog("Movimento local: \(origin.row),\(origin.column) -> \(destination.row),\(destination.column)")
        if !capturedPositions.isEmpty {
            let captureName = captureKind?.title.lowercased() ?? "captura"
            appendLog("Captura por \(captureName): \(capturedPositions.count)")
        }
    }

    private func sendGameOver(winner: PieceOwner, reason: GameOverReason) {
        let message = NetworkMessage(
            type: .gameOver,
            gameState: .finished,
            boardPieces: Array(board.pieces.values),
            winner: winner,
            gameOverReason: reason
        )

        sendToPeer(message)
    }

    private func applyGameOver(_ message: NetworkMessage) {
        if let boardPieces = message.boardPieces {
            applyBoardSnapshot(boardPieces)
        }

        let winner = message.winner
        let reason = message.gameOverReason ?? .noPieces
        finishMatch(winner: winner, reason: reason)
        appendLog("Game over recebido: \(reason.title)")
    }

    private func displayName(for owner: PieceOwner) -> String {
        switch owner {
        case .white:
            return "Brancas"
        case .black:
            return "Pretas"
        }
    }

    private var resolvedPlayerName: String {
        let trimmedName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? UIDevice.current.name : trimmedName
    }

    private func sendToPeer(_ message: NetworkMessage) {
        if isServerRunning {
            repository.sendFromServer(message)
        } else {
            repository.sendFromClient(message)
        }
    }

    private func appendLog(_ text: String) {
        logs.append(text)
        if logs.count > 60 {
            logs.removeFirst(logs.count - 60)
        }
    }

    private func appendChatFromPeer(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        chatMessages.append(ChatMessage(text: text, isMine: false))
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
