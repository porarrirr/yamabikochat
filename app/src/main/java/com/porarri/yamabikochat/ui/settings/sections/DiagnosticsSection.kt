package com.porarri.yamabikochat.ui.settings.sections

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.BorderStroke
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.porarri.yamabikochat.BuildConfig
import com.porarri.yamabikochat.ui.settings.ApiKeyStatus
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

fun LazyListScope.diagnosticsSection(apiKeyStatus: ApiKeyStatus) {
    if (!BuildConfig.DEBUG && !BuildConfig.DIAGNOSTIC) return

    item {
        val context = LocalContext.current
        val clipboard = LocalClipboardManager.current
        val scope = rememberCoroutineScope()
        val securePrefs = remember(context) { SecurePreferencesManager.getInstance(context) }
        val encryptionAvailable = remember { securePrefs.isEncryptionAvailable() }

        var logText by remember { mutableStateOf("") }
        var showDialog by remember { mutableStateOf(false) }

        suspend fun refresh() {
            logText = withContext(Dispatchers.IO) { DiagnosticsLogger.read() }
        }

        LaunchedEffect(Unit) { refresh() }

        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text(
                    text = "診断ログ",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "Releaseで発生する不具合の原因調査用です。再現後にログをコピーして共有してください。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                DiagnosticsLabeledValue(
                    label = "端末",
                    value = "${Build.MANUFACTURER}/${Build.MODEL} (API ${Build.VERSION.SDK_INT})"
                )
                DiagnosticsLabeledValue(
                    label = "暗号化ストレージ",
                    value = if (encryptionAvailable) "利用可" else "利用不可（フォールバック）"
                )
                DiagnosticsLabeledValue(
                    label = "APIキー",
                    value = buildString {
                        append("GEMINI="); append(if (apiKeyStatus.hasGeminiKey) "OK" else "NG"); append(" / ")
                        append("OPENAI="); append(if (apiKeyStatus.hasOpenAiKey) "OK" else "NG"); append(" / ")
                        append("OPENROUTER="); append(if (apiKeyStatus.hasOpenRouterKey) "OK" else "NG"); append(" / ")
                        append("MINIMAX="); append(if (apiKeyStatus.hasMiniMaxKey) "OK" else "NG"); append(" / ")
                        append("ZAI="); append(if (apiKeyStatus.hasZaiKey) "OK" else "NG"); append(" / ")
                        append("OPENCODE_GO="); append(if (apiKeyStatus.hasOpenCodeGoKey) "OK" else "NG"); append(" / ")
                        append("CLINEPASS="); append(if (apiKeyStatus.hasClinePassKey) "OK" else "NG"); append(" / ")
                        append("ALIBABA_CODING_PLAN="); append(if (apiKeyStatus.hasAlibabaCodingPlanKey) "OK" else "NG"); append(" / ")
                        append("ALIBABA_MCP_TOKEN="); append(if (apiKeyStatus.hasAlibabaMcpAuthorizationToken) "OK" else "NG"); append(" / ")
                        append("CODEX="); append(if (apiKeyStatus.hasCodexAuth) "OK" else "NG"); append(" / ")
                        append("SUPERGROK="); append(if (apiKeyStatus.hasSuperGrokAuth) "OK" else "NG")
                    }
                )

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = { scope.launch { refresh() } }) { Text("更新") }
                    TextButton(
                        enabled = logText.isNotBlank(),
                        onClick = {
                            clipboard.setText(AnnotatedString(logText))
                            Toast.makeText(context, "診断ログをコピーしました", Toast.LENGTH_SHORT).show()
                        }
                    ) { Text("コピー") }
                    TextButton(
                        enabled = logText.isNotBlank(),
                        onClick = {
                            DiagnosticsLogger.clear()
                            scope.launch { refresh() }
                            Toast.makeText(context, "診断ログをクリアしました", Toast.LENGTH_SHORT).show()
                        }
                    ) { Text("クリア") }
                    TextButton(
                        enabled = logText.isNotBlank(),
                        onClick = { showDialog = true }
                    ) { Text("表示") }
                }

                if (logText.isBlank()) {
                    Text(
                        text = "ログはありません。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    val preview = remember(logText) { logText.takeLast(2000) }
                    Text(
                        text = preview,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        if (showDialog) {
            AlertDialog(
                onDismissRequest = { showDialog = false },
                title = { Text("診断ログ") },
                text = {
                    Text(
                        text = logText,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 320.dp)
                            .verticalScroll(rememberScrollState()),
                        style = MaterialTheme.typography.bodySmall
                    )
                },
                confirmButton = {
                    TextButton(
                        onClick = {
                            clipboard.setText(AnnotatedString(logText))
                            Toast.makeText(context, "診断ログをコピーしました", Toast.LENGTH_SHORT).show()
                        }
                    ) { Text("コピー") }
                },
                dismissButton = {
                    TextButton(onClick = { showDialog = false }) { Text("閉じる") }
                }
            )
        }
    }
}

@Composable
private fun DiagnosticsLabeledValue(
    label: String,
    value: String
) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface
        )
    }
}
