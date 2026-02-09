package com.porarri.yamabikochat.ui.chat

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.util.TypedValue
import android.widget.TextView
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import android.webkit.WebView
import android.webkit.WebViewClient
import com.porarri.yamabikochat.data.models.CodeBlock
import com.porarri.yamabikochat.ui.components.CodeBlockCard
import com.porarri.yamabikochat.utils.CodeExtractorUtils
import kotlinx.coroutines.launch
import io.noties.markwon.Markwon
import io.noties.markwon.html.HtmlPlugin
import io.noties.markwon.image.ImagesPlugin
import io.noties.markwon.ext.latex.JLatexMathPlugin
import io.noties.markwon.inlineparser.MarkwonInlineParserPlugin

/**
 * 高度な数式解析システム - 複雑なLaTeX記法を正しく処理
 */
private fun preprocessMathExpressions(text: String): String {
    var result = text
    
    // ブロック数式の処理 ($$...$$ → \[...\])
    result = processBlockMath(result)
    
    // インライン数式の処理 ($...$ → \(...\))
    result = processInlineMath(result)
    
    // LaTeX数式コマンドの最適化
    result = optimizeLatexCommands(result)
    
    return result
}

/**
 * LaTeX数式コマンドの最適化 - 一般的なコマンドの処理
 */
private fun optimizeLatexCommands(text: String): String {
    var result = text
    
    // 数式環境内でのコマンド最適化
    result = result.replace("\\\\text\\{([^}]+)\\}".toRegex(), "\\\\text{$1}")
    result = result.replace("\\\\,", "\\\\,")  // 薄いスペース
    result = result.replace("\\\\:", "\\\\:")  // 中スペース
    result = result.replace("\\\\;", "\\\\;")  // 太いスペース
    
    // 三角関数と対数
    result = result.replace("\\\\sin", "\\\\sin")
    result = result.replace("\\\\cos", "\\\\cos")
    result = result.replace("\\\\tan", "\\\\tan")
    result = result.replace("\\\\log", "\\\\log")
    
    // ギリシャ文字
    result = result.replace("\\\\theta", "\\\\theta")
    result = result.replace("\\\\mu", "\\\\mu")
    result = result.replace("\\\\pi", "\\\\pi")
    result = result.replace("\\\\alpha", "\\\\alpha")
    result = result.replace("\\\\beta", "\\\\beta")
    result = result.replace("\\\\gamma", "\\\\gamma")
    
    // 分数と平方根
    result = result.replace("\\\\frac", "\\\\frac")
    result = result.replace("\\\\sqrt", "\\\\sqrt")
    
    // 上付き・下付き
    result = result.replace("\\^([0-9]+)".toRegex(), "^{$1}")
    result = result.replace("_([0-9]+)".toRegex(), "_{$1}")
    
    return result
}

/**
 * ブロック数式の処理 - ネストした括弧を考慮
 */
private fun processBlockMath(text: String): String {
    val result = StringBuilder()
    var i = 0
    
    while (i < text.length) {
        if (i < text.length - 1 && text[i] == '$' && text[i + 1] == '$') {
            // $$ の開始を検出
            val startIndex = i + 2
            val endIndex = findMatchingBlockEnd(text, startIndex)
            
            if (endIndex != -1) {
                val mathContent = text.substring(startIndex, endIndex)
                result.append("\\\\[").append(mathContent).append("\\\\]")
                i = endIndex + 2
            } else {
                result.append(text[i])
                i++
            }
        } else {
            result.append(text[i])
            i++
        }
    }
    
    return result.toString()
}

/**
 * インライン数式の処理 - 括弧のバランスを考慮
 */
private fun processInlineMath(text: String): String {
    val result = StringBuilder()
    var i = 0
    
    while (i < text.length) {
        if (text[i] == '$' && (i == 0 || text[i - 1] != '$') && 
            (i == text.length - 1 || text[i + 1] != '$')) {
            // 単独の $ を検出
            val startIndex = i + 1
            val endIndex = findMatchingInlineEnd(text, startIndex)
            
            if (endIndex != -1) {
                val mathContent = text.substring(startIndex, endIndex)
                // 異なるアプローチ: $...$ 形式を保持するか、異なる形式に変換
                result.append("$$").append(mathContent).append("$$")
                i = endIndex + 1
            } else {
                result.append(text[i])
                i++
            }
        } else {
            result.append(text[i])
            i++
        }
    }
    
    return result.toString()
}

/**
 * ブロック数式の終了位置を検出
 */
private fun findMatchingBlockEnd(text: String, startIndex: Int): Int {
    var i = startIndex
    
    while (i < text.length - 1) {
        if (text[i] == '$' && text[i + 1] == '$') {
            return i
        }
        i++
    }
    
    return -1
}

/**
 * インライン数式の終了位置を検出 - 括弧のバランスを考慮
 */
private fun findMatchingInlineEnd(text: String, startIndex: Int): Int {
    var i = startIndex
    var braceLevel = 0
    
    while (i < text.length) {
        when (text[i]) {
            '{' -> braceLevel++
            '}' -> braceLevel--
            '$' -> {
                if (braceLevel == 0) {
                    return i
                }
            }
            '\n' -> {
                // 改行で数式を終了
                return -1
            }
        }
        i++
    }
    
    return -1
}

@Composable
fun MarkdownText(
    markdown: String,
    modifier: Modifier = Modifier,
    enableCodeExtraction: Boolean = true
) {
    if (LocalInspectionMode.current) {
        Text(
            text = markdown,
            modifier = modifier.padding(4.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface
        )
        return
    }

    val context = LocalContext.current
    val repository = remember {
        (context.applicationContext as com.porarri.yamabikochat.MyApplication).repository
    }
    
    // 設定を監視
    val settings by repository.getSettings().collectAsState(initial = null)
    val mathRenderingEnabled = settings?.mathRenderingEnabled ?: true
    
    // コードブロック検知
    val codeBlocks = remember(markdown, enableCodeExtraction) {
        if (enableCodeExtraction && CodeExtractorUtils.containsCodeBlocks(markdown)) {
            CodeExtractorUtils.extractCodeBlocks(markdown)
        } else {
            emptyList()
        }
    }
    
    // スナックバー用の状態
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    
    // 設定変更を確認
    remember(mathRenderingEnabled) {
        mathRenderingEnabled
    }
    
    Box(modifier = modifier) {
        Column {
            // コードブロックが検知された場合、先にコードカードを表示
            if (codeBlocks.isNotEmpty()) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    codeBlocks.forEach { codeBlock ->
                        CodeBlockCard(
                            codeBlock = codeBlock,
                            onExportComplete = { success, message ->
                                scope.launch {
                                    val snackbarMessage = if (success) {
                                        "ファイル「${codeBlock.filename}」が正常に保存されました"
                                    } else {
                                        message ?: "ファイル保存に失敗しました"
                                    }
                                    snackbarHostState.showSnackbar(snackbarMessage)
                                }
                            }
                        )
                    }
                    
                    // コードブロック後にスペースを追加
                    Spacer(modifier = Modifier.height(16.dp))
                }
            }
            
            // メインのマークダウンテキスト表示
            val displayMarkdown = if (codeBlocks.isNotEmpty() && enableCodeExtraction) {
                // コードブロック部分を除去して表示
                removeCodeBlocksFromMarkdown(markdown, codeBlocks)
            } else {
                markdown
            }
            
            // 数式レンダリングが有効な場合のみ数式処理を行う
            if (mathRenderingEnabled) {
                // 数式が含まれているかどうかを判定（WebView強制条件）
                val containsMath = remember(displayMarkdown) {
                    displayMarkdown.contains("$$") ||
                    displayMarkdown.contains("$") ||
                    displayMarkdown.contains("\\(") || displayMarkdown.contains("\\)") ||
                    displayMarkdown.contains("\\[") || displayMarkdown.contains("\\]") ||
                    displayMarkdown.contains("\\\\") ||
                    displayMarkdown.contains("frac") || displayMarkdown.contains("sqrt") ||
                    displayMarkdown.contains("sum") || displayMarkdown.contains("int") ||
                    displayMarkdown.contains("theta") || displayMarkdown.contains("mu") ||
                    displayMarkdown.contains("pi") || displayMarkdown.contains("alpha") ||
                    displayMarkdown.contains("beta") || displayMarkdown.contains("gamma") ||
                    displayMarkdown.contains("θ") || displayMarkdown.contains("μ") || displayMarkdown.contains("π") ||
                    displayMarkdown.contains("≈") || displayMarkdown.contains("≠") ||
                    displayMarkdown.contains("≤") || displayMarkdown.contains("≥")
                }

                if (containsMath) {
                    // 数式を含む場合は必ずWebView(MathJax)でレンダリング
                    MathJaxWebView(
                        content = displayMarkdown,
                        modifier = Modifier.fillMaxWidth()
                    )
                } else {
                    // 数式がない場合は通常のTextViewを使用
                    SimpleMarkdownText(
                        markdown = displayMarkdown,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            } else {
                // 数式レンダリングが無効な場合は通常のTextViewのみ使用
                SimpleMarkdownText(
                    markdown = displayMarkdown,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
        
        // スナックバーホスト
        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier.align(androidx.compose.ui.Alignment.BottomCenter)
        )
    }
}

/**
 * マークダウンからコードブロックを除去する
 */
private fun removeCodeBlocksFromMarkdown(
    markdown: String,
    codeBlocks: List<CodeBlock>
): String {
    if (codeBlocks.isEmpty()) return markdown
    
    var result = markdown
    // 後ろから順番に除去（インデックスの変更を防ぐため）
    codeBlocks.sortedByDescending { it.startIndex }.forEach { codeBlock ->
        if (codeBlock.startIndex < result.length && codeBlock.endIndex <= result.length) {
            result = result.removeRange(codeBlock.startIndex, codeBlock.endIndex)
                .replace(Regex("\\n\\s*\\n\\s*\\n"), "\n\n") // 余分な空行を削除
        }
    }
    
    return result.trim()
}

@Composable
private fun SimpleMarkdownText(
    markdown: String,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val textColor = MaterialTheme.colorScheme.onSurface.toArgb()
    val backgroundColor = Color.TRANSPARENT
    val typography = MaterialTheme.typography.bodyLarge
    val density = LocalDensity.current
    val textSizePx = with(density) { typography.fontSize.toPx() }

    val markwon = remember(context, textColor, textSizePx) {
        Markwon.builder(context)
            .usePlugin(JLatexMathPlugin.create(textSizePx))
            .usePlugin(MarkwonInlineParserPlugin.create())
            .usePlugin(HtmlPlugin.create())
            .usePlugin(ImagesPlugin.create())
            .build()
    }
    
    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            TextView(ctx).apply {
                setTextColor(textColor)
                setBackgroundColor(backgroundColor)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, typography.fontSize.value)
                typeface = Typeface.DEFAULT
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                    lineHeight = (typography.lineHeight.value * resources.displayMetrics.density).toInt()
                }
                setPadding(0, 0, 0, 0)
                setTextIsSelectable(true)
                // テキストの選択可能性を有効にする
                isClickable = true
                isFocusable = true
                isFocusableInTouchMode = true
                // タッチアンドホールド（長押し）でテキスト選択を有効にする
                setOnLongClickListener {
                    // TextView内でのテキスト選択処理を優先
                    false
                }
            }
        },
        update = { textView ->
            markwon.setMarkdown(textView, markdown)
            textView.setTextColor(textColor)
        }
    )
}
