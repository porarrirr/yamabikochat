package com.porarri.yamabikochat.data.fusion

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class FusionPresetDefinition(
    val taskType: FusionTaskType = FusionTaskType.research,
    val maxPanelTokens: Int = 4096,
    val maxJudgeTokens: Int = 2048,
    val maxSynthesizerTokens: Int = 4096,
    val timeoutMs: Int = 120_000,
    val allowWebSearch: Boolean = true,
    val panelModels: List<PanelModelConfig> = emptyList(),
    val judgeModel: PanelModelConfig,
    val synthesizerModel: PanelModelConfig,
    val fallbackModel: PanelModelConfig? = null
)

object FusionPresetLoader {
    const val PRESET_LABEL = "custom"
    const val MAX_PANEL_MODEL_COUNT = 4

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    }

    fun panelCount(customPresetJSON: String = ""): Int =
        runCatching { resolveDefinition(customPresetJSON).panelModels.size }.getOrDefault(0)

    fun resolveDefinition(customPresetJSON: String): FusionPresetDefinition {
        val trimmedJSON = customPresetJSON.trim()
        if (trimmedJSON.isEmpty()) {
            val preset = defaultFusionCustomPreset()
            validatePreset(preset)
            return preset
        }
        val decoded = runCatching {
            json.decodeFromString(FusionPresetDefinition.serializer(), trimmedJSON)
        }.getOrElse {
            throw FusionError.InvalidPreset("invalid custom preset JSON")
        }
        val preset = normalizedFusionPresetDefinition(decoded)
        validatePreset(preset)
        return preset
    }

    fun buildRequest(
        userPrompt: String,
        systemPrompt: String? = null,
        taskTypeOverride: FusionTaskType = FusionTaskType.auto,
        allowWebSearchOverride: Boolean? = null,
        customPresetJSON: String = "",
        metadata: Map<String, String> = emptyMap()
    ): FusionRequest {
        val preset = resolveDefinition(customPresetJSON)
        val resolvedTaskType = if (taskTypeOverride == FusionTaskType.auto) {
            preset.taskType
        } else {
            taskTypeOverride
        }
        val allowWebSearch = allowWebSearchOverride ?: preset.allowWebSearch

        return FusionRequest(
            userPrompt = userPrompt,
            systemPrompt = systemPrompt,
            panelModels = preset.panelModels,
            judgeModel = preset.judgeModel,
            synthesizerModel = preset.synthesizerModel,
            fallbackModel = preset.fallbackModel,
            preset = PRESET_LABEL,
            maxPanelTokens = preset.maxPanelTokens,
            maxJudgeTokens = preset.maxJudgeTokens,
            maxSynthesizerTokens = preset.maxSynthesizerTokens,
            timeoutMs = preset.timeoutMs,
            allowWebSearch = allowWebSearch,
            taskType = resolvedTaskType,
            metadata = metadata
        )
    }

    fun validatePreset(preset: FusionPresetDefinition) {
        if (preset.panelModels.isEmpty()) {
            throw FusionError.InvalidPreset("panelModels must not be empty")
        }
        if (preset.panelModels.size > MAX_PANEL_MODEL_COUNT) {
            throw FusionError.InvalidPreset("panelModels must not exceed $MAX_PANEL_MODEL_COUNT")
        }
        if (preset.judgeModel.modelId.trim().isEmpty()) {
            throw FusionError.InvalidPreset("judgeModel.modelId is required")
        }
        if (preset.synthesizerModel.modelId.trim().isEmpty()) {
            throw FusionError.InvalidPreset("synthesizerModel.modelId is required")
        }
        for (panel in preset.panelModels) {
            if (panel.modelId.isEmpty() || panel.provider.isEmpty()) {
                throw FusionError.InvalidPreset("panel modelId and provider are required")
            }
        }
    }

    fun defaultFusionCustomPreset(): FusionPresetDefinition =
        FusionPresetDefinition(
            taskType = FusionTaskType.research,
            maxPanelTokens = 4096,
            maxJudgeTokens = 2048,
            maxSynthesizerTokens = 4096,
            timeoutMs = 120_000,
            allowWebSearch = true,
            panelModels = listOf(
                PanelModelConfig(
                    modelId = "gemini-2.5-pro",
                    provider = "GEMINI",
                    temperature = 0.3,
                    maxTokens = 4096,
                    timeoutMs = 120_000,
                    role = "researcher"
                ),
                PanelModelConfig(
                    modelId = "anthropic/claude-sonnet-4",
                    provider = "OPENROUTER",
                    temperature = 0.3,
                    maxTokens = 4096,
                    timeoutMs = 120_000,
                    role = "analyst"
                ),
                PanelModelConfig(
                    modelId = "openai/gpt-4.1",
                    provider = "OPENROUTER",
                    temperature = 0.3,
                    maxTokens = 4096,
                    timeoutMs = 120_000,
                    role = "critic"
                ),
                PanelModelConfig(
                    modelId = "deepseek/deepseek-chat",
                    provider = "OPENROUTER",
                    temperature = 0.4,
                    maxTokens = 4096,
                    timeoutMs = 120_000,
                    role = "synthesizer_candidate"
                )
            ),
            judgeModel = PanelModelConfig(
                modelId = "anthropic/claude-sonnet-4",
                provider = "OPENROUTER",
                temperature = 0.1,
                maxTokens = 2048,
                timeoutMs = 90_000,
                role = null
            ),
            synthesizerModel = PanelModelConfig(
                modelId = "gemini-2.5-pro",
                provider = "GEMINI",
                temperature = 0.4,
                maxTokens = 4096,
                timeoutMs = 120_000,
                role = null
            ),
            fallbackModel = PanelModelConfig(
                modelId = "gemini-2.5-flash",
                provider = "GEMINI",
                temperature = 0.5,
                maxTokens = 4096,
                timeoutMs = 60_000,
                role = null
            )
        )

    fun encodeFusionCustomPreset(definition: FusionPresetDefinition): String =
        runCatching { json.encodeToString(FusionPresetDefinition.serializer(), definition) }
            .getOrDefault("")

    fun decodeFusionCustomPreset(raw: String): FusionPresetDefinition? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        return runCatching {
            json.decodeFromString(FusionPresetDefinition.serializer(), trimmed)
        }.getOrNull()
    }

    fun normalizedFusionPresetDefinition(preset: FusionPresetDefinition): FusionPresetDefinition {
        val normalizedPanels = preset.panelModels.map { panel ->
            panel.copy(
                provider = panel.provider.trim().uppercase(),
                modelId = panel.modelId.trim()
            )
        }
        val judge = preset.judgeModel.copy(
            provider = preset.judgeModel.provider.trim().uppercase(),
            modelId = preset.judgeModel.modelId.trim()
        )
        val synthesizer = preset.synthesizerModel.copy(
            provider = preset.synthesizerModel.provider.trim().uppercase(),
            modelId = preset.synthesizerModel.modelId.trim()
        )
        val fallbackRaw = preset.fallbackModel
        val fallback = if (fallbackRaw == null) {
            synthesizer
        } else {
            val normalized = fallbackRaw.copy(
                provider = fallbackRaw.provider.trim().uppercase(),
                modelId = fallbackRaw.modelId.trim()
            )
            if (normalized.modelId.isEmpty() || normalized.provider.isEmpty()) {
                synthesizer
            } else {
                normalized
            }
        }
        return preset.copy(
            panelModels = normalizedPanels,
            judgeModel = judge,
            synthesizerModel = synthesizer,
            fallbackModel = fallback
        )
    }

    fun normalizedFusionCustomPresetJSON(raw: String): String {
        var preset = decodeFusionCustomPreset(raw) ?: defaultFusionCustomPreset()
        preset = normalizedFusionPresetDefinition(preset)
        val valid = runCatching {
            validatePreset(preset)
            true
        }.getOrDefault(false)
        if (!valid) {
            preset = defaultFusionCustomPreset()
        }
        return encodeFusionCustomPreset(preset)
    }
}
