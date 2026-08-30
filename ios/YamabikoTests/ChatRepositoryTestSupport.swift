import GRDB
@testable import YamabikoChat

struct FusionNoopPricingRepository: LiteLlmPricingEstimating {
    func estimateCostUsd(
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int?,
        cacheCreationInputTokens: Int?,
        reasoningTokens: Int?
    ) async -> Double? {
        nil
    }

    func modelSupportsVision(provider: String, model: String) async -> Bool {
        false
    }
}

enum ChatRepositoryTestSupport {
    static func makeRepository(
        dbQueue: DatabaseQueue,
        settings: SettingsRepository,
        conversations: ConversationRepository,
        credentials: SecureCredentialStore,
        piStream: @escaping PiAgentStream = PiStreamSpy().stream,
        modelService: OpenRouterModelService? = nil,
        modelsDevCatalogRepository: ModelsDevCatalogRepository? = nil,
        openCodeGoUsageRepository: OpenCodeGoUsageRepository? = nil,
        pricingRepository: (any LiteLlmPricingEstimating)? = nil
    ) -> ChatRepository {
        let resolvedModelService = modelService ?? OpenRouterModelService(credentialStore: credentials)
        let requestSettingsResolver = ProviderRequestSettingsResolver(
            modelService: resolvedModelService,
            modelsDevCatalogRepository: modelsDevCatalogRepository
        )
        let codexAuth = CodexAuthRepository(credentialStore: credentials)
        let superGrokAuth = SuperGrokAuthRepository(credentialStore: credentials)
        let providers = ProviderGateway(
            settingsRepository: settings,
            credentialStore: credentials,
            superGrokAuthRepository: superGrokAuth,
            piStream: piStream
        )
        let fusionTraceStore = FusionTraceStore(dbQueue: dbQueue)
        let fusionService = FusionService(
            settingsRepository: settings,
            providerGateway: providers,
            pricingRepository: pricingRepository ?? LiteLlmPricingRepository(),
            traceStore: fusionTraceStore,
            requestSettingsResolver: requestSettingsResolver
        )
        return ChatRepository(
            conversations: conversations,
            settings: settings,
            providers: providers,
            credentialStore: credentials,
            modelService: resolvedModelService,
            modelsDevCatalogRepository: modelsDevCatalogRepository,
            requestSettingsResolver: requestSettingsResolver,
            codexAuthRepository: codexAuth,
            superGrokAuthRepository: superGrokAuth,
            openCodeGoUsageRepository: openCodeGoUsageRepository,
            pricingRepository: pricingRepository ?? LiteLlmPricingRepository(),
            fusionService: fusionService,
            fusionTraceStore: fusionTraceStore
        )
    }
}
