import Foundation

enum AppStoreScreenshotDemoSeeder {
    static let mathRenderingFixtureText = #"""
        サブエージェント3つに、それぞれ別の導き方を依頼しました。3つの回答をまとめると、球の半径を \(r\)、表面積を \(S\) として、いずれも

        \[
        \boxed{S=4\pi r^2}
        \]

        になります。

        ### 1. 球面を薄い帯に分けて足し合わせる
        球の中心から高さ \(z\) にある細い帯の面積を考えます。断面の円の半径を \(\rho\)、帯の球面に沿った幅を \(ds\) とすると、断面の関係から \(\rho^2+z^2=r^2\)、また \(ds=\frac{r}{\rho}dz\) です。帯の面積は円周×幅なので、

        \[
        dS=2\pi\rho\,ds=2\pi r\,dz.
        \]

        球の高さ全体 \(-r\) から \(r\) まで足すと、

        \[
        S=\int_{-r}^{r}2\pi r\,dz=4\pi r^2.
        \]

        ### 2. 球帯の面積を使う
        球を高さ \(dy\) の薄い輪切りにします。その輪切りの円周は \(2\pi\sqrt{r^2-y^2}\) です。球面に沿った幅は \(ds=\frac{r}{\sqrt{r^2-y^2}}dy\) なので、薄い球帯の面積は

        \[
        dA=2\pi\sqrt{r^2-y^2}\,ds=2\pi r\,dy.
        \]

        これを球の高さ全体にわたって積分すれば、

        \[
        S=\int_{-r}^{r}2\pi r\,dy=4\pi r^2.
        \]

        ### 3. 球の体積を半径で微分する
        半径 \(r\) の球の体積は \(V(r)=\frac{4}{3}\pi r^3\) です。半径を少しだけ増やしたときの体積の増加は、表面積×半径の増加分に相当するため、表面積は体積を半径で微分して求められます。

        \[
        S=\frac{dV}{dr}
        =\frac{d}{dr}\left(\frac{4}{3}\pi r^3\right)
        =4\pi r^2.
        \]

        **使い分けの目安：** 1と2は球面を細い帯に分ける考え方で、3は球の体積の公式を知っているときに使える方法です。直径 \(d\) が与えられた場合は \(r=d/2\) を代入して、\(S=\pi d^2\) です。
        """#

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
        let isGenUIFixture = ProcessInfo.processInfo.arguments.contains("-GenUIFixture")
            || ProcessInfo.processInfo.arguments.contains("-GenUIRichFixture")
        var settings = try chatRepository.loadSettings()
        settings.themeMode = isReasoningEffortFixture || ProcessInfo.processInfo.arguments.contains("-GenUIDarkFixture") ? "DARK" : "LIGHT"
        settings.dynamicColorEnabled = true
        settings.isDualModeEnabled = !isReasoningEffortFixture && !isGenUIFixture && !ProcessInfo.processInfo.arguments.contains("-SubagentFixture")
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
        if ProcessInfo.processInfo.arguments.contains("-SubagentFixture") {
            settings.apiProvider = "GEMINI"
            settings.defaultModel = "gemini-2.5-flash"
            settings.subagents = SubagentSettings()
        }
        _ = try chatRepository.saveSettings(settings)

        if ProcessInfo.processInfo.arguments.contains("-MathRenderingFixture") {
            settings.isDualModeEnabled = false
            settings.themeMode = ProcessInfo.processInfo.arguments.contains("-MathDarkFixture") ? "DARK" : "LIGHT"
            _ = try chatRepository.saveSettings(settings)
            let conversationId = try chatRepository.createConversation(title: "表面積の計算 TeX Fixture")
            _ = try conversations.insertMessage(ChatMessage(
                conversationId: conversationId,
                role: "model",
                text: mathRenderingFixtureText,
                createdAtMs: Int64(Date().timeIntervalSince1970 * 1000)
            ))
            return
        }

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
        if isGenUIFixture {
            try GenUIDemoFixture.seed(chatRepository: chatRepository, conversations: conversations, timestamp: baseTime + 500_000)
        }
        if ProcessInfo.processInfo.arguments.contains("-GenUIRichFixture") {
            try GenUIRichDemoFixture.seed(chatRepository: chatRepository, conversations: conversations, timestamp: baseTime + 600_000)
        }
        if ProcessInfo.processInfo.arguments.contains("-SubagentFixture") {
            try SubagentDemoFixture.seed(chatRepository: chatRepository, conversations: conversations, timestamp: baseTime + 700_000)
        }
    }
}
