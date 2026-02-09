package com.porarri.yamabikochat.ui.components

import android.app.Activity
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.porarri.yamabikochat.data.models.CodeBlockGroup
import com.porarri.yamabikochat.data.models.GroupType
import com.porarri.yamabikochat.utils.FileExportUtils
import kotlinx.coroutines.launch

/**
 * コードブロックグループ表示用のカードコンポーネント
 * 関連するHTML、CSS、JavaScriptブロックを統合表示・エクスポート可能
 * 
 * @param group 表示するコードブロックグループ
 * @param modifier Modifier
 * @param onExportComplete エクスポート完了時のコールバック
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CodeBlockGroupCard(
    group: CodeBlockGroup,
    modifier: Modifier = Modifier,
    onExportComplete: (Boolean, String?) -> Unit = { _, _ -> }
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var isExporting by remember { mutableStateOf(false) }
    var showFullContent by remember { mutableStateOf(false) }
    var showBlockDetails by remember { mutableStateOf(false) }
    
    val stats = remember(group) { group.getStats() }
    
    // 統合HTMLエクスポート用のランチャー
    val integratedHtmlLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            result.data?.data?.let { uri ->
                scope.launch {
                    isExporting = true
                    val exportResult = FileExportUtils.saveIntegratedHtmlToUri(context, uri, group)
                    isExporting = false
                    
                    when (exportResult) {
                        is FileExportUtils.ExportResult.Success -> {
                            onExportComplete(true, "統合HTMLファイルを保存しました")
                        }
                        is FileExportUtils.ExportResult.Error -> {
                            onExportComplete(false, exportResult.message)
                        }
                        is FileExportUtils.ExportResult.Cancelled -> {
                            onExportComplete(false, "エクスポートがキャンセルされました")
                        }
                    }
                }
            }
        } else {
            onExportComplete(false, "ファイル保存がキャンセルされました")
        }
    }
    
    Card(
        modifier = modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 6.dp),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = when (group.groupType) {
                GroupType.WEB_BUNDLE -> MaterialTheme.colorScheme.primaryContainer
                GroupType.MIXED -> MaterialTheme.colorScheme.surfaceVariant
                GroupType.SINGLE -> MaterialTheme.colorScheme.surface
            }
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            // ヘッダー部分
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = when (group.groupType) {
                            GroupType.WEB_BUNDLE -> Icons.Default.Language
                            GroupType.MIXED -> Icons.Default.LibraryBooks
                            GroupType.SINGLE -> Icons.Default.Code
                        },
                        contentDescription = null,
                        tint = when (group.groupType) {
                            GroupType.WEB_BUNDLE -> MaterialTheme.colorScheme.primary
                            GroupType.MIXED -> MaterialTheme.colorScheme.secondary
                            GroupType.SINGLE -> MaterialTheme.colorScheme.onSurface
                        },
                        modifier = Modifier.size(24.dp)
                    )
                    
                    Spacer(modifier = Modifier.width(12.dp))
                    
                    Column {
                        Text(
                            text = group.groupType.displayName,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        
                        Text(
                            text = stats.getDescription(),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                        )
                    }
                }
                
                // 統計情報
                Column(
                    horizontalAlignment = Alignment.End
                ) {
                    Text(
                        text = "${stats.totalBlocks}ブロック",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.8f)
                    )
                    
                    Text(
                        text = "${stats.totalLines}行",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                    )
                    
                    if (stats.integrable) {
                        Card(
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)
                            ),
                            modifier = Modifier.padding(top = 4.dp)
                        ) {
                            Text(
                                text = "統合可能",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                            )
                        }
                    }
                }
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            // ブロック詳細の切り替え
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "コードブロック詳細",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurface
                )
                
                TextButton(
                    onClick = { showBlockDetails = !showBlockDetails }
                ) {
                    Icon(
                        imageVector = if (showBlockDetails) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = if (showBlockDetails) "非表示" else "表示",
                        style = MaterialTheme.typography.labelMedium
                    )
                }
            }
            
            // ブロック詳細表示
            if (showBlockDetails) {
                Spacer(modifier = Modifier.height(8.dp))
                
                group.blocks.forEachIndexed { index, block ->
                    if (index > 0) {
                        Spacer(modifier = Modifier.height(8.dp))
                    }
                    
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surface
                        ),
                        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
                    ) {
                        Column(
                            modifier = Modifier.padding(12.dp)
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Code,
                                    contentDescription = null,
                                    tint = getLanguageColor(block.language),
                                    modifier = Modifier.size(16.dp)
                                )
                                
                                Spacer(modifier = Modifier.width(8.dp))
                                
                                Text(
                                    text = "${block.displayLanguage} - ${block.filename}",
                                    style = MaterialTheme.typography.bodySmall,
                                    fontWeight = FontWeight.Medium
                                )
                                
                                Spacer(modifier = Modifier.weight(1f))
                                
                                Text(
                                    text = "${block.lineCount}行",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                                )
                            }
                            
                            // コードプレビュー（最初の3行のみ）
                            val previewContent = block.content.lines().take(3).joinToString("\n")
                            if (previewContent.isNotBlank()) {
                                Spacer(modifier = Modifier.height(8.dp))
                                
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .background(
                                            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                                            shape = RoundedCornerShape(6.dp)
                                        )
                                        .padding(8.dp)
                                ) {
                                    Text(
                                        text = previewContent + if (block.lineCount > 3) "\n..." else "",
                                        fontFamily = FontFamily.Monospace,
                                        fontSize = 11.sp,
                                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.8f),
                                        maxLines = 4,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }
                    }
                }
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            // アクション
            if (group.canIntegrate) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (isExporting) {
                        CircularProgressIndicator(
                            modifier = Modifier
                                .size(18.dp)
                                .padding(end = 8.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                    FilledTonalIconButton(
                        onClick = {
                            if (!isExporting) {
                                FileExportUtils.createIntegratedHtmlIntent(
                                    context,
                                    group,
                                    integratedHtmlLauncher
                                )
                            }
                        },
                        enabled = !isExporting
                    ) {
                        Icon(
                            imageVector = Icons.Default.FileDownload,
                            contentDescription = "統合HTML出力"
                        )
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                    IconButton(
                        onClick = {
                            scope.launch {
                                val shareIntent = FileExportUtils.createIntegratedHtmlShareIntent(context, group)
                                shareIntent?.let { intent ->
                                    try {
                                        context.startActivity(Intent.createChooser(intent, "統合HTMLを共有"))
                                        onExportComplete(true, "統合HTMLファイルを共有しました")
                                    } catch (e: Exception) {
                                        onExportComplete(false, "共有に失敗しました: ${e.message}")
                                    }
                                } ?: onExportComplete(false, "統合HTMLファイルの作成に失敗しました")
                            }
                        },
                        enabled = !isExporting
                    ) {
                        Icon(
                            imageVector = Icons.Default.Share,
                            contentDescription = "共有"
                        )
                    }
                }
            }

            // グループ情報表示
            Spacer(modifier = Modifier.height(12.dp))
            
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "範囲: ${group.textRange.first}-${group.textRange.last}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                )
                
                if (group.blocks.size > 1) {
                    Text(
                        text = "最大間隔: ${group.maxBlockDistance}文字",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                    )
                }
            }
        }
    }
}

/**
 * 言語に応じた色を取得（CodeBlockCardと同じ実装）
 */
@Composable
private fun getLanguageColor(language: String): Color {
    return when (language.lowercase()) {
        "python", "py" -> Color(0xFF3776ab)
        "javascript", "js" -> Color(0xFFf7df1e)
        "typescript", "ts" -> Color(0xFF3178c6)
        "html" -> Color(0xFFe34f26)
        "css" -> Color(0xFF1572b6)
        "kotlin", "kt" -> Color(0xFF7f52ff)
        "java" -> Color(0xFFed8b00)
        "json" -> Color(0xFF292929)
        "xml" -> Color(0xFFff6600)
        "sql" -> Color(0xFF336791)
        "shell", "bash", "sh" -> Color(0xFF4eaa25)
        "svg" -> Color(0xFFff9500)
        else -> MaterialTheme.colorScheme.primary
    }
}