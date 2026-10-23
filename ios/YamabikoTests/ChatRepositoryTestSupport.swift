import GRDB
@testable import YamabikoChat

final class ConversationTitleGeneratorSpy: ConversationTitleGenerating {
    struct Request: Equatable {
        var firstPrompt: String
        var firstResponse: String
    }

    private(set) var requests: [Request] = []
    var generatedTitle: String?

    init(generatedTitle: String? = nil) {
        self.generatedTitle = generatedTitle
    }

    func generateTitle(firstPrompt: String, firstResponse: String) async throws -> String? {
        requests.append(Request(firstPrompt: firstPrompt, firstResponse: firstResponse))
        return generatedTitle
    }
}

struct ChatTestNoopPricingRepository: LiteLlmPricingEstimating {
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
        codexAuthRepository: CodexAuthRepository? = nil,
        superGrokAuthRepository: SuperGrokAuthRepository? = nil,
        openCodeGoUsageRepository: OpenCodeGoUsageRepository? = nil,
        pricingRepository: (any LiteLlmPricingEstimating)? = nil,
        conversationTitleGenerator: any ConversationTitleGenerating = ConversationTitleGeneratorSpy()
    ) -> ChatRepository {
        let resolvedModelService = modelService ?? OpenRouterModelService(credentialStore: credentials)
        let requestSettingsResolver = ProviderRequestSettingsResolver(
            modelService: resolvedModelService,
            modelsDevCatalogRepository: modelsDevCatalogRepository
        )
        let codexAuth = codexAuthRepository ?? CodexAuthRepository(credentialStore: credentials)
        let superGrokAuth = superGrokAuthRepository ?? SuperGrokAuthRepository(credentialStore: credentials)
        let providers = ProviderGateway(
            settingsRepository: settings,
            credentialStore: credentials,
            codexAuthRepository: codexAuth,
            superGrokAuthRepository: superGrokAuth,
            piStream: piStream
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
            pricingRepository: pricingRepository ?? ChatTestNoopPricingRepository(),
            conversationTitleGenerator: conversationTitleGenerator
        )
    }
}
