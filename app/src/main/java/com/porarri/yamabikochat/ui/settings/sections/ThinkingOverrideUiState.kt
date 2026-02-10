package com.porarri.yamabikochat.ui.settings.sections

data class ThinkingOverrideUiState(
    val overrideEnabled: Boolean,
    val onOverrideEnabledChange: (Boolean) -> Unit,
    val thinkingEnabled: Boolean,
    val onThinkingEnabledChange: (Boolean) -> Unit,
    val thinkingBudget: Float,
    val onThinkingBudgetChange: (Float) -> Unit,
    val thinkingLevel: String,
    val onThinkingLevelChange: (String) -> Unit,
    val codexReasoningEffort: String,
    val onCodexReasoningEffortChange: (String) -> Unit,
    val onApplyDefaults: () -> Unit
)
