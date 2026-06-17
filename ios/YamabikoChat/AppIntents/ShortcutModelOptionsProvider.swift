import AppIntents
import Foundation

private enum ShortcutModelOptionsSupport {
    static func modelOptions(for providerID: String) -> [String] {
        let settings = (try? AppServices.shared.settingsRepository.load()) ?? AppSettings()
        let openRouterModels = AppServices.shared.openRouterModelService.currentModels()
        return ShortcutModelOptionsBuilder.modelOptions(
            provider: providerID,
            settings: settings,
            openRouterModels: openRouterModels
        )
    }

    static func defaultProviderID() -> String {
        (try? AppServices.shared.settingsRepository.load().apiProvider) ?? "GEMINI"
    }
}

struct AskShortcutModelOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        ShortcutModelOptionsSupport.modelOptions(for: ShortcutModelOptionsSupport.defaultProviderID())
    }

    func defaultResult() async -> String? {
        ShortcutModelOptionsSupport.modelOptions(for: ShortcutModelOptionsSupport.defaultProviderID()).first
    }
}

struct SaveShortcutModelOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        ShortcutModelOptionsSupport.modelOptions(for: ShortcutModelOptionsSupport.defaultProviderID())
    }

    func defaultResult() async -> String? {
        ShortcutModelOptionsSupport.modelOptions(for: ShortcutModelOptionsSupport.defaultProviderID()).first
    }
}
