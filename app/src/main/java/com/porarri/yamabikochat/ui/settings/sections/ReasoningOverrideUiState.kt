package com.porarri.yamabikochat.ui.settings.sections

data class ReasoningOverrideUiState(
    val overrideEnabled: Boolean,
    val onOverrideEnabledChange: (Boolean) -> Unit,
    val reasoningEnabled: Boolean,
    val onReasoningEnabledChange: (Boolean) -> Unit,
    val reasoningMode: String,
    val onReasoningModeChange: (String) -> Unit,
    val reasoningEffort: String,
    val onReasoningEffortChange: (String) -> Unit,
    val reasoningExclude: Boolean,
    val onReasoningExcludeChange: (Boolean) -> Unit,
    val reasoningBudget: Float,
    val onReasoningBudgetChange: (Float) -> Unit,
    val onApplyDefaults: () -> Unit
)
