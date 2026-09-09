//
//  LobbyViewModel.swift
//  SocketProject
//
//  Created by OpenAI.
//

import Foundation
internal import Combine
import UIKit

@MainActor
final class LobbyViewModel: ObservableObject {
    @Published var playerName: String = UIDevice.current.name
    @Published var host: String = "10.45.49.92"
    @Published var portText: String = "8080"
    @Published var message: String = "Olá servidor!"
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

        let trimmedPlayerName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPlayerName = trimmedPlayerName.isEmpty ? UIDevice.current.name : trimmedPlayerName
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

    func sendAsClient() {
        guard !message.isEmpty else { return }
        isSendingMessage = true
        dismissKeyboard()
        let text = message
        repository.sendFromClient(NetworkMessage(type: .message, text: text))
        appendLog("Cliente enviou: \(text)")
        isSendingMessage = false
    }

    func sendAsServer() {
        guard !message.isEmpty else { return }
        dismissKeyboard()
        let text = message
        repository.sendFromServer(NetworkMessage(type: .message, text: text))
        appendLog("Servidor enviou: \(text)")
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
        repository.sendFromServer(NetworkMessage(type: .playerReady, player: hostPlayer, gameState: .waiting))
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
        let trimmedPlayerName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPlayerName = trimmedPlayerName.isEmpty ? UIDevice.current.name : trimmedPlayerName
        repository.sendFromClient(NetworkMessage(type: .playerReady, player: Player(name: resolvedPlayerName), gameState: .waiting))
        appendLog("CLIENTE ficou pronto")
    }

    func startGame() {
        attemptStartGame()
    }

    func disconnectFromGame() {
        if isClientConnected {
            disconnectClient()
        } else if isServerRunning {
            stopServer()
        } else {
            resetLobbyState()
        }
    }

    func handleBoardTap(_ position: BoardPosition) {
        guard isShowingGameScreen else { return }

        if let selectedPosition {
            if selectedPosition == position {
                self.selectedPosition = nil
                boardStatus = "Peça desmarcada"
                return
            }

            if board.isEmpty(at: position) {
                performLocalMove(from: selectedPosition, to: position, sendMessage: true)
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
            return "Partida encerrada"
        }
    }

    var matchStatusDetail: String {
        switch gameState {
        case .waiting:
            return "A tela de jogo abre automaticamente quando HOST e CLIENTE estiverem prontos."
        case .playing:
            return "Você já está na tela do jogo."
        case .finished:
            return "Você pode reiniciar o servidor ou reconectar o cliente."
        }
    }

    private func handleServerMessage(_ message: NetworkMessage) {
        switch message.type {
        case .playerJoined:
            let name = message.player?.name ?? "Jogador"
            connectedPlayerName = name
            serverStatus = "Cliente conectado"
            appendLog("HOST recebeu playerJoined de \(name)")
        case .playerReady:
            clientReady = true
            appendLog("HOST recebeu playerReady de \(message.player?.name ?? "Jogador")")
            attemptStartGame()
        case .startGame:
            gameState = .playing
            appendLog("HOST recebeu startGame")
        case .move:
            applyRemoteMove(origin: message.origin, destination: message.destination)
        case .message:
            appendLog("HOST recebeu: \(message.text ?? "")")
        case .disconnect:
            let name = message.player?.name ?? "Jogador"
            connectedPlayerName = "Nenhum jogador"
            serverStatus = "Aguardando conexão"
            if isShowingGameScreen {
                finishMatch()
            } else {
                resetLobbyState()
            }
            appendLog("HOST recebeu disconnect de \(name)")
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
            applyRemoteMove(origin: message.origin, destination: message.destination)
        case .message:
            appendLog("CLIENTE recebeu: \(message.text ?? "")")
        case .disconnect:
            appendLog("CLIENTE recebeu disconnect")
            if isShowingGameScreen {
                finishMatch()
            } else {
                resetLobbyState()
            }
        }
    }

    private func attemptStartGame() {
        guard isServerRunning, isClientConnected, hostReady, clientReady else { return }
        guard gameState != .playing else { return }

        gameState = .playing
        repository.sendFromServer(NetworkMessage(type: .startGame, gameState: .playing))
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
        board = Board.initial()
    }

    private func finishMatch() {
        gameState = .finished
        hostReady = false
        clientReady = false
        isShowingGameScreen = false
        selectedPosition = nil
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

    private func performLocalMove(from origin: BoardPosition, to destination: BoardPosition, sendMessage: Bool) {
        guard board.isEmpty(at: destination) else {
            boardStatus = "Destino ocupado"
            return
        }

        board.movePiece(from: origin, to: destination)
        selectedPosition = nil
        currentTurn = currentTurn == .white ? .black : .white
        boardStatus = isLocalPlayersTurn ? "Sua vez" : "Aguardando oponente"
        appendLog("Movimento local: \(origin.row),\(origin.column) -> \(destination.row),\(destination.column)")

        guard sendMessage else { return }

        let message = NetworkMessage(type: .move, origin: origin, destination: destination)
        if isServerRunning {
            repository.sendFromServer(message)
        } else {
            repository.sendFromClient(message)
        }
    }

    private func applyRemoteMove(origin: BoardPosition?, destination: BoardPosition?) {
        guard let origin, let destination else {
            appendLog("Move inválido recebido")
            return
        }

        guard board.piece(at: origin) != nil, board.isEmpty(at: destination) else {
            appendLog("Move inválido recebido")
            return
        }

        board.movePiece(from: origin, to: destination)
        selectedPosition = nil
        currentTurn = currentTurn == .white ? .black : .white
        boardStatus = isLocalPlayersTurn ? "Sua vez" : "Aguardando oponente"
        appendLog("Movimento recebido: \(origin.row),\(origin.column) -> \(destination.row),\(destination.column)")
    }

    private func appendLog(_ text: String) {
        logs.append(text)
        if logs.count > 60 {
            logs.removeFirst(logs.count - 60)
        }
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
