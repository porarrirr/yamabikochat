import AppIntents
import Foundation

enum ShortcutIntentSupport {
    static func perform(
        prompt: String,
        provider: ShortcutProviderAppEnum,
        model: String,
        systemPrompt: String?,
        saveToNewConversation: Bool
    ) async throws -> some IntentResult & ReturnsValue<String> {
        let trimmedSystemPrompt = systemPrompt?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSystemPrompt = trimmedSystemPrompt?.isEmpty == false ? trimmedSystemPrompt : nil

        do {
            let result = try await AppServices.shared.chatRepository.runShortcut(
                prompt: prompt,
                provider: provider.providerKey,
                model: model,
                systemPromptOverride: resolvedSystemPrompt,
                saveToNewConversation: saveToNewConversation
            )
            return .result(
                value: result.text,
                dialog: IntentDialog(stringLiteral: L10n.text("Shortcuts: 完了しました。"))
            )
        } catch {
            DiagnosticsLogger.log(
                saveToNewConversation ? "Shortcut save intent failed" : "Shortcut intent failed",
                category: .chat,
                metadata: [
                    "provider": provider.providerKey,
                    "model": model
                ],
                error: error
            )
            throw error
        }
    }
}
