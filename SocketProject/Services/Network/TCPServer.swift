//
//  TCPServer.swift
//  SocketProject
//
//  Created by Martenier Santos on 22/08/26.
//

import Foundation
import Network

final class TCPServer {
    private var listener: NWListener?
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var isReceiving = false
    private var connectedPlayer: Player?
    var onStateChange: ((String) -> Void)?
    var onMessageReceived: ((NetworkMessage) -> Void)?

    private let queue = DispatchQueue(label: "TCPServerQueue")
    private let port: NWEndpoint.Port

    init(port: UInt16) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() {
        guard listener == nil else {
            print("Servidor já está iniciado")
            return
        }

        do {
            let listener = try NWListener(using: .tcp, on: port)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("Servidor iniciado")
                    print("Aguardando conexão")
                    self?.onStateChange?("Servidor iniciado")
                case .failed(let error):
                    print("Erro no servidor: \(error)")
                    self?.onStateChange?("Erro no servidor")
                case .cancelled:
                    print("Servidor parado")
                    self?.onStateChange?("Servidor parado")
                case .waiting(let error):
                    print("Servidor aguardando: \(error)")
                    self?.onStateChange?("Servidor aguardando")
                default:
                    break
                }
            }

            listener.start(queue: queue)
        } catch {
            print("Falha ao iniciar o servidor: \(error)")
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isReceiving = false
            self.receiveBuffer.removeAll(keepingCapacity: false)
            self.connection?.cancel()
            self.connection = nil
            self.listener?.cancel()
            self.listener = nil
        }
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

    private func accept(_ newConnection: NWConnection) {
        if connection != nil {
            print("Servidor já possui um cliente conectado")
            newConnection.cancel()
            return
        }

        connection = newConnection
        receiveBuffer.removeAll(keepingCapacity: false)
        isReceiving = false
        connectedPlayer = nil

        newConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Cliente conectado")
                self?.receive()
            case .failed(let error):
                print("Erro na conexão: \(error)")
                self?.cleanupConnection()
            case .cancelled:
                print("Cliente desconectado")
                self?.cleanupConnection()
            case .waiting(let error):
                print("Servidor aguardando: \(error)")
            default:
                break
            }
        }

        newConnection.start(queue: queue)
    }

    private func receiveNextMessage(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBufferedMessages(prefix: "Recebido do cliente")
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

    private func processBufferedMessages(prefix: String) {
        while let newlineRange = receiveBuffer.firstRange(of: Data([0x0A])) {
            let messageData = receiveBuffer.subdata(in: 0..<newlineRange.lowerBound)
            receiveBuffer.removeSubrange(0..<newlineRange.upperBound)

            guard let message = MessageParser.decode(messageData) else {
                if let text = String(data: messageData, encoding: .utf8), !text.isEmpty {
                    print("Recebido do cliente (não decodificado): \(text)")
                }
                continue
            }

            switch message.type {
            case .playerJoined:
                connectedPlayer = message.player
                self.onMessageReceived?(message)
                print("\(prefix): playerJoined \(message.player?.name ?? "?")")
            case .playerReady:
                self.onMessageReceived?(message)
                print("\(prefix): playerReady \(message.player?.name ?? "?")")
            case .startGame:
                self.onMessageReceived?(message)
                print("\(prefix): startGame")
            case .move:
                self.onMessageReceived?(message)
                let origin = message.origin.map { "\($0.row),\($0.column)" } ?? "?"
                let destination = message.destination.map { "\($0.row),\($0.column)" } ?? "?"
                print("\(prefix): move \(origin) \(destination)")
            case .message:
                self.onMessageReceived?(message)
                print("\(prefix): message \(message.text ?? "")")
            case .disconnect:
                self.onMessageReceived?(message)
                print("\(prefix): disconnect \(message.player?.name ?? "?")")
                connectedPlayer = nil
            }
        }
    }

    private func cleanupConnection() {
        isReceiving = false
        receiveBuffer.removeAll(keepingCapacity: false)
        connection = nil
        connectedPlayer = nil
    }

    private func send(_ message: NetworkMessage, completion: (() -> Void)? = nil) {
        guard let connection = self.connection else {
            print("Nenhum cliente conectado")
            completion?()
            return
        }

        guard let data = MessageParser.encodeFramed(message) else {
            print("Falha ao codificar mensagem do servidor")
            completion?()
            return
        }

        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                print("Erro ao enviar do servidor: \(error)")
            } else {
                print("Servidor enviou: \(MessageParser.summary(for: message))")
            }
            completion?()
        })
    }
}
