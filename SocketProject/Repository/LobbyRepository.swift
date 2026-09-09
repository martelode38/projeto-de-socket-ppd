final class LobbyRepository {
    var onServerStateChange: ((String) -> Void)?
    var onClientStateChange: ((String) -> Void)?
    var onServerMessageReceived: ((NetworkMessage) -> Void)?
    var onClientMessageReceived: ((NetworkMessage) -> Void)?

    private var server: TCPServer?
    private var client: TCPClient?

    func startServer(port: UInt16) {
        let server = TCPServer(port: port)
        server.onStateChange = { [weak self] state in
            self?.onServerStateChange?(state)
        }
        server.onMessageReceived = { [weak self] message in
            self?.onServerMessageReceived?(message)
        }
        self.server = server
        server.start()
    }

    func stopServer() {
        server?.stop()
        server = nil
    }

    func connectClient(host: String, port: UInt16, player: Player) {
        let client = TCPClient(host: host, port: port, player: player)
        client.onStateChange = { [weak self] state in
            self?.onClientStateChange?(state)
        }
        client.onMessageReceived = { [weak self] message in
            self?.onClientMessageReceived?(message)
        }
        self.client = client
        client.connect()
    }

    func disconnectClient() {
        client?.disconnect()
        client = nil
    }

    func sendFromClient(_ message: NetworkMessage) {
        client?.send(message)
    }

    func sendFromServer(_ message: NetworkMessage) {
        server?.send(message)
    }
}
