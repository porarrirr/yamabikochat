#if DEBUG
import Foundation

/// Deterministic UI test data; never used for normal conversations or model execution.
enum SubagentDemoFixture {
    static let title = "サブエージェントの調査"

    @MainActor
    static func seed(chatRepository: ChatRepository, conversations: ConversationRepository, timestamp: Int64) throws {
        let conversation: Int64
        let message: Int64
        if let existing = try conversations.siriConversations(matching: title).first(where: { $0.title == title })?.id,
           let existingMessage = try conversations.fetchLastAssistantMessage(conversationId: existing)?.id {
            conversation = existing
            message = existingMessage
        } else {
            conversation = try chatRepository.createConversation(title: title)
            _ = try conversations.insertMessage(ChatMessage(conversationId: conversation, role: "user",
                text: "3つのサブエージェントで、資料調査・実装確認・テストを並行して進めてください。", createdAtMs: timestamp))
            message = try conversations.insertMessage(ChatMessage(conversationId: conversation, role: "assistant",
                text: "調査を3つに分けて進めています。\n\n各エージェントの依頼内容・処理履歴・結果は、上のサマリーから確認できます。通常のチャットもそのまま使えます。", createdAtMs: timestamp + 1))
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var payload = ToolActivityPayload()
        for (index, name) in ["資料調査", "実装確認", "テスト確認"].enumerated() {
            payload.applySubagent(SubagentRun(id: "fixture-\(index)", agent: name,
                task: "\(name)を担当してください。確認した根拠と具体的な結果を日本語で報告してください。",
                provider: index == 1 ? "openai" : "google", model: index == 1 ? "gpt-5.5" : "gemini-3.1-pro-preview",
                effort: "medium", status: index == 0 ? .completed : .running,
                activity: index == 0 ? "完了" : index == 1 ? "fetch_url を実行中" : "テスト結果を確認中",
                startedAtMs: now - 12_000, updatedAtMs: now, finishedAtMs: index == 0 ? now : nil,
                output: index == 0 ? "公式資料から、モデルの継承仕様を確認できました。" : """
                ## \(name)の確認結果

                \(name)の途中結果です。既存の処理との接続を確認しています。

                - **設定**：親のモデル設定を継承します。
                - **表示**：[公式資料](https://pi.dev)と照合しています。

                ```swift
                let result = "確認中"
                ```

                | 項目 | 状態 |
                | --- | --- |
                | 接続 | 確認済み |
                """,
                outputTruncated: false,
                events: [.init(id: "\(index)-started", kind: "started", title: "子セッションを開始", detail: "\(name)を開始しました", createdAtMs: now - 12_000),
                    .init(id: "\(index)-tool", kind: "tool_start", title: "fetch_url", detail: "https://pi.dev/packages/pi-subagents", createdAtMs: now - 4_000),
                    .init(id: "\(index)-result", kind: "tool_end", title: "資料を取得", detail: "公式ドキュメントの該当箇所を取得しました。", createdAtMs: now - 1_000)],
                eventsTruncated: false, usage: nil, error: nil))
        }
        try conversations.saveToolActivity(messageId: message, variantId: nil, payload: payload)
        if ProcessInfo.processInfo.arguments.contains("-SubagentLiveFixture") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(12))
                var updated = payload.subagents[1]
                updated.output = "ライブ更新の結果：実装と設定の接続を確認できました。"
                updated.status = .completed
                updated.activity = "完了"
                updated.updatedAtMs += 12_000
                updated.finishedAtMs = updated.updatedAtMs
                payload.applySubagent(updated)
                try? conversations.saveToolActivity(messageId: message, variantId: nil, payload: payload)
            }
        }
    }
}

#endif
