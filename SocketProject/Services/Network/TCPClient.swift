//
//  TCPClient.swift
//  SocketProject
//
//  Created by Martenier Santos on 22/08/26.
//

import Foundation
import Network

final class TCPClient {
    var connection: NWConnection?
    var onStateChange: ((String) -> Void)?
    var onMessageReceived: ((NetworkMessage) -> Void)?

    private let queue = DispatchQueue(label: "TCPClientQueue")
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let localPlayer: Player
    private var receiveBuffer = Data()
    private var isReceiving = false

    init(host: String, port: UInt16, player: Player) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
        self.localPlayer = player
    }

    func connect() {
        guard connection == nil else {
            print("Cliente já está conectado ou conectando")
            return
        }

        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Cliente conectado")
                self?.onStateChange?("Cliente conectado")
                self?.receive()
                self?.send(NetworkMessage(type: .playerJoined, player: self?.localPlayer))
            case .failed(let error):
                print("Erro na conexão: \(error)")
                self?.onStateChange?("Erro na conexão")
                self?.cleanupConnection()
            case .cancelled:
                print("Desconectado")
                self?.onStateChange?("Desconectado")
                self?.cleanupConnection()
            case .waiting(let error):
                print("Cliente aguardando: \(error)")
                self?.onStateChange?("Cliente aguardando")
            default:
                break
            }
        }

        print("Conectando...")
        connection.start(queue: queue)
    }

    func send(_ message: String) {
        send(NetworkMessage(type: .message, text: message))
    }

    func send(_ message: NetworkMessage) {
        queue.async { [weak self] in
            self?.send(message, completion: nil)
        }
    }

    func receive() {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isReceiving, let connection = self.connection else { return }
            self.isReceiving = true
            self.receiveNextMessage(on: connection)
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.connection != nil else {
                self.cleanupConnection()
                return
            }

            let disconnectMessage = NetworkMessage(type: .disconnect, player: self.localPlayer)
            self.send(disconnectMessage) { [weak self] in
                self?.connection?.cancel()
                self?.cleanupConnection()
            }
        }
    }

    private func receiveNextMessage(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBufferedMessages()
            }

            if isComplete {
                connection.cancel()
                self.cleanupConnection()
                return
            }

            if let error {
                print("Erro na conexão: \(error)")
                self.cleanupConnection()
                return
            }

            self.receiveNextMessage(on: connection)
        }
    }

    private func processBufferedMessages() {
        while let newlineRange = receiveBuffer.firstRange(of: Data([0x0A])) {
            let messageData = receiveBuffer.subdata(in: 0..<newlineRange.lowerBound)
            receiveBuffer.removeSubrange(0..<newlineRange.upperBound)

            guard let message = MessageParser.decode(messageData) else {
                if let text = String(data: messageData, encoding: .utf8), !text.isEmpty {
                    print("Recebido do servidor (não decodificado): \(text)")
                }
                continue
            }

            self.onMessageReceived?(message)
            print("Recebido do servidor: \(MessageParser.summary(for: message))")
        }
    }

    private func cleanupConnection() {
        isReceiving = false
        receiveBuffer.removeAll(keepingCapacity: false)
        connection = nil
    }

    private func send(_ message: NetworkMessage, completion: (() -> Void)? = nil) {
        guard let connection = self.connection else {
            print("Cliente sem conexão ativa")
            completion?()
            return
        }

        guard let data = MessageParser.encodeFramed(message) else {
            print("Falha ao codificar mensagem do cliente")
            completion?()
            return
        }

        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                print("Erro ao enviar do cliente: \(error)")
            } else {
                print("Cliente enviou: \(MessageParser.summary(for: message))")
            }
            completion?()
        })
    }
}
