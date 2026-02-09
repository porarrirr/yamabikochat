package com.porarri.yamabikochat.ui.settings.sections

data class ToolingOverrideUiState(
    val overrideEnabled: Boolean,
    val onOverrideEnabledChange: (Boolean) -> Unit,
    val googleSearchEnabled: Boolean,
    val onGoogleSearchEnabledChange: (Boolean) -> Unit,
    val codeExecutionEnabled: Boolean,
    val onCodeExecutionEnabledChange: (Boolean) -> Unit,
    val urlContextEnabled: Boolean,
    val onUrlContextEnabledChange: (Boolean) -> Unit,
    val googleMapsEnabled: Boolean,
    val onGoogleMapsEnabledChange: (Boolean) -> Unit,
    val computerUseEnabled: Boolean,
    val onComputerUseEnabledChange: (Boolean) -> Unit,
    val onApplyDefaults: () -> Unit
)
