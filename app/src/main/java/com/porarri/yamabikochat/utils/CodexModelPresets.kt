package com.porarri.yamabikochat.utils

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
    private val delegatedEfforts = maximumEfforts +
        CodexReasoningEffortPreset("ultra", "Maximum reasoning with automatic task delegation")
    private val legacyEfforts = listOf(
        CodexReasoningEffortPreset("low", "Balances speed with some reasoning; useful for straightforward queries and short explanations"),
        CodexReasoningEffortPreset("medium", "Provides a solid balance of reasoning depth and latency for general-purpose tasks"),
        CodexReasoningEffortPreset("high", "Maximizes reasoning depth for complex or ambiguous problems"),
        CodexReasoningEffortPreset("xhigh", "Extra high reasoning for complex problems")
    )

    private val presets: List<CodexModelPreset> = listOf(
        preset("gpt-5.6-sol", "GPT-5.6-Sol", "Latest frontier agentic coding model.", "low", delegatedEfforts, true),
        preset("gpt-5.6-terra", "GPT-5.6-Terra", "Balanced agentic coding model for everyday work.", "medium", delegatedEfforts),
        preset("gpt-5.6-luna", "GPT-5.6-Luna", "Fast and affordable agentic coding model.", "medium", maximumEfforts),
        preset("gpt-5.5", "GPT-5.5", "Frontier model for complex coding, research, and real-world work.", "medium", modernEfforts),
        preset("gpt-5.4", "GPT-5.4", "Strong model for everyday coding.", "medium", modernEfforts),
        preset("gpt-5.4-mini", "GPT-5.4-Mini", "Small, fast, and cost-efficient model for simpler coding tasks.", "medium", modernEfforts),
        preset("gpt-5.2", "GPT-5.2", "Optimized for professional work and long-running agents.", "medium", legacyEfforts)
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

    fun findPreset(model: String): CodexModelPreset? {
        val normalized = model.trim()
        return presets.firstOrNull {
            it.model.equals(normalized, ignoreCase = true) || it.id.equals(normalized, ignoreCase = true)
        }
    }

    fun defaultModel(): String = presets.firstOrNull { it.isDefault }?.model ?: "gpt-5.6-sol"

    fun supportsReasoningSummary(model: String): Boolean = model.trim().lowercase().startsWith("gpt-5")

    fun supportsTextVerbosity(model: String): Boolean = model.trim().lowercase().startsWith("gpt-5")
}
