import SwiftUI

struct AgentSkillInstallReview: View {
    let preview: AgentSkillInstallPreview
    let onCancel: () -> Void
    let onInstall: (Bool) -> Void
    @State private var trusted = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Skill") {
                    LabeledContent("名前", value: preview.manifest.name)
                    Text(preview.manifest.description)
                    if let license = preview.manifest.license { LabeledContent("ライセンス", value: license) }
                    if let compatibility = preview.manifest.compatibility { LabeledContent("互換性", value: compatibility) }
                    if preview.replacesExisting { Text("同名Skillを置換します。有効状態は維持されます。").foregroundStyle(.orange) }
                }
                Section("能力と危険性") {
                    LabeledContent("スクリプト", value: preview.hasScripts ? "あり（端末では実行しません）" : "なし")
                    LabeledContent("allowed-tools", value: preview.manifest.allowedTools.isEmpty ? "なし" : preview.manifest.allowedTools.joined(separator: ", "))
                    Text("allowed-toolsは表示情報であり、権限を自動付与しません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !preview.externalURLs.isEmpty {
                    Section("外部URLらしき記述") {
                        ForEach(preview.externalURLs, id: \.self) { Text($0).font(.caption.monospaced()) }
                    }
                }
                Section("全ファイル（\(preview.files.count)）") {
                    ForEach(preview.files) { file in
                        HStack {
                            Text(file.path).font(.caption.monospaced())
                            Spacer()
                            if file.isScript { Image(systemName: "terminal").foregroundStyle(.orange) }
                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).font(.caption2)
                        }
                    }
                }
                Section {
                    Toggle("内容を確認し、このSkillを信頼します", isOn: $trusted)
                } footer: {
                    Text("Skillの指示と資料は外部モデルへ送信される場合があります。ローカルでスクリプトは実行しません。")
                }
            }
            .navigationTitle("Agent Skillを確認")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) { Button(preview.replacesExisting ? "置換" : "インストール") { onInstall(trusted) }.disabled(!trusted) }
            }
        }
    }
}
