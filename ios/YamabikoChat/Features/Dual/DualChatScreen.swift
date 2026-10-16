import SwiftUI

struct DualChatScreen: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("現在の入力をデュアル送信") {
                if !viewModel.settings.isDualModeEnabled {
                    viewModel.toggleDualMode()
                }
                viewModel.sendMessage()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.inputText.isEmpty || viewModel.isSending)

            List(viewModel.dualMessages) { message in
                VStack(alignment: .leading, spacing: 8) {
                    Text("ユーザー")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(message.userText)
                        .font(.body)

                    Divider()
                    Text("A (\(message.modelAName))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(message.modelAText)

                    Divider()
                    Text("B (\(message.modelBName))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(message.modelBText)
                }
                .padding(.vertical, 6)
            }
        }
        .padding()
    }
}
