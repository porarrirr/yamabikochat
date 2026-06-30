import Foundation

enum FusionPhase: String, Codable, Sendable {
    case panel
    case judge
    case synthesizer
    case fallback
}

enum FusionTaskType: String, Codable, Sendable, CaseIterable {
    case research
    case coding
    case auto
}

enum FusionConfidence: String, Codable, Sendable {
    case low
    case medium
    case high
}

struct PanelModelConfig: Codable, Sendable, Equatable {
    var modelId: String
    var provider: String
    var temperature: Double?
    var maxTokens: Int?
    var timeoutMs: Int?
    var role: String?
}

struct FusionRequest: Codable, Sendable, Equatable {
    var userPrompt: String
    var systemPrompt: String?
    var panelModels: [PanelModelConfig]
    var judgeModel: PanelModelConfig
    var synthesizerModel: PanelModelConfig
    var fallbackModel: PanelModelConfig?
    var preset: String
    var maxPanelTokens: Int
    var maxJudgeTokens: Int
    var maxSynthesizerTokens: Int
    var timeoutMs: Int
    var allowWebSearch: Bool
    var taskType: FusionTaskType
    var metadata: [String: String]
}

struct PanelResult: Codable, Sendable, Equatable {
    var modelId: String
    var provider: String
    var success: Bool
    var content: String
    var error: String?
    var latencyMs: Int64
    var inputTokens: Int?
    var outputTokens: Int?
    var cost: Double?
    var toolCalls: [ToolCall]?
    var finishReason: String?
    var role: String?
}

struct JudgeContradiction: Codable, Sendable, Equatable {
    var topic: String
    var positions: [String]
    var likelyResolution: String
    var confidence: FusionConfidence
}

struct JudgeUniqueInsight: Codable, Sendable, Equatable {
    var model: String
    var insight: String
    var useInFinal: Bool
}

struct JudgeSuspectedError: Codable, Sendable, Equatable {
    var model: String
    var claim: String
    var reason: String
}

struct JudgeStrongestPart: Codable, Sendable, Equatable {
    var model: String
    var part: String
    var reason: String
}

struct JudgeAnalysis: Codable, Sendable, Equatable {
    var consensus: [String]
    var contradictions: [JudgeContradiction]
    var uniqueInsights: [JudgeUniqueInsight]
    var coverageGaps: [String]
    var suspectedErrors: [JudgeSuspectedError]
    var sourceQualityIssues: [String]
    var strongestAnswerParts: [JudgeStrongestPart]
    var recommendedFinalPosition: String
    var confidence: FusionConfidence
    var notes: String?
}

struct JudgePhaseResult: Codable, Sendable, Equatable {
    var analysis: JudgeAnalysis?
    var rawJSON: String?
    var parseSucceeded: Bool
    var latencyMs: Int64
    var inputTokens: Int?
    var outputTokens: Int?
    var cost: Double?
    var error: String?
}

struct SynthesisPhaseResult: Codable, Sendable, Equatable {
    var modelId: String
    var provider: String
    var success: Bool
    var content: String
    var latencyMs: Int64
    var inputTokens: Int?
    var outputTokens: Int?
    var cost: Double?
    var error: String?
    var usedFallback: Bool
}

struct FusionTrace: Codable, Sendable, Equatable {
    var requestId: String
    var preset: String
    var startedAtMs: Int64
    var completedAtMs: Int64?
    var panelResults: [PanelResult]
    var judgeResult: JudgePhaseResult?
    var synthesisResult: SynthesisPhaseResult?
    var totalLatencyMs: Int64?
    var totalCost: Double?
    var failedModels: [String]
    var status: String
    var userPrompt: String?
    var finalAnswer: String?
}

struct FusionContext: Sendable, Equatable {
    static let maxFusionDepth = 1

    var fusionDepth: Int
    var debugMode: Bool
    var logPrompts: Bool
    var conversationId: Int64?

    init(
        fusionDepth: Int = 0,
        debugMode: Bool = false,
        logPrompts: Bool = false,
        conversationId: Int64? = nil
    ) {
        self.fusionDepth = fusionDepth
        self.debugMode = debugMode
        self.logPrompts = logPrompts
        self.conversationId = conversationId
    }
}

struct FusionRunOptions: Sendable, Equatable {
    var preset: String
    var taskType: FusionTaskType
    var systemPrompt: String?
    var debugMode: Bool
    var logPrompts: Bool
    var fusionDepth: Int
    var conversationId: Int64?
    var allowWebSearch: Bool?

    init(
        preset: String = "quality",
        taskType: FusionTaskType = .auto,
        systemPrompt: String? = nil,
        debugMode: Bool = false,
        logPrompts: Bool = false,
        fusionDepth: Int = 0,
        conversationId: Int64? = nil,
        allowWebSearch: Bool? = nil
    ) {
        self.preset = preset
        self.taskType = taskType
        self.systemPrompt = systemPrompt
        self.debugMode = debugMode
        self.logPrompts = logPrompts
        self.fusionDepth = fusionDepth
        self.conversationId = conversationId
        self.allowWebSearch = allowWebSearch
    }
}

struct FusionRunResult: Sendable, Equatable {
    var finalAnswer: String
    var traceId: String
    var judgeAnalysis: JudgeAnalysis?
    var rawPanelResults: [PanelResult]?
    var totalLatencyMs: Int64?
    var totalCost: Double?
}

struct FusionJudgeOutcome: Sendable {
    var trace: FusionTrace
    var synthesisRequest: ProviderRequest
    var synthesizerProvider: LLMProvider
    var synthesizerModel: PanelModelConfig
    var staticFallbackAnswer: String
    var panelTokenUsages: [(provider: String, model: String, usage: ProviderUsage?, requestType: String)]
    var judgeTokenUsage: (provider: String, model: String, usage: ProviderUsage?)?
}

enum FusionError: LocalizedError, Sendable {
    case allPanelsFailed(panelResults: [PanelResult])
    case presetNotFound(String)
    case invalidPreset(String)
    case serviceDeallocated

    var errorDescription: String? {
        switch self {
        case .allPanelsFailed:
            return L10n.text("Fusion: すべてのパネルモデルが失敗しました。")
        case let .presetNotFound(name):
            return L10n.format("Fusion: プリセット '%@' が見つかりません。", name)
        case let .invalidPreset(reason):
            return L10n.format("Fusion: 無効なプリセット — %@", reason)
        case .serviceDeallocated:
            return L10n.text("Fusion: サービスが解放されました。")
        }
    }
}

// MARK: - Judge JSON DTO (snake_case from model output)

struct JudgeAnalysisDTO: Codable, Sendable {
    var consensus: [String]?
    var contradictions: [JudgeContradictionDTO]?
    var uniqueInsights: [JudgeUniqueInsightDTO]?
    var coverageGaps: [String]?
    var suspectedErrors: [JudgeSuspectedErrorDTO]?
    var sourceQualityIssues: [String]?
    var strongestAnswerParts: [JudgeStrongestPartDTO]?
    var recommendedFinalPosition: String?
    var confidence: String?
    var notes: String?
}

struct JudgeContradictionDTO: Codable, Sendable {
    var topic: String?
    var positions: [String]?
    var likelyResolution: String?
    var confidence: String?
}

struct JudgeUniqueInsightDTO: Codable, Sendable {
    var model: String?
    var insight: String?
    var useInFinal: Bool?
}

struct JudgeSuspectedErrorDTO: Codable, Sendable {
    var model: String?
    var claim: String?
    var reason: String?
}

struct JudgeStrongestPartDTO: Codable, Sendable {
    var model: String?
    var part: String?
    var reason: String?
}

extension JudgeAnalysisDTO {
    func toJudgeAnalysis() -> JudgeAnalysis {
        JudgeAnalysis(
            consensus: consensus ?? [],
            contradictions: (contradictions ?? []).map {
                JudgeContradiction(
                    topic: $0.topic ?? "",
                    positions: $0.positions ?? [],
                    likelyResolution: $0.likelyResolution ?? "",
                    confidence: FusionConfidence(rawValue: ($0.confidence ?? "medium").lowercased()) ?? .medium
                )
            },
            uniqueInsights: (uniqueInsights ?? []).map {
                JudgeUniqueInsight(
                    model: $0.model ?? "",
                    insight: $0.insight ?? "",
                    useInFinal: $0.useInFinal ?? true
                )
            },
            coverageGaps: coverageGaps ?? [],
            suspectedErrors: (suspectedErrors ?? []).map {
                JudgeSuspectedError(
                    model: $0.model ?? "",
                    claim: $0.claim ?? "",
                    reason: $0.reason ?? ""
                )
            },
            sourceQualityIssues: sourceQualityIssues ?? [],
            strongestAnswerParts: (strongestAnswerParts ?? []).map {
                JudgeStrongestPart(
                    model: $0.model ?? "",
                    part: $0.part ?? "",
                    reason: $0.reason ?? ""
                )
            },
            recommendedFinalPosition: recommendedFinalPosition ?? "",
            confidence: FusionConfidence(rawValue: (confidence ?? "medium").lowercased()) ?? .medium,
            notes: notes
        )
    }
}