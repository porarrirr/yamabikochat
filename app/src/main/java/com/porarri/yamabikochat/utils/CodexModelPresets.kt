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
    private val presets: List<CodexModelPreset> = listOf(
        CodexModelPreset(
            id = "gpt-5.2-codex",
            model = "gpt-5.2-codex",
            displayName = "gpt-5.2-codex",
            description = "Latest frontier agentic coding model.",
            defaultReasoningEffort = "medium",
            supportedReasoningEfforts = listOf(
                CodexReasoningEffortPreset("low", "Fast responses with lighter reasoning"),
                CodexReasoningEffortPreset("medium", "Balances speed and reasoning depth for everyday tasks"),
                CodexReasoningEffortPreset("high", "Greater reasoning depth for complex problems"),
                CodexReasoningEffortPreset("xhigh", "Extra high reasoning depth for complex problems")
            ),
            isDefault = true,
            showInPicker = true
        ),
        CodexModelPreset(
            id = "gpt-5.1-codex-max",
            model = "gpt-5.1-codex-max",
            displayName = "gpt-5.1-codex-max",
            description = "Codex-optimized flagship for deep and fast reasoning.",
            defaultReasoningEffort = "medium",
            supportedReasoningEfforts = listOf(
                CodexReasoningEffortPreset("low", "Fast responses with lighter reasoning"),
                CodexReasoningEffortPreset("medium", "Balances speed and reasoning depth for everyday tasks"),
                CodexReasoningEffortPreset("high", "Greater reasoning depth for complex problems"),
                CodexReasoningEffortPreset("xhigh", "Extra high reasoning depth for complex problems")
            ),
            isDefault = false,
            showInPicker = true
        ),
        CodexModelPreset(
            id = "gpt-5.1-codex-mini",
            model = "gpt-5.1-codex-mini",
            displayName = "gpt-5.1-codex-mini",
            description = "Optimized for codex. Cheaper, faster, but less capable.",
            defaultReasoningEffort = "medium",
            supportedReasoningEfforts = listOf(
                CodexReasoningEffortPreset("medium", "Dynamically adjusts reasoning based on the task"),
                CodexReasoningEffortPreset("high", "Maximizes reasoning depth for complex or ambiguous problems")
            ),
            isDefault = false,
            showInPicker = true
        ),
        CodexModelPreset(
            id = "gpt-5.2",
            model = "gpt-5.2",
            displayName = "gpt-5.2",
            description = "Latest frontier model with improvements across knowledge, reasoning and coding.",
            defaultReasoningEffort = "medium",
            supportedReasoningEfforts = listOf(
                CodexReasoningEffortPreset("low", "Balances speed with some reasoning; useful for straightforward queries and short explanations"),
                CodexReasoningEffortPreset("medium", "Provides a solid balance of reasoning depth and latency for general-purpose tasks"),
                CodexReasoningEffortPreset("high", "Maximizes reasoning depth for complex or ambiguous problems"),
                CodexReasoningEffortPreset("xhigh", "Extra high reasoning depth for complex problems")
            ),
            isDefault = false,
            showInPicker = true
        ),
        CodexModelPreset(
            id = "gpt-5.1",
            model = "gpt-5.1",
            displayName = "gpt-5.1",
            description = "Broad world knowledge with strong general reasoning.",
            defaultReasoningEffort = "medium",
            supportedReasoningEfforts = listOf(
                CodexReasoningEffortPreset("low", "Balances speed with some reasoning; useful for straightforward queries and short explanations"),
                CodexReasoningEffortPreset("medium", "Provides a solid balance of reasoning depth and latency for general-purpose tasks"),
                CodexReasoningEffortPreset("high", "Maximizes reasoning depth for complex or ambiguous problems")
            ),
            isDefault = false,
            showInPicker = true
        )
    )

    fun visiblePresets(): List<CodexModelPreset> = presets.filter { it.showInPicker }

    fun findPreset(model: String): CodexModelPreset? {
        val normalized = model.trim()
        return presets.firstOrNull { it.model.equals(normalized, ignoreCase = true) || it.id.equals(normalized, ignoreCase = true) }
    }

    fun defaultModel(): String {
        return presets.firstOrNull { it.isDefault }?.model ?: "gpt-5.2-codex"
    }

    fun supportsReasoningSummary(model: String): Boolean {
        val normalized = model.trim().lowercase()
        return normalized.startsWith("gpt-5")
    }

    fun supportsTextVerbosity(model: String): Boolean {
        val normalized = model.trim().lowercase()
        return normalized.startsWith("gpt-5")
    }
}
