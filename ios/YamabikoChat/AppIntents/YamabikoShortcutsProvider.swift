import AppIntents
import Foundation

struct YamabikoShortcutsProvider: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskYamabikoIntent(),
            phrases: ["\(.applicationName) に質問", "\(.applicationName) に聞く"],
            shortTitle: "やまびこに質問",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: OpenConversationIntent(),
            phrases: ["\(.applicationName) で会話を開く", "\(.applicationName) で \(\.$target) を開く"],
            shortTitle: "会話を開く",
            systemImageName: "bubble.left.and.bubble.right"
        )
        AppShortcut(
            intent: FindConversationsIntent(),
            phrases: ["\(.applicationName) で会話を検索"],
            shortTitle: "会話を検索",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: RunYamabikoModelIntent(),
            phrases: [
                "Shortcuts: \(.applicationName) でモデルに聞く",
                "\(.applicationName) モデルに聞く"
            ],
            shortTitle: LocalizedStringResource("モデルに聞く"),
            systemImageName: "bubble.left.and.text.bubble.right"
        )
        AppShortcut(
            intent: RunAndSaveYamabikoModelIntent(),
            phrases: [
                "Shortcuts: \(.applicationName) でモデルに聞いて保存",
                "\(.applicationName) モデルに聞いて保存"
            ],
            shortTitle: LocalizedStringResource("モデルに聞いて保存"),
            systemImageName: "square.and.arrow.down"
        )
        AppShortcut(
            intent: RunFusionIntent(),
            phrases: [
                "Shortcuts: \(.applicationName) で Fusion に聞く",
                "\(.applicationName) Fusion に聞く"
            ],
            shortTitle: LocalizedStringResource("Fusion に聞く"),
            systemImageName: "arrow.triangle.merge"
        )
    }
}
