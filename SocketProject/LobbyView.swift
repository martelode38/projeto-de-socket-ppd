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
    }

    private var lobbyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Lobby")
                    .font(.title)

                Text(viewModel.matchStatusText)
                Text("Papel: \(viewModel.roleText)")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Conexão")
                    .font(.headline)

                Button(viewModel.serverButtonTitle) {
                    viewModel.toggleServer()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(viewModel.isServerButtonDisabled)

                if !viewModel.isServerRunning {
                    TextField("Endereço do servidor", text: $viewModel.host)
                        .textFieldStyle(.roundedBorder)

                    Button(viewModel.clientButtonTitle) {
                        viewModel.toggleClient()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(viewModel.isClientButtonDisabled)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Partida")
                    .font(.headline)

                Text(viewModel.matchStatusDetail)
                    .foregroundStyle(.secondary)

                Button(viewModel.readyButtonTitle) {
                    viewModel.markReady()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isReadyButtonDisabled)
            }

            ChatView(
                messages: viewModel.chatMessages,
                text: $viewModel.message,
                canSend: viewModel.canSendChatMessage,
                onSend: viewModel.sendChatMessage
            )

            Spacer(minLength: 0)
        }
        .padding()
    }
}
