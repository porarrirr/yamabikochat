package com.porarri.yamabikochat.ui.components

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.porarri.yamabikochat.data.models.CodeBlock
import com.porarri.yamabikochat.utils.FileExportUtils
import com.porarri.yamabikochat.utils.SvgAnalyzer
import com.porarri.yamabikochat.utils.SvgAnalysisResult
import com.porarri.yamabikochat.utils.rememberFileExportLauncher
import kotlinx.coroutines.launch

/**
 * コードブロック表示用のカードコンポーネント
 * 
 * @param codeBlock 表示するコードブロック
 * @param modifier Modifier
 * @param onExportComplete エクスポート完了時のコールバック
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CodeBlockCard(
    codeBlock: CodeBlock,
    modifier: Modifier = Modifier,
    onExportComplete: (Boolean, String?) -> Unit = { _, _ -> }
) {
    val context = LocalContext.current
    val clipboardManager = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    var isExporting by remember { mutableStateOf(false) }
    var showFullCode by remember { mutableStateOf(false) }
    var showSvgPreview by remember { mutableStateOf(false) }
    var showActionMenu by remember { mutableStateOf(false) }
    
    // SVG解析結果をキャッシュ
    val svgAnalysisResult = remember(codeBlock.content) {
        if (codeBlock.isSvg) {
            codeBlock.getSvgAnalysisResult()
        } else {
            null
        }
    }
    
    // ファイルエクスポートランチャーを設定
    val fileExportLauncher = rememberFileExportLauncher { uri, pendingCodeBlock ->
        if (uri != null && pendingCodeBlock != null) {
            scope.launch {
                isExporting = true
                val result = FileExportUtils.saveCodeToUri(context, uri, pendingCodeBlock)
                isExporting = false
                
                when (result) {
                    is FileExportUtils.ExportResult.Success -> {
                        onExportComplete(true, null)
                    }
                    is FileExportUtils.ExportResult.Error -> {
                        onExportComplete(false, result.message)
                    }
                    is FileExportUtils.ExportResult.Cancelled -> {
                        onExportComplete(false, "エクスポートがキャンセルされました")
                    }
                }
            }
        } else {
            onExportComplete(false, "ファイル保存がキャンセルされました")
        }
    }
    
    Card(
        modifier = modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier.padding(12.dp)
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
                        imageVector = if (codeBlock.isSvg) Icons.Default.Image else Icons.Default.Code,
                        contentDescription = null,
                        tint = getLanguageColor(codeBlock.language),
                        modifier = Modifier.size(20.dp)
                    )
                    
                    Spacer(modifier = Modifier.width(8.dp))
                    
                    Column {
                        Text(
                            text = codeBlock.displayLanguage,
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        
                        Text(
                            text = codeBlock.filename,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
                
                // 統計情報
                Column(
                    horizontalAlignment = Alignment.End
                ) {
                    if (codeBlock.isSvg && svgAnalysisResult is SvgAnalysisResult.Valid) {
                        // SVG専用の統計情報
                        Text(
                            text = "${svgAnalysisResult.elementStats.totalElements}要素",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                        )
                        
                        val dimensionText = when {
                            svgAnalysisResult.width != null && svgAnalysisResult.height != null -> 
                                "${svgAnalysisResult.width!!.toInt()} × ${svgAnalysisResult.height!!.toInt()}"
                            svgAnalysisResult.viewBox != null -> 
                                "${svgAnalysisResult.viewBox!!.width.toInt()} × ${svgAnalysisResult.viewBox!!.height.toInt()}"
                            else -> "${codeBlock.size}文字"
                        }
                        
                        Text(
                            text = dimensionText,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                        )
                        
                        Text(
                            text = svgAnalysisResult.complexity.displayName,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary
                        )
                    } else {
                        // 通常のコード統計情報
                        Text(
                            text = "${codeBlock.lineCount}行",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                        )
                        
                        Text(
                            text = "${codeBlock.size}文字",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                        )
                    }
                }
            }
            
            Spacer(modifier = Modifier.height(12.dp))
            
            // コード内容プレビュー
            val displayContent = if (showFullCode || codeBlock.lineCount <= 10) {
                codeBlock.content
            } else {
                codeBlock.content.lines().take(8).joinToString("\n") + "\n..."
            }
            
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        color = MaterialTheme.colorScheme.surface,
                        shape = RoundedCornerShape(8.dp)
                    )
                    .padding(12.dp)
            ) {
                Text(
                    text = displayContent,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    lineHeight = 16.sp
                )
            }
            
            // 「もっと見る」ボタン（10行以上の場合）
            if (codeBlock.lineCount > 10) {
                Spacer(modifier = Modifier.height(8.dp))
                
                TextButton(
                    onClick = { showFullCode = !showFullCode },
                    modifier = Modifier.align(Alignment.CenterHorizontally)
                ) {
                    Text(
                        text = if (showFullCode) "縮小表示" else "全て表示 (${codeBlock.lineCount}行)",
                        style = MaterialTheme.typography.labelMedium
                    )
                }
            }
            
            // SVGプレビューセクション
            if (codeBlock.isSvg) {
                Spacer(modifier = Modifier.height(12.dp))
                
                // プレビュー切り替えボタン
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "SVGプレビュー",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    
                    TextButton(
                        onClick = { showSvgPreview = !showSvgPreview }
                    ) {
                        Icon(
                            imageVector = if (showSvgPreview) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = if (showSvgPreview) "非表示" else "表示",
                            style = MaterialTheme.typography.labelMedium
                        )
                    }
                }
                
                // SVGプレビュー表示
                if (showSvgPreview) {
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 8.dp),
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surface
                        ),
                        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
                    ) {
                        SvgPreviewWebView(
                            svgContent = codeBlock.content,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(8.dp),
                            maxHeight = 300,
                            enableZoom = true,
                            onError = { errorMessage ->
                                // プレビューエラー時の処理
                                showSvgPreview = false
                            }
                        )
                    }
                }
                
                // SVGメタデータ表示（解析結果がある場合）
                if (svgAnalysisResult is SvgAnalysisResult.Valid) {
                    Spacer(modifier = Modifier.height(8.dp))
                    
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        // 寸法情報
                        if (svgAnalysisResult.width != null && svgAnalysisResult.height != null) {
                            Column {
                                Text(
                                    text = "寸法",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                                )
                                Text(
                                    text = "${svgAnalysisResult.width!!.toInt()} × ${svgAnalysisResult.height!!.toInt()}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                        
                        // 要素統計
                        Column {
                            Text(
                                text = "形状要素",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                            )
                            Text(
                                text = "${svgAnalysisResult.elementStats.shapeElements}個",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        
                        // 複雑さレベル
                        Column {
                            Text(
                                text = "複雑さ",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                            )
                            Text(
                                text = svgAnalysisResult.complexity.displayName,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                }
            }
            
            Spacer(modifier = Modifier.height(12.dp))
            
            // アクション（アイコン中心に集約）
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
                            fileExportLauncher.exportFile(codeBlock)
                        }
                    },
                    enabled = !isExporting
                ) {
                    Icon(
                        imageVector = Icons.Default.Download,
                        contentDescription = "ダウンロード"
                    )
                }
                Spacer(modifier = Modifier.width(8.dp))
                IconButton(
                    onClick = {
                        scope.launch {
                            val shareIntent = FileExportUtils.createShareIntent(context, codeBlock)
                            shareIntent?.let { intent ->
                                try {
                                    context.startActivity(Intent.createChooser(intent, "コードを共有"))
                                    onExportComplete(true, null)
                                } catch (e: Exception) {
                                    onExportComplete(false, "共有に失敗しました: ${e.message}")
                                }
                            } ?: onExportComplete(false, "共有ファイルの作成に失敗しました")
                        }
                    },
                    enabled = !isExporting
                ) {
                    Icon(
                        imageVector = Icons.Default.Share,
                        contentDescription = "共有"
                    )
                }
                Spacer(modifier = Modifier.width(4.dp))
                Box {
                    IconButton(onClick = { showActionMenu = true }) {
                        Icon(Icons.Default.MoreVert, contentDescription = "その他")
                    }
                    DropdownMenu(
                        expanded = showActionMenu,
                        onDismissRequest = { showActionMenu = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("コードをコピー") },
                            leadingIcon = {
                                Icon(Icons.Default.ContentCopy, contentDescription = null)
                            },
                            onClick = {
                                clipboardManager.setText(AnnotatedString(codeBlock.content))
                                showActionMenu = false
                            }
                        )
                    }
                }
            }

            // 抽出方法の表示
            Spacer(modifier = Modifier.height(8.dp))
            
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "抽出方法: ${if (codeBlock.extractionMethod == "markdown") "マークダウン" else "カスタムタグ"}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                )
                
                Text(
                    text = "拡張子: .${codeBlock.fileExtension}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                )
            }
        }
    }
}

/**
 * 言語に応じた色を取得
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
