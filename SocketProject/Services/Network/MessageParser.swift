//
//  MessageParser.swift
//  SocketProject
//
//  Created by OpenAI.
//

import Foundation

struct Player: Codable, Hashable, Identifiable {
    let id: UUID
    let name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
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
}

struct NetworkMessage: Codable {
    let type: MessageType
    let player: Player?
    let text: String?
    let gameState: GameState?
    let origin: BoardPosition?
    let destination: BoardPosition?

    init(
        type: MessageType,
        player: Player? = nil,
        text: String? = nil,
        gameState: GameState? = nil,
        origin: BoardPosition? = nil,
        destination: BoardPosition? = nil
    ) {
        self.type = type
        self.player = player
        self.text = text
        self.gameState = gameState
        self.origin = origin
        self.destination = destination
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

    static func summary(for message: NetworkMessage) -> String {
        switch message.type {
        case .playerJoined:
            let name = message.player?.name ?? "?"
            let id = message.player?.id.uuidString ?? "?"
            return "playerJoined \(name) \(id)"
        case .playerReady:
            let name = message.player?.name ?? "?"
            return "playerReady \(name)"
        case .startGame:
            return "startGame"
        case .move:
            let origin = message.origin.map { "\($0.row),\($0.column)" } ?? "?"
            let destination = message.destination.map { "\($0.row),\($0.column)" } ?? "?"
            return "move \(origin) \(destination)"
        case .message:
            return "message \(message.text ?? "")"
        case .disconnect:
            let name = message.player?.name ?? "?"
            return "disconnect \(name)"
        }
    }
}
