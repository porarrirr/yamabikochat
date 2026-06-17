import AppIntents
import Foundation

struct RunYamabikoModelIntent: AppIntent {
    static var title: LocalizedStringResource = "モデルに聞く"
    static var description = IntentDescription(LocalizedStringResource("Shortcuts: モデルに聞く説明"))
    static var openAppWhenRun: Bool = false

    @Parameter(title: LocalizedStringResource("Shortcuts: プロンプト"))
    var prompt: String

    @Parameter(title: LocalizedStringResource("Shortcuts: プロバイダ"))
    var provider: ShortcutProviderAppEnum

    @Parameter(
        title: LocalizedStringResource("Shortcuts: モデル ID"),
        optionsProvider: AskShortcutModelOptionsProvider()
    )
    var model: String

    @Parameter(
        title: LocalizedStringResource("Shortcuts: システムプロンプト"),
        default: nil
    )
    var systemPrompt: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Shortcuts: モデルに聞く要約") {
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
            saveToNewConversation: false
        )
    }
}
