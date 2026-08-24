import AppIntents
import Foundation

private enum ShortcutModelOptionsSupport {
    static func modelOptions(for providerID: String) throws -> [String] {
        let services = try AppServices.resolve()
        let settings = try services.settingsRepository.load()
        let openRouterModels = services.openRouterModelService.currentModels()
        return ShortcutModelOptionsBuilder.modelOptions(
            provider: providerID,
            settings: settings,
            openRouterModels: openRouterModels
        )
    }

    static func defaultProviderID() throws -> String {
        try AppServices.resolve().settingsRepository.load().apiProvider
    }
}

struct AskShortcutModelOptionsProvider: DynamicOptionsProvider {
    @IntentParameterDependency<RunYamabikoModelIntent>(\.$provider)
    private var intent

    func results() async throws -> [String] {
        try ShortcutModelOptionsSupport.modelOptions(
            for: try intent?.provider.providerKey ?? ShortcutModelOptionsSupport.defaultProviderID()
        )
    }

    func defaultResult() async -> String? {
        guard let provider = intent?.provider.providerKey ?? (try? ShortcutModelOptionsSupport.defaultProviderID()) else {
            return nil
        }
        return try? ShortcutModelOptionsSupport.modelOptions(for: provider).first
    }
}

struct SaveShortcutModelOptionsProvider: DynamicOptionsProvider {
    @IntentParameterDependency<RunAndSaveYamabikoModelIntent>(\.$provider)
    private var intent

    func results() async throws -> [String] {
        try ShortcutModelOptionsSupport.modelOptions(
            for: try intent?.provider.providerKey ?? ShortcutModelOptionsSupport.defaultProviderID()
        )
    }

    func defaultResult() async -> String? {
        guard let provider = intent?.provider.providerKey ?? (try? ShortcutModelOptionsSupport.defaultProviderID()) else {
            return nil
        }
        return try? ShortcutModelOptionsSupport.modelOptions(for: provider).first
    }
}
