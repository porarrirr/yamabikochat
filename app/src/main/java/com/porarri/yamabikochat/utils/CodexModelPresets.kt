package com.porarri.yamabikochat.utils

import com.porarri.yamabikochat.pi.PiCodexModel

data class CodexReasoningEffortPreset(
    val effort: String,
    val description: String
)

data class CodexModelPreset(
    val id: String,
    val model: String,
    val displayName: String,
    val description: String,
    val defaultReasoningEffort: String,
    val supportedReasoningEfforts: List<CodexReasoningEffortPreset>,
    val isDefault: Boolean,
    val showInPicker: Boolean
)

object CodexModelPresets {
    private val modernEfforts = listOf(
        CodexReasoningEffortPreset("low", "Fast responses with lighter reasoning"),
        CodexReasoningEffortPreset("medium", "Balances speed and reasoning depth for everyday tasks"),
        CodexReasoningEffortPreset("high", "Greater reasoning depth for complex problems"),
        CodexReasoningEffortPreset("xhigh", "Extra high reasoning depth for complex problems")
    )
    private val maximumEfforts = modernEfforts +
        CodexReasoningEffortPreset("max", "Maximum reasoning depth for the hardest problems")
    private val presets: List<CodexModelPreset> = listOf(
        preset("gpt-6-sol", "GPT-6 Sol", "Complex coding and agentic workflows.", "medium", maximumEfforts, true),
        preset("gpt-6-astra", "GPT-6 Astra", "Most capable model for complex work.", "low", maximumEfforts),
        preset("gpt-6-luna", "GPT-6 Luna", "Efficient model for focused work.", "high", maximumEfforts),
        preset("gpt-5.6-sol", "GPT-5.6 Sol", "Frontier agentic coding model.", "low", maximumEfforts),
        preset("gpt-5.6-terra", "GPT-5.6-Terra", "Balanced agentic coding model for everyday work.", "medium", maximumEfforts),
        preset("gpt-5.6-luna", "GPT-5.6-Luna", "Fast and affordable agentic coding model.", "medium", maximumEfforts),
        preset("gpt-5.5", "GPT-5.5", "Previous-generation flagship model.", "medium", modernEfforts)
    )

    private fun preset(
        model: String,
        displayName: String,
        description: String,
        defaultEffort: String,
        efforts: List<CodexReasoningEffortPreset>,
        isDefault: Boolean = false
    ) = CodexModelPreset(model, model, displayName, description, defaultEffort, efforts, isDefault, true)

    fun visiblePresets(): List<CodexModelPreset> = presets.filter { it.showInPicker }

    fun visiblePresets(models: List<PiCodexModel>): List<CodexModelPreset> =
        if (models.isEmpty()) visiblePresets() else models.sortedWith(compareBy<PiCodexModel> {
            presets.indexOfFirst { preset -> preset.model == it.id }.takeIf { index -> index >= 0 } ?: Int.MAX_VALUE
        }.thenBy { it.id }).map { model ->
            findPreset(model.id) ?: preset(model.id, model.name, "Pi Codex model", "medium", modernEfforts)
        }

    fun findPreset(model: String): CodexModelPreset? {
        val normalized = model.trim()
        return presets.firstOrNull {
            it.model.equals(normalized, ignoreCase = true) || it.id.equals(normalized, ignoreCase = true)
        }
    }

    fun findPreset(model: String, models: List<PiCodexModel>): CodexModelPreset? =
        visiblePresets(models).firstOrNull { it.model.equals(model.trim(), ignoreCase = true) }

    fun defaultModel(): String = presets.firstOrNull { it.isDefault }?.model ?: "gpt-6-sol"

    fun resolvedReasoningEffort(requested: String, model: String): String {
        val normalized = requested.trim().lowercase()
        val supported = (findPreset(model)?.supportedReasoningEfforts ?: modernEfforts).map { it.effort }
        return normalized.takeIf { it in supported } ?: "medium"
    }

    fun supportsReasoningSummary(model: String): Boolean = model.trim().lowercase().startsWith("gpt-5")

    fun supportsTextVerbosity(model: String): Boolean = model.trim().lowercase().startsWith("gpt-5")
}
