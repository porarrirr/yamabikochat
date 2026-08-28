import Foundation

enum AppStoreScreenshotDemoSeeder {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-AppStoreScreenshotDemo")
    }

    @MainActor
    static func seedIfNeeded(chatRepository: ChatRepository, conversations: ConversationRepository) {
        guard isEnabled else { return }

        do {
            try seed(chatRepository: chatRepository, conversations: conversations)
            DiagnosticsLogger.log("App Store screenshot demo data seeded", category: .app)
        } catch {
            DiagnosticsLogger.log("App Store screenshot demo seed failed", category: .app, error: error)
        }
    }

    @MainActor
    private static func seed(chatRepository: ChatRepository, conversations: ConversationRepository) throws {
        let isReasoningEffortFixture = ProcessInfo.processInfo.arguments.contains(
            "-ReasoningEffortSliderFixture"
        )
        var settings = try chatRepository.loadSettings()
        settings.themeMode = isReasoningEffortFixture ? "DARK" : "LIGHT"
        settings.dynamicColorEnabled = true
        settings.isDualModeEnabled = !isReasoningEffortFixture
        settings.isFusionModeEnabled = false
        settings.isAutoConversationEnabled = false
        settings.apiProvider = isReasoningEffortFixture ? "CODEX_AUTH" : "OPENROUTER"
        settings.defaultModel = isReasoningEffortFixture ? "gpt-5.6-terra" : "openai/gpt-4o-mini"
        settings.codexReasoningEnabled = true
        settings.codexReasoningEffort = "medium"
        settings.dualProviderA = "OPENAI"
        settings.dualModelA = "gpt-4o-mini"
        settings.dualProviderB = "GEMINI"
        settings.dualModelB = "gemini-2.5-flash-preview"
        _ = try chatRepository.saveSettings(settings)

        let baseTime = Int64(Date().timeIntervalSince1970 * 1000)
        if ProcessInfo.processInfo.arguments.contains("-ChatTextSelectionFixture") {
            let conversationId = try chatRepository.createConversation(title: "Text Selection Fixture")
            _ = try conversations.insertMessage(
                ChatMessage(
                    conversationId: conversationId,
                    role: "assistant",
                    text: """
                    First selectable paragraph.

                    Second selectable paragraph.

                    Third selectable paragraph.
                    """,
                    createdAtMs: baseTime + 240_000
                )
            )
        }

        let projectId = try chatRepository.createProject(
            title: "仕事用",
            instructions: "簡潔で実務的な日本語で回答してください。"
        )

        let samples: [(title: String, projectId: Int64?, user: String, assistant: String)] = [
            (
                "Markdown 数式",
                nil,
                "フィボナッチ数列を Swift で書いて、数式も示して。",
                """
                ### フィボナッチ数列

                ```swift
                func fib(_ n: Int) -> Int {
                    guard n > 1 else { return n }
                    return fib(n - 1) + fib(n - 2)
                }
                ```

                漸化式: `f(n) = f(n-1) + f(n-2)`

                | n | f(n) |
                |---|------|
                | 0 | 0 |
                | 1 | 1 |
                | 8 | 21 |
                """
            ),
            (
                "API 設計レビュー",
                projectId,
                "REST API のエラーレスポンス設計のベストプラクティスを教えて。",
                """
                **おすすめの形**

                1. HTTP ステータスで大分類（4xx / 5xx）
                2. ボディは `code`, `message`, `details` を分離
                3. クライアントが再試行できるか `retryable` を明示

                > 同じエラーでも、ユーザー向け文言と開発者向け `details` は分けると運用が楽です。
                """
            ),
            (
                "英語メール推敲",
                nil,
                "次の文を丁寧なビジネス英語に直して: I will send document tomorrow.",
                """
                **提案文**

                I will share the document with you tomorrow.

                **補足**

                - `send` より `share` の方が資料共有の文脈で自然です
                - 具体時刻があるなら `by 3:00 p.m. JST` を追加すると親切です
                """
            ),
            (
                "旅行プラン",
                nil,
                "京都の半日観光プランを箇条書きで。",
                """
                **午前**

                - 清水寺 → 二年坂・三年坂
                - 産寧坂で休憩

                **午後**

                - 伏見稲荷大社（千本鳥居）
                - 錦市場で食事

                移動は地下鉄 + 徒歩がおすすめです。
                """
            )
        ]

        for (index, sample) in samples.enumerated() {
            let conversationId = try chatRepository.createConversation(
                title: sample.title,
                projectId: sample.projectId
            )
            let offset = Int64(index * 60_000)
            _ = try conversations.insertMessage(
                ChatMessage(
                    conversationId: conversationId,
                    role: "user",
                    text: sample.user,
                    createdAtMs: baseTime + offset
                )
            )
            _ = try conversations.insertMessage(
                ChatMessage(
                    conversationId: conversationId,
                    role: "assistant",
                    text: sample.assistant,
                    createdAtMs: baseTime + offset + 1_000
                )
            )
        }

        if ProcessInfo.processInfo.arguments.contains("-ChatTimelinePerformanceFixture") {
            let conversationId = try chatRepository.createConversation(title: "Timeline Performance Fixture")
            for index in 0..<200 {
                let isLast = index == 199
                let text = isLast
                    ? "Fixture message 199\n\n" + String(repeating: "Long streaming content for native Markdown. ", count: 750)
                    : "Fixture message \(index)\n\n- Stable row identity\n- Native Markdown block"
                _ = try conversations.insertMessage(
                    ChatMessage(
                        conversationId: conversationId,
                        role: index.isMultiple(of: 2) ? "user" : "assistant",
                        text: text,
                        createdAtMs: baseTime + 300_000 + Int64(index)
                    )
                )
            }
        }
    }
}
