//
//  TCPServer.swift
//  SocketProject
//
//  Recreated by Assistant
//

import Foundation
import Network

final class TCPServer {
    // Listener é quem "escuta" novas conexões TCP na porta configurada
    private var listener: NWListener?
    
    // Fila dedicada para eventos de rede (não bloquear a UI)
    private let queue = DispatchQueue(label: "TCPServerQueue")
    
    // Porta na qual o servidor vai escutar (ex.: 8080)
    private let port: NWEndpoint.Port

    // Inicializa o servidor com a porta desejada
    init(port: UInt16) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    // Inicia o servidor: cria o listener, configura handlers e começa a escutar
    func start() {
        do {
            let listener = try NWListener(using: .tcp, on: port)
            self.listener = listener

            // Chamado quando chega uma nova conexão de cliente
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }

            // Acompanha mudanças de estado do listener (pronto, erro, etc.)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("Servidor pronto na porta \(listener.port?.rawValue ?? 0)")
                case .failed(let error):
                    print("Servidor falhou: \(error)")
                case .waiting(let error):
                    print("Servidor aguardando: \(error)")
                default:
                    break
                }
            }

            // Começa a escutar na fila dedicada
            listener.start(queue: queue)
        } catch {
            print("Falha ao iniciar o servidor: \(error)")
        }
    }

    // Encerra o servidor, liberando recursos
    func stop() {
        listener?.cancel()
        listener = nil
    }

    // Aceita/configura uma nova conexão e inicia a leitura quando estiver pronta
    private func handle(_ connection: NWConnection) {
        // Observa mudanças de estado da conexão
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Quando a conexão está pronta, começamos a ler dados
                print("Cliente conectado: \(connection.endpoint)")
                self?.receive(on: connection)
            case .failed(let error):
                print("Conexão falhou: \(error)")
            case .cancelled:
                print("Conexão cancelada")
            default:
                break
            }
        }
        // Inicia o processamento assíncrono da conexão na fila dedicada do servidor
        connection.start(queue: queue)
    }

    // Lê dados do cliente e mantém um loop de leitura (chamando a si mesma)
    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                // Converte para String (para log). Se não for UTF‑8, mostra "<bytes>"
                let text = String(data: data, encoding: .utf8) ?? "<bytes>"
                print("Recebido: \(text)")
                // Opcional: eco simples para testar round‑trip cliente-servidor
                connection.send(content: data, completion: .contentProcessed { sendError in
                    if let sendError {
                        print("Erro ao enviar eco: \(sendError)")
                    }
                })
            }

            if isComplete {
                // O cliente encerrou a conexão de forma limpa
                connection.cancel()
                return
            }

            if let error {
                // Algum erro ocorreu durante a leitura
                print("Erro ao receber: \(error)")
                connection.cancel()
                return
            }

            // Continua lendo mais dados (loop)
            self?.receive(on: connection)
        }
    }
}
