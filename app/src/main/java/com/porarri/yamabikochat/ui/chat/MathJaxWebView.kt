package com.porarri.yamabikochat.ui.chat

import android.annotation.SuppressLint
import android.os.Build
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.viewinterop.AndroidView
import java.io.ByteArrayInputStream

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun MathJaxWebView(
    content: String,
    modifier: Modifier = Modifier,
    onOpenUrl: (String) -> Boolean
) {
    val textColor = MaterialTheme.colorScheme.onSurface
    val backgroundColor = MaterialTheme.colorScheme.surface
    val textColorHex = String.format("#%06X", (0xFFFFFF and textColor.toArgb()))
    val backgroundColorHex = String.format("#%06X", (0xFFFFFF and backgroundColor.toArgb()))
    
    val htmlContent = remember(content, textColorHex, backgroundColorHex) {
        createMathJaxHtml(content, textColorHex, backgroundColorHex)
    }
    
    val webViewRefState = remember { mutableStateOf<WebView?>(null) }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            WebView(ctx).apply {
                webViewRefState.value = this
                // 明示的なLayoutParamsでwrapContent高さを保証
                layoutParams = android.widget.FrameLayout.LayoutParams(
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                    android.view.ViewGroup.LayoutParams.WRAP_CONTENT
                )
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.loadWithOverviewMode = true
                settings.useWideViewPort = true
                settings.builtInZoomControls = false
                settings.displayZoomControls = false

                // パフォーマンス最適化
                settings.cacheMode = android.webkit.WebSettings.LOAD_CACHE_ELSE_NETWORK
                settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW

                // セキュリティ設定
                // MathJaxのスクリプトは app/src/main/assets/mathjax 下のローカル資産から読み込むため、
                // file:///android_asset/ へのアクセスを許可する
                settings.allowFileAccess = true
                // コンテンツアクセスは不要なので無効化
                settings.allowContentAccess = false
                settings.allowFileAccessFromFileURLs = false
                settings.allowUniversalAccessFromFileURLs = false
                settings.blockNetworkLoads = true
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    settings.safeBrowsingEnabled = true
                }

                // 外観設定
                settings.textZoom = 100
                settings.minimumFontSize = 8
                settings.defaultFontSize = 16

                // ハードウェア加速の有効化
                setLayerType(android.view.View.LAYER_TYPE_HARDWARE, null)

                webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView?, url: String?) {
                        super.onPageFinished(view, url)
                        // MathJax読み込み後に安全にtypesetを依頼（fallbackはHTML側で制御）
                        view?.evaluateJavascript(
                            """
                            (function() {
                                try {
                                    if (typeof window.requestMathJaxTypeset === 'function') {
                                        window.requestMathJaxTypeset();
                                    }
                                } catch (e) {
                                    // no-op
                                }
                            })();
                            """.trimIndent(),
                            null
                        )
                    }

                    override fun onReceivedError(view: WebView?, request: android.webkit.WebResourceRequest?, error: android.webkit.WebResourceError?) {
                        super.onReceivedError(view, request, error)
                        // ネットワークエラー時のフォールバック
                        android.util.Log.w("MathJaxWebView", "WebView error: ${error?.description} for ${request?.url}")
                        // ネットワークエラー時はフォールバックを適用
                        view?.post {
                            view.evaluateJavascript("window.applyFallback && window.applyFallback();", null)
                        }
                    }

                    override fun shouldOverrideUrlLoading(
                        view: WebView?,
                        request: WebResourceRequest?
                    ): Boolean {
                        val targetUrl = request?.url?.toString().orEmpty()
                        if (isInternalMathJaxResource(targetUrl)) return false
                        onOpenUrl(targetUrl)
                        return true
                    }

                    @Deprecated("Deprecated in Java")
                    override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                        val targetUrl = url.orEmpty()
                        if (isInternalMathJaxResource(targetUrl)) return false
                        onOpenUrl(targetUrl)
                        return true
                    }

                    override fun shouldInterceptRequest(
                        view: WebView?,
                        request: WebResourceRequest?
                    ): WebResourceResponse? {
                        val url = request?.url?.toString().orEmpty()
                        return if (isInternalMathJaxResource(url)) {
                            null
                        } else {
                            WebResourceResponse(
                                "text/plain",
                                "UTF-8",
                                ByteArrayInputStream(ByteArray(0))
                            )
                        }
                    }

                    @Deprecated("Deprecated in Java")
                    override fun shouldInterceptRequest(view: WebView?, url: String?): WebResourceResponse? {
                        val safeUrl = url.orEmpty()
                        return if (isInternalMathJaxResource(safeUrl)) {
                            null
                        } else {
                            WebResourceResponse(
                                "text/plain",
                                "UTF-8",
                                ByteArrayInputStream(ByteArray(0))
                            )
                        }
                    }
                }

                loadDataWithBaseURL(
                    "file:///android_asset/mathjax/",
                    htmlContent,
                    "text/html",
                    "UTF-8",
                    null
                )
            }
        },
        update = { webView ->
            webView.loadDataWithBaseURL(
                "file:///android_asset/mathjax/",
                htmlContent,
                "text/html",
                "UTF-8",
                null
            )
        }
    )

    DisposableEffect(Unit) {
        onDispose {
            webViewRefState.value?.let { webView ->
                webView.stopLoading()
                webView.clearHistory()
                webView.removeAllViews()
                webView.destroy()
            }
            webViewRefState.value = null
        }
    }
}

/**
 * MathJaxを使用したHTMLテンプレートを生成
 */
private fun createMathJaxHtml(
    content: String,
    textColor: String,
    backgroundColor: String
): String {
    // LaTeX数式記法を処理
    val processedContent = preprocessLatexForMathJax(content)
    
    return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <script type="text/javascript">
                // MathJax読み込み状態管理
                var mathJaxLoaded = false;

                window.applyFallback = function() {
                    if (mathJaxLoaded) return; // 既に読み込み済みの場合は何もしない
                    document.documentElement.classList.add('mathjax-fallback');
                };

                window.requestMathJaxTypeset = function() {
                    if (window.MathJax && MathJax.typesetPromise) {
                        MathJax.startup.promise
                            .then(function() {
                                return MathJax.typesetPromise();
                            })
                            .catch(function() {
                                window.applyFallback();
                            });
                    }
                };
            </script>
            <!-- MathJax 3.x で安定性を向上 -->
            <script>
                window.MathJax = {
                    tex: {
                        inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
                        displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']],
                        processEscapes: true,
                        processEnvironments: true
                    },
                    svg: {
                        fontCache: 'none'
                    },
                    startup: {
                        typeset: false,
                        ready: function() {
                            mathJaxLoaded = true;
                            MathJax.startup.defaultReady();
                            window.requestMathJaxTypeset();
                        }
                    },
                    options: {
                        renderActions: {
                            addMenu: [0, '', '']
                        }
                    }
                };
            </script>
            <script type="text/javascript" id="MathJax-script" async
                src="tex-svg.js"
                onerror="window.applyFallback && window.applyFallback();">
            </script>
            <style>
                body {
                    font-family: system-ui, -apple-system, sans-serif;
                    font-size: 16px;
                    line-height: 1.6;
                    color: $textColor;
                    background-color: $backgroundColor;
                    margin: 0;
                    padding: 8px;
                    word-wrap: break-word;
                }
                
                .math-container {
                    overflow-x: auto;
                    margin: 4px 0;
                }
                
                .math-container svg {
                    color: $textColor;
                    fill: currentColor;
                }
                
                /* 選択可能にする */
                * {
                    -webkit-user-select: text;
                    -moz-user-select: text;
                    -ms-user-select: text;
                    user-select: text;
                }
            </style>
        </head>
        <body>
            <div class="math-container">
                $processedContent
            </div>
        </body>
        </html>
    """.trimIndent()
}

/**
 * LaTeX記法をMathJax用に前処理
 */
private fun preprocessLatexForMathJax(content: String): String {
    // 1) HTMLエスケープ
    val escaped = escapeHtml(content)

    // 2) Markdownを最小限HTML化（数式を壊さない範囲）
    val markdownHtml = markdownToHtml(escaped)

    // 3) 数式記法の正規化（MathJaxが解釈しやすい形へ）
    return markdownHtml
        .replace("\\(", "$")
        .replace("\\)", "$")
        .replace("\\[", "$$")
        .replace("\\]", "$$")
}

/**
 * HTMLエスケープ（WebView内での安全性を担保）
 */
private fun escapeHtml(text: String): String =
    text
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&#39;")

/**
 * Markdownを最小限HTMLに変換する。
 * WebViewではMarkdownエンジンを使っていないため、
 * 数式レンダリング時でも記号が露出しないようにする。
 */
private fun markdownToHtml(markdown: String): String {
    val lines = markdown.split("\n")
    val html = StringBuilder()
    var inUl = false
    var inOl = false

    fun closeListsIfNeeded() {
        if (inUl) {
            html.append("</ul>")
            inUl = false
        }
        if (inOl) {
            html.append("</ol>")
            inOl = false
        }
    }

    lines.forEach { rawLine ->
        val line = rawLine.trimEnd()

        if (line.isBlank()) {
            closeListsIfNeeded()
            return@forEach
        }

        // 見出し
        val headingMatch = Regex("^(#{1,6})\\s+(.+)$").find(line)
        if (headingMatch != null) {
            closeListsIfNeeded()
            val level = headingMatch.groupValues[1].length
            val content = inlineMarkdownToHtml(headingMatch.groupValues[2])
            html.append("<h").append(level).append(">")
                .append(content)
                .append("</h").append(level).append(">")
            return@forEach
        }

        // 箇条書き（unordered）
        val ulMatch = Regex("^[-*+]\\s+(.+)$").find(line)
        if (ulMatch != null) {
            if (inOl) {
                html.append("</ol>")
                inOl = false
            }
            if (!inUl) {
                html.append("<ul>")
                inUl = true
            }
            html.append("<li>")
                .append(inlineMarkdownToHtml(ulMatch.groupValues[1]))
                .append("</li>")
            return@forEach
        }

        // 箇条書き（ordered）
        val olMatch = Regex("^(\\d+)\\.\\s+(.+)$").find(line)
        if (olMatch != null) {
            if (inUl) {
                html.append("</ul>")
                inUl = false
            }
            if (!inOl) {
                html.append("<ol>")
                inOl = true
            }
            val itemContent = inlineMarkdownToHtml(olMatch.groupValues[2])
            html.append("<li value=\"")
                .append(olMatch.groupValues[1])
                .append("\">")
                .append(itemContent)
                .append("</li>")
            return@forEach
        }

        // 通常段落
        closeListsIfNeeded()
        html.append("<p>")
            .append(inlineMarkdownToHtml(line))
            .append("</p>")
    }

    if (inUl) html.append("</ul>")
    if (inOl) html.append("</ol>")

    return html.toString()
}

/**
 * インラインMarkdownをHTMLに変換する（最小限）。
 */
private fun inlineMarkdownToHtml(text: String): String {
    var result = text

    // インラインコード
    result = result.replace(Regex("`([^`]+)`")) { match ->
        "<code>${match.groupValues[1]}</code>"
    }

    // リンク
    result = result.replace(Regex("\\[([^\\]]+)]\\(([^)]+)\\)")) { match ->
        val label = match.groupValues[1]
        val url = match.groupValues[2]
        "<a href=\"$url\" rel=\"noopener noreferrer\">$label</a>"
    }

    // 太字
    result = result.replace(Regex("\\*\\*([^*]+)\\*\\*")) { match ->
        "<strong>${match.groupValues[1]}</strong>"
    }

    // 斜体（単純化のため *text* のみ対応）
    result = result.replace(Regex("\\*([^*]+)\\*")) { match ->
        "<em>${match.groupValues[1]}</em>"
    }

    // 改行を<br>へ（段落内改行の表現）
    result = result.replace("\n", "<br>")

    return result
}

private fun isInternalMathJaxResource(url: String): Boolean {
    val safeUrl = url.trim()
    return safeUrl.startsWith("about:") ||
        safeUrl.startsWith("data:") ||
        safeUrl.startsWith("file:///android_asset/mathjax/")
}
