import SwiftUI

struct AutoConversationScreen: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自動会話はモデルA/Bの応答を交互に実行します。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Button(viewModel.isAutoConversationRunning ? "実行中" : "開始") {
                    if !viewModel.settings.isAutoConversationEnabled {
                        viewModel.toggleAutoConversation()
                    }
                    if !viewModel.inputText.isEmpty {
                        viewModel.sendMessage()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isAutoConversationRunning)

                Button("停止") {
                    viewModel.stopAutoConversation()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isAutoConversationRunning)
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
