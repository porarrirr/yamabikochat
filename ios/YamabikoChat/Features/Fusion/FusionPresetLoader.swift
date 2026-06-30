import Foundation

struct FusionPresetDefinition: Codable, Sendable, Equatable {
    var taskType: FusionTaskType
    var maxPanelTokens: Int
    var maxJudgeTokens: Int
    var maxSynthesizerTokens: Int
    var timeoutMs: Int
    var allowWebSearch: Bool
    var panelModels: [PanelModelConfig]
    var judgeModel: PanelModelConfig
    var synthesizerModel: PanelModelConfig
    var fallbackModel: PanelModelConfig?
}

enum FusionPresetLoader {
    static let presetLabel = "custom"
    static let maxPanelModelCount = 4

    static func panelCount(customPresetJSON: String = "") -> Int {
        (try? resolveDefinition(customPresetJSON: customPresetJSON))?
            .panelModels.count ?? 0
    }

    static func resolveDefinition(customPresetJSON: String) throws -> FusionPresetDefinition {
        let trimmedJSON = customPresetJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedJSON.isEmpty {
            let preset = AppSettings.defaultFusionCustomPreset()
            try validatePreset(preset)
            return preset
        }
        guard let data = trimmedJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(FusionPresetDefinition.self, from: data) else {
            throw FusionError.invalidPreset("invalid custom preset JSON")
        }
        let preset = AppSettings.normalizedFusionPresetDefinition(decoded)
        try validatePreset(preset)
        return preset
    }

    static func buildRequest(
        userPrompt: String,
        systemPrompt: String? = nil,
        taskTypeOverride: FusionTaskType = .auto,
        allowWebSearchOverride: Bool? = nil,
        customPresetJSON: String = "",
        metadata: [String: String] = [:]
    ) throws -> FusionRequest {
        let preset = try resolveDefinition(customPresetJSON: customPresetJSON)
        let resolvedTaskType: FusionTaskType
        if taskTypeOverride == .auto {
            resolvedTaskType = preset.taskType
        } else {
            resolvedTaskType = taskTypeOverride
        }
        let allowWebSearch = allowWebSearchOverride ?? preset.allowWebSearch

        return FusionRequest(
            userPrompt: userPrompt,
            systemPrompt: systemPrompt,
            panelModels: preset.panelModels,
            judgeModel: preset.judgeModel,
            synthesizerModel: preset.synthesizerModel,
            fallbackModel: preset.fallbackModel,
            preset: presetLabel,
            maxPanelTokens: preset.maxPanelTokens,
            maxJudgeTokens: preset.maxJudgeTokens,
            maxSynthesizerTokens: preset.maxSynthesizerTokens,
            timeoutMs: preset.timeoutMs,
            allowWebSearch: allowWebSearch,
            taskType: resolvedTaskType,
            metadata: metadata
        )
    }

    static func validatePreset(_ preset: FusionPresetDefinition) throws {
        guard preset.panelModels.count >= 1 else {
            throw FusionError.invalidPreset("panelModels must not be empty")
        }
        guard preset.panelModels.count <= maxPanelModelCount else {
            throw FusionError.invalidPreset("panelModels must not exceed \(maxPanelModelCount)")
        }
        guard !preset.judgeModel.modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FusionError.invalidPreset("judgeModel.modelId is required")
        }
        guard !preset.synthesizerModel.modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FusionError.invalidPreset("synthesizerModel.modelId is required")
        }
        for panel in preset.panelModels {
            guard !panel.modelId.isEmpty, !panel.provider.isEmpty else {
                throw FusionError.invalidPreset("panel modelId and provider are required")
            }
        }
    }
}