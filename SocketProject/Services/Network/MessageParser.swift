import Foundation

struct Player: Codable {
    let name: String

    init(name: String) {
        self.name = name
    }
}

enum GameState: String, Codable {
    case waiting
    case playing
    case finished
}

enum MessageType: String, Codable {
    case playerJoined
    case playerReady
    case startGame
    case move
    case message
    case disconnect
    case gameOver
}

struct NetworkMessage: Codable {
    let type: MessageType
    let player: Player?
    let text: String?
    let gameState: GameState?
    let origin: BoardPosition?
    let destination: BoardPosition?
    let captureKind: CaptureKind?
    let capturedPositions: [BoardPosition]
    let boardPieces: [Piece]?
    let winner: PieceOwner?
    let gameOverReason: GameOverReason?

    init(
        type: MessageType,
        player: Player? = nil,
        text: String? = nil,
        gameState: GameState? = nil,
        origin: BoardPosition? = nil,
        destination: BoardPosition? = nil,
        captureKind: CaptureKind? = nil,
        capturedPositions: [BoardPosition] = [],
        boardPieces: [Piece]? = nil,
        winner: PieceOwner? = nil,
        gameOverReason: GameOverReason? = nil
    ) {
        self.type = type
        self.player = player
        self.text = text
        self.gameState = gameState
        self.origin = origin
        self.destination = destination
        self.captureKind = captureKind
        self.capturedPositions = capturedPositions
        self.boardPieces = boardPieces
        self.winner = winner
        self.gameOverReason = gameOverReason
    }

    enum CodingKeys: String, CodingKey {
        case type
        case player
        case text
        case gameState
        case origin
        case destination
        case captureKind
        case capturedPositions
        case boardPieces
        case winner
        case gameOverReason
    }

    // Messages from older app builds do not contain the newer game fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(MessageType.self, forKey: .type)
        player = try container.decodeIfPresent(Player.self, forKey: .player)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        gameState = try container.decodeIfPresent(GameState.self, forKey: .gameState)
        origin = try container.decodeIfPresent(BoardPosition.self, forKey: .origin)
        destination = try container.decodeIfPresent(BoardPosition.self, forKey: .destination)
        captureKind = try container.decodeIfPresent(CaptureKind.self, forKey: .captureKind)
        capturedPositions = try container.decodeIfPresent([BoardPosition].self, forKey: .capturedPositions) ?? []
        boardPieces = try container.decodeIfPresent([Piece].self, forKey: .boardPieces)
        winner = try container.decodeIfPresent(PieceOwner.self, forKey: .winner)
        gameOverReason = try container.decodeIfPresent(GameOverReason.self, forKey: .gameOverReason)
    }
}

enum MessageParser {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encode(_ message: NetworkMessage) -> Data? {
        try? encoder.encode(message)
    }

    static func decode(_ data: Data) -> NetworkMessage? {
        try? decoder.decode(NetworkMessage.self, from: data)
    }

    static func encodeFramed(_ message: NetworkMessage) -> Data? {
        guard let data = encode(message) else { return nil }
        var framed = Data(data)
        framed.append(0x0A)
        return framed
    }

    static func decodeMessages(from buffer: inout Data) -> [NetworkMessage] {
        var messages: [NetworkMessage] = []

        while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
            let messageData = buffer.subdata(in: 0..<newlineRange.lowerBound)
            buffer.removeSubrange(0..<newlineRange.upperBound)

            if let message = decode(messageData) {
                messages.append(message)
            }
        }

        return messages
    }

    static func summary(for message: NetworkMessage) -> String {
        switch message.type {
        case .playerJoined:
            let name = message.player?.name ?? "?"
            return "playerJoined \(name)"
        case .playerReady:
            let name = message.player?.name ?? "?"
            return "playerReady \(name)"
        case .startGame:
            return "startGame"
        case .move:
            let origin = message.origin.map { "\($0.row),\($0.column)" } ?? "?"
            let destination = message.destination.map { "\($0.row),\($0.column)" } ?? "?"
            let capture = message.captureKind?.title ?? "sem captura"
            return "move \(origin) \(destination) \(capture) x\(message.capturedPositions.count)"
        case .message:
            return "message \(message.text ?? "")"
        case .disconnect:
            let name = message.player?.name ?? "?"
            return "disconnect \(name)"
        case .gameOver:
            let winner = message.winner?.rawValue ?? "?"
            let reason = message.gameOverReason?.title ?? "Fim"
            return "gameOver \(winner) \(reason)"
        }
    }
}
