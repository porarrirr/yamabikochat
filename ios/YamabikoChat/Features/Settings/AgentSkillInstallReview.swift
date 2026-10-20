import SwiftUI

struct AgentSkillInstallReview: View {
    let preview: AgentSkillInstallPreview
    let onCancel: () -> Void
    let onInstall: (Bool) -> Void
    @State private var trusted = false

    var body: some View {
        NavigationStack {
            AMOLEDForm {
                Section("Skill") {
                    LabeledContent("名前", value: preview.manifest.name)
                    Text(preview.manifest.description)
                    if let license = preview.manifest.license { LabeledContent("ライセンス", value: license) }
                    if let compatibility = preview.manifest.compatibility { LabeledContent("互換性", value: compatibility) }
                }
                Section("能力と危険性") {
                    LabeledContent("スクリプト", value: preview.hasScripts ? "あり" : "なし")
                    LabeledContent("allowed-tools", value: preview.manifest.allowedTools.isEmpty ? "なし" : preview.manifest.allowedTools.joined(separator: ", "))
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
