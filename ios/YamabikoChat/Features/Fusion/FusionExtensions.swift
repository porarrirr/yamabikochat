import Foundation

/// Extension point for learned model routing (v2+).
protocol FusionRoutingPolicy: Sendable {
    func selectPanelModels(for request: FusionRequest, preset: FusionPresetDefinition) -> [PanelModelConfig]
}

/// Extension point for automatic prompt evolution (v2+).
protocol FusionPromptEvolver: Sendable {
    func evolvePanelPrompt(base: String, taskType: FusionTaskType) -> String
}

extension AppSettings {
    func decodeFusionCustomPreset() -> FusionPresetDefinition? {
        let trimmed = fusionCustomPresetJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(FusionPresetDefinition.self, from: data) else {
            return nil
        }
        return decoded
    }

    func encodeFusionCustomPreset(_ definition: FusionPresetDefinition) -> String {
        guard let data = try? JSONEncoder().encode(definition),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }

    static func defaultFusionCustomPreset() -> FusionPresetDefinition {
        FusionPresetDefinition(
            taskType: .research,
            maxPanelTokens: 4096,
            maxJudgeTokens: 2048,
            maxSynthesizerTokens: 4096,
            timeoutMs: 120_000,
            allowWebSearch: true,
            panelModels: [
                PanelModelConfig(
                    modelId: "gemini-2.5-pro",
                    provider: "GEMINI",
                    temperature: 0.3,
                    maxTokens: 4096,
                    timeoutMs: 120_000,
                    role: "researcher"
                ),
                PanelModelConfig(
                    modelId: "anthropic/claude-sonnet-4",
                    provider: "OPENROUTER",
                    temperature: 0.3,
                    maxTokens: 4096,
                    timeoutMs: 120_000,
                    role: "analyst"
                ),
                PanelModelConfig(
                    modelId: "openai/gpt-4.1",
                    provider: "OPENROUTER",
                    temperature: 0.3,
                    maxTokens: 4096,
                    timeoutMs: 120_000,
                    role: "critic"
                ),
                PanelModelConfig(
                    modelId: "deepseek/deepseek-chat",
                    provider: "OPENROUTER",
                    temperature: 0.4,
                    maxTokens: 4096,
                    timeoutMs: 120_000,
                    role: "synthesizer_candidate"
                )
            ],
            judgeModel: PanelModelConfig(
                modelId: "anthropic/claude-sonnet-4",
                provider: "OPENROUTER",
                temperature: 0.1,
                maxTokens: 2048,
                timeoutMs: 90_000,
                role: nil
            ),
            synthesizerModel: PanelModelConfig(
                modelId: "gemini-2.5-pro",
                provider: "GEMINI",
                temperature: 0.4,
                maxTokens: 4096,
                timeoutMs: 120_000,
                role: nil
            ),
            fallbackModel: PanelModelConfig(
                modelId: "gemini-2.5-flash",
                provider: "GEMINI",
                temperature: 0.5,
                maxTokens: 4096,
                timeoutMs: 60_000,
                role: nil
            )
        )
    }

    func normalizedFusionCustomPresetJSON() -> String {
        var preset = decodeFusionCustomPreset() ?? Self.defaultFusionCustomPreset()
        preset = Self.normalizedFusionPresetDefinition(preset)
        if (try? FusionPresetLoader.validatePreset(preset)) == nil {
            preset = Self.defaultFusionCustomPreset()
        }
        return encodeFusionCustomPreset(preset)
    }

    static func normalizedFusionPresetDefinition(_ preset: FusionPresetDefinition) -> FusionPresetDefinition {
        var normalized = preset
        normalized.panelModels = preset.panelModels.map { panel in
            var copy = panel
            copy.provider = panel.provider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            copy.modelId = ProviderCatalog.migrateLegacyModelID(
                panel.modelId.trimmingCharacters(in: .whitespacesAndNewlines),
                for: copy.provider
            )
            return copy
        }
        normalized.judgeModel.provider = preset.judgeModel.provider
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        normalized.judgeModel.modelId = ProviderCatalog.migrateLegacyModelID(
            preset.judgeModel.modelId.trimmingCharacters(in: .whitespacesAndNewlines),
            for: normalized.judgeModel.provider
        )
        normalized.synthesizerModel.provider = preset.synthesizerModel.provider
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        normalized.synthesizerModel.modelId = ProviderCatalog.migrateLegacyModelID(
            preset.synthesizerModel.modelId.trimmingCharacters(in: .whitespacesAndNewlines),
            for: normalized.synthesizerModel.provider
        )
        if var fallback = normalized.fallbackModel {
            fallback.provider = fallback.provider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            fallback.modelId = ProviderCatalog.migrateLegacyModelID(
                fallback.modelId.trimmingCharacters(in: .whitespacesAndNewlines),
                for: fallback.provider
            )
            if fallback.modelId.isEmpty || fallback.provider.isEmpty {
                normalized.fallbackModel = normalized.synthesizerModel
            } else {
                normalized.fallbackModel = fallback
            }
        } else {
            normalized.fallbackModel = normalized.synthesizerModel
        }
        return normalized
    }
}
