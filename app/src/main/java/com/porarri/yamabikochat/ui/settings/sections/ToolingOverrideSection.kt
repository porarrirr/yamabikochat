package com.porarri.yamabikochat.ui.settings.sections

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.ui.settings.components.SettingsToggleRow

@Composable
fun ToolingOverrideSection(
    provider: String,
    tooling: ToolingOverrideUiState
) {
    val normalized = provider.uppercase()
    val supportsGoogleSearch = normalized == "GEMINI" || normalized == "OPENROUTER"
    val supportsCodeExecution = supportsGoogleSearch
    val supportsUrlContext = normalized == "GEMINI"
    val supportsGoogleMaps = normalized == "GEMINI"
    val supportsComputerUse = normalized == "GEMINI"
    val supportsAny = supportsGoogleSearch || supportsCodeExecution || supportsUrlContext || supportsGoogleMaps || supportsComputerUse

    if (!supportsAny) return

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SettingsToggleRow(
            title = "ツール設定",
            description = if (tooling.overrideEnabled) "カスタム設定を使用" else "グローバル設定を継承",
            checked = tooling.overrideEnabled,
            onCheckedChange = {
                tooling.onOverrideEnabledChange(it)
                if (it) tooling.onApplyDefaults()
            }
        )

        if (tooling.overrideEnabled) {
            if (supportsGoogleSearch) {
                SettingsToggleRow(
                    title = "Google Search",
                    checked = tooling.googleSearchEnabled,
                    onCheckedChange = tooling.onGoogleSearchEnabledChange
                )
            }
            if (supportsUrlContext) {
                SettingsToggleRow(
                    title = "URL Context",
                    checked = tooling.urlContextEnabled,
                    onCheckedChange = tooling.onUrlContextEnabledChange
                )
            }
            if (supportsCodeExecution) {
                SettingsToggleRow(
                    title = "Code Execution",
                    checked = tooling.codeExecutionEnabled,
                    onCheckedChange = tooling.onCodeExecutionEnabledChange
                )
            }
            if (supportsGoogleMaps) {
                SettingsToggleRow(
                    title = "Google Maps",
                    checked = tooling.googleMapsEnabled,
                    onCheckedChange = tooling.onGoogleMapsEnabledChange
                )
            }
            if (supportsComputerUse) {
                SettingsToggleRow(
                    title = "Computer Use",
                    checked = tooling.computerUseEnabled,
                    onCheckedChange = tooling.onComputerUseEnabledChange,
                    showDivider = false
                )
            }
        }
    }
}
