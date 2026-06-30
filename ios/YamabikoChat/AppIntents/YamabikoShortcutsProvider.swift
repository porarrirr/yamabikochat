import AppIntents
import Foundation

struct YamabikoShortcutsProvider: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
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
                "\(.applicationName) Fusion に聞く",
                "\(.applicationName) fusion test"
            ],
            shortTitle: "Fusion に聞く",
            systemImageName: "arrow.triangle.merge"
        )
    }
}
