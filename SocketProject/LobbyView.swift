//
//  LobbyView.swift
//  SocketProject
//
//  Created by OpenAI.
//

import SwiftUI

struct LobbyView: View {
    @StateObject private var viewModel = LobbyViewModel()

    var body: some View {
        Group {
            if viewModel.isShowingGameScreen {
                GameView(viewModel: viewModel)
            } else {
                lobbyContent
            }
        }
        .onAppear {
            if viewModel.logs.isEmpty {
                viewModel.logs.append("Lobby pronto")
            }
        }
    }

    private var lobbyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Lobby")
                    .font(.title)

                Text(viewModel.matchStatusText)
                Text(viewModel.matchStatusDetail)

//                VStack(alignment: .leading, spacing: 8) {
//                    Text("HOST")
//                        .font(.headline)
//                    Text("Estado: \(viewModel.serverStatus)")
//                    Text("Jogador: \(viewModel.connectedPlayerName)")
//                    Text("Pronto: \(viewModel.hostReady ? "Sim" : "Não")")
//                    Text("Porta: \(viewModel.portText)")
//                }
//
//                VStack(alignment: .leading, spacing: 8) {
//                    Text("CLIENTE")
//                        .font(.headline)
//                    Text("Estado: \(viewModel.clientStatus)")
//                    Text("Player local: \(viewModel.playerName)")
//                    Text("Pronto: \(viewModel.clientReady ? "Sim" : "Não")")
//                    Text("Host: \(viewModel.host)")
//                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Identidade e conexão")
                        .font(.headline)

                    TextField("Jogador", text: $viewModel.playerName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Host", text: $viewModel.host)
                        .textFieldStyle(.roundedBorder)

                    TextField("Porta", text: $viewModel.portText)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Servidor")
                        .font(.headline)

                    HStack {
                        Button("Start Server") {
                            viewModel.startServer()
                        }
                        .disabled(viewModel.isStartingServer || viewModel.isServerRunning)

                        Button("Stop Server") {
                            viewModel.stopServer()
                        }
                        .disabled(viewModel.isStoppingServer || !viewModel.isServerRunning)
                    }
                }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cliente")
                        .font(.headline)

                    HStack {
                        Button("Connect Client") {
                            viewModel.connectClient()
                        }
                        .disabled(viewModel.isConnectingClient || viewModel.isServerRunning || viewModel.host.isEmpty)

                        Button("Disconnect Client") {
                            viewModel.disconnectClient()
                        }
                        .disabled(!viewModel.isClientConnected)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Partida")
                        .font(.headline)

                    HStack {
                        Button("Ready as Host") {
                            viewModel.readyAsHost()
                        }
                        .disabled(!viewModel.isServerRunning || viewModel.hostReady)

                        Button("Ready as Client") {
                            viewModel.readyAsClient()
                        }
                        .disabled(!viewModel.isClientConnected || viewModel.clientReady)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Chat")
                        .font(.headline)

                    TextField("Mensagem", text: $viewModel.message)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Enviar como cliente") {
                            viewModel.sendAsClient()
                        }
                        .disabled(viewModel.isSendingMessage || !viewModel.isClientConnected || viewModel.message.isEmpty)

                        Button("Enviar como host") {
                            viewModel.sendAsServer()
                        }
                        .disabled(!viewModel.isServerRunning || viewModel.message.isEmpty)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Log")
                        .font(.headline)

                    ForEach(viewModel.logs.indices, id: \.self) { index in
                        Text(viewModel.logs[index])
                    }
                }
            }
            .padding()
        }
    }
}
