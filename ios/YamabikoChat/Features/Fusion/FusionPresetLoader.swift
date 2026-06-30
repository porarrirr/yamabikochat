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

private struct FusionPresetsFile: Codable {
    var presets: [String: FusionPresetDefinition]
}

enum FusionPresetLoader {
    static let defaultPresetName = "quality"
    static let customPresetName = "custom"
    static let maxPanelModelCount = 4

    static var bundledPresetNames: [String] {
        guard let file = try? loadPresetsFile() else {
            return [defaultPresetName]
        }
        return file.presets.keys.sorted()
    }

    static var availablePresetNames: [String] {
        bundledPresetNames + [customPresetName]
    }

    static func panelCount(for presetName: String, customPresetJSON: String = "") -> Int {
        (try? resolveDefinition(presetName: presetName, customPresetJSON: customPresetJSON))?
            .panelModels.count ?? 0
    }

    static func loadPreset(named name: String) throws -> FusionPresetDefinition {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            throw FusionError.invalidPreset("empty preset name")
        }
        guard normalized != customPresetName else {
            throw FusionError.invalidPreset("use resolveDefinition for custom preset")
        }

        let file = try loadPresetsFile()
        guard let preset = file.presets[normalized] else {
            throw FusionError.presetNotFound(normalized)
        }
        try validatePreset(preset, name: normalized)
        return preset
    }

    static func resolveDefinition(
        presetName: String,
        customPresetJSON: String
    ) throws -> FusionPresetDefinition {
        let normalized = presetName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == customPresetName {
            let trimmedJSON = customPresetJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedJSON.isEmpty {
                let preset = AppSettings.defaultFusionCustomPreset()
                try validatePreset(preset, name: customPresetName)
                return preset
            }
            guard let data = trimmedJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(FusionPresetDefinition.self, from: data) else {
                throw FusionError.invalidPreset("invalid custom preset JSON")
            }
            let preset = AppSettings.normalizedFusionPresetDefinition(decoded)
            try validatePreset(preset, name: customPresetName)
            return preset
        }
        return try loadPreset(named: normalized)
    }

    static func buildRequest(
        userPrompt: String,
        presetName: String,
        systemPrompt: String? = nil,
        taskTypeOverride: FusionTaskType = .auto,
        allowWebSearchOverride: Bool? = nil,
        customPresetJSON: String = "",
        metadata: [String: String] = [:]
    ) throws -> FusionRequest {
        let normalizedName = presetName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let preset = try resolveDefinition(presetName: normalizedName, customPresetJSON: customPresetJSON)
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
            preset: normalizedName,
            maxPanelTokens: preset.maxPanelTokens,
            maxJudgeTokens: preset.maxJudgeTokens,
            maxSynthesizerTokens: preset.maxSynthesizerTokens,
            timeoutMs: preset.timeoutMs,
            allowWebSearch: allowWebSearch,
            taskType: resolvedTaskType,
            metadata: metadata
        )
    }

    private static func loadPresetsFile() throws -> FusionPresetsFile {
        guard let url = Bundle.main.url(forResource: "FusionPresets", withExtension: "json") else {
            throw FusionError.invalidPreset("FusionPresets.json not found in bundle")
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(FusionPresetsFile.self, from: data)
    }

    static func validatePreset(_ preset: FusionPresetDefinition, name: String) throws {
        guard preset.panelModels.count >= 1 else {
            throw FusionError.invalidPreset("\(name): panelModels must not be empty")
        }
        guard preset.panelModels.count <= maxPanelModelCount else {
            throw FusionError.invalidPreset("\(name): panelModels must not exceed \(maxPanelModelCount)")
        }
        guard !preset.judgeModel.modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FusionError.invalidPreset("\(name): judgeModel.modelId is required")
        }
        guard !preset.synthesizerModel.modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FusionError.invalidPreset("\(name): synthesizerModel.modelId is required")
        }
        for panel in preset.panelModels {
            guard !panel.modelId.isEmpty, !panel.provider.isEmpty else {
                throw FusionError.invalidPreset("\(name): panel modelId and provider are required")
            }
        }
    }
}