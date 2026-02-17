import SwiftUI

struct AutoConversationScreen: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自動会話はモデルA/Bの応答を交互に実行します。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("開始メッセージを入力", text: $viewModel.inputText)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.isAutoConversationRunning || viewModel.isAutoConversationPaused)

            HStack {
                Button(viewModel.isAutoConversationRunning ? L10n.text("実行中") : L10n.text("開始")) {
                    if !viewModel.settings.isAutoConversationEnabled {
                        viewModel.toggleAutoConversation()
                        return
                    }
                    viewModel.startAutoConversationManually()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isAutoConversationRunning || viewModel.isAutoConversationPaused)

                Button("一時停止") {
                    viewModel.pauseAutoConversation()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isAutoConversationRunning)

                Button("再開") {
                    viewModel.resumeAutoConversation()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isAutoConversationPaused)

                Button("停止") {
                    viewModel.stopAutoConversation()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isAutoConversationRunning && !viewModel.isAutoConversationPaused)
            }

            if let status = viewModel.autoConversationStatus {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }
}
