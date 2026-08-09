import Foundation

struct ProviderRegistry {
    private let openAICompatible: OpenAICompatibleProviderClient
    private let anthropicCompatible: AnthropicCompatibleProviderClient
    private let openCodeGo: OpenCodeGoProviderClient
    private let gemini: GeminiProviderClient
    private let codex: CodexProviderClient
    private let superGrok: SuperGrokProviderClient
    private let appleIntelligence: AppleIntelligenceProviderClient
    private let openAIHostedSkills: OpenAIHostedSkillsProviderClient?

    init(skillRepository: AgentSkillRepository? = nil, attachmentRepository: AttachmentRepository? = nil) {
        openAICompatible = OpenAICompatibleProviderClient()
        anthropicCompatible = AnthropicCompatibleProviderClient()
        openCodeGo = OpenCodeGoProviderClient()
        gemini = GeminiProviderClient()
        codex = CodexProviderClient()
        superGrok = SuperGrokProviderClient()
        appleIntelligence = AppleIntelligenceProviderClient()
        if let skillRepository, let attachmentRepository {
            openAIHostedSkills = OpenAIHostedSkillsProviderClient(manager: OpenAISkillContainerManager(skillRepository: skillRepository), attachmentRepository: attachmentRepository)
        } else { openAIHostedSkills = nil }
    }

    func client(for provider: LLMProvider) -> ProviderClient {
        switch provider {
        case .gemini:
            return gemini
        case .codexAuth:
            return codex
        case .superGrok:
            return superGrok
        case .appleIntelligence:
            return appleIntelligence
        case .openCodeGo:
            return openCodeGo
        case .alibabaCodingPlan:
            return anthropicCompatible
        case .openRouter, .openAI, .openAICompat, .miniMax, .zai, .clinePass:
            return openAICompatible
        }
    }

    func client(for provider: LLMProvider, request: ProviderRequest) throws -> ProviderClient {
        if provider == .openAI,
           request.skillContext?.hostedExecutionEnabled == true,
           request.skillContext?.catalog.isEmpty == false {
            guard let openAIHostedSkills else {
                throw ProviderClientError.parseFailure("OpenAI hosted Skill client is unavailable")
            }
            return openAIHostedSkills
        }
        return client(for: provider)
    }
}
