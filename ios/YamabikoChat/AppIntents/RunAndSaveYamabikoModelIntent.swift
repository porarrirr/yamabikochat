import AppIntents
import Foundation

struct RunAndSaveYamabikoModelIntent: AppIntent {
    static var title: LocalizedStringResource = "モデルに聞いて保存"
    static var description = IntentDescription(LocalizedStringResource("Shortcuts: モデルに聞いて保存説明"))
    static var openAppWhenRun: Bool = false

    @Parameter(title: LocalizedStringResource("Shortcuts: プロンプト"))
    var prompt: String

    @Parameter(title: LocalizedStringResource("Shortcuts: プロバイダ"))
    var provider: ShortcutProviderAppEnum

    @Parameter(
        title: LocalizedStringResource("Shortcuts: モデル ID"),
        optionsProvider: SaveShortcutModelOptionsProvider()
    )
    var model: String

    @Parameter(
        title: LocalizedStringResource("Shortcuts: システムプロンプト"),
        default: nil
    )
    var systemPrompt: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Shortcuts: モデルに聞いて保存要約") {
            \.$prompt
            \.$provider
            \.$model
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        try await ShortcutIntentSupport.perform(
            prompt: prompt,
            provider: provider,
            model: model,
            systemPrompt: systemPrompt,
            saveToNewConversation: true
        )
    }
}
