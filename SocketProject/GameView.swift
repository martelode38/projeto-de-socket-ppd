//
//  GameView.swift
//  SocketProject
//
//  Created by OpenAI.
//

import SwiftUI

struct GameView: View {
    @ObservedObject var viewModel: LobbyViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fanorona")
                            .font(.title)
                        Text("Tela do jogo")
                    }

                    Spacer()

                    Button("Desconectar") {
                        viewModel.disconnectFromGame()
                    }
                }

                Text("Estado: \(viewModel.gameState.rawValue)")
                Text("Turno: \(viewModel.currentTurn == .white ? "Brancas" : "Pretas")")
                Text("Status: \(viewModel.boardStatus)")

                FanoronaBoardView(
                    board: viewModel.board,
                    selectedPosition: viewModel.selectedPosition,
                    onTapPosition: viewModel.handleBoardTap
                )
                .frame(minHeight: 360)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Chat")
                        .font(.headline)

                    Text("Jogador conectado: \(viewModel.connectedPlayerName)")

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

                VStack(alignment: .leading, spacing: 4) {
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

private struct FanoronaBoardView: View {
    let board: Board
    let selectedPosition: BoardPosition?
    let onTapPosition: (BoardPosition) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let inset = size * 0.08
            let usableSize = size - inset * 2
            let columnSpacing = usableSize / CGFloat(Board.columns - 1)
            let rowSpacing = usableSize / CGFloat(Board.rows - 1)

            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .overlay(
                        Rectangle()
                            .stroke(lineWidth: 1)
                    )

                Path { path in
                    for row in 0..<Board.rows {
                        let y = inset + CGFloat(row) * rowSpacing
                        path.move(to: CGPoint(x: inset, y: y))
                        path.addLine(to: CGPoint(x: inset + usableSize, y: y))
                    }

                    for column in 0..<Board.columns {
                        let x = inset + CGFloat(column) * columnSpacing
                        path.move(to: CGPoint(x: x, y: inset))
                        path.addLine(to: CGPoint(x: x, y: inset + usableSize))
                    }
                }
                .stroke(lineWidth: 1)

                ForEach(board.positions) { position in
                    let point = CGPoint(
                        x: inset + CGFloat(position.column) * columnSpacing,
                        y: inset + CGFloat(position.row) * rowSpacing
                    )

                    Button {
                        onTapPosition(position)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.gray.opacity(0.18))
                                .frame(width: size * 0.09, height: size * 0.09)

                            if selectedPosition == position {
                                Circle()
                                    .stroke(lineWidth: 2)
                                    .frame(width: size * 0.10, height: size * 0.10)
                            }

                            if let piece = board.piece(at: position) {
                                Circle()
                                    .fill(piece.owner == .white ? .white : .black)
                                    .overlay(
                                        Circle()
                                            .stroke(lineWidth: 1)
                                    )
                                    .frame(width: size * 0.08, height: size * 0.08)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .position(point)
                }
            }
        }
    }
}
