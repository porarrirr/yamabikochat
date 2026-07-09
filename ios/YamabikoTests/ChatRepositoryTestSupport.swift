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
        httpClient: HTTPClientProtocol,
        pricingRepository: (any LiteLlmPricingEstimating)? = nil
    ) -> ChatRepository {
        let modelService = OpenRouterModelService(credentialStore: credentials)
        let codexAuth = CodexAuthRepository(credentialStore: credentials)
        let superGrokAuth = SuperGrokAuthRepository(credentialStore: credentials)
        let providers = ProviderGateway(
            settingsRepository: settings,
            credentialStore: credentials,
            httpClient: httpClient,
            superGrokAuthRepository: superGrokAuth
        )
        let fusionTraceStore = FusionTraceStore(dbQueue: dbQueue)
        let fusionService = FusionService(
            settingsRepository: settings,
            providerGateway: providers,
            pricingRepository: pricingRepository ?? LiteLlmPricingRepository(),
            traceStore: fusionTraceStore
        )
        return ChatRepository(
            conversations: conversations,
            settings: settings,
            providers: providers,
            credentialStore: credentials,
            modelService: modelService,
            codexAuthRepository: codexAuth,
            superGrokAuthRepository: superGrokAuth,
            pricingRepository: pricingRepository ?? LiteLlmPricingRepository(),
            fusionService: fusionService,
            fusionTraceStore: fusionTraceStore
        )
    }
}