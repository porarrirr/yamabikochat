package com.porarri.yamabikochat.ui.components

import android.content.Context
import android.graphics.Canvas
import android.view.View
import android.view.View.MeasureSpec
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.os.Build
import java.io.ByteArrayInputStream
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.caverock.androidsvg.SVG
import com.caverock.androidsvg.SVGParseException
import android.graphics.RectF
import com.porarri.yamabikochat.utils.SvgAnalyzer
import com.porarri.yamabikochat.utils.SvgAnalysisResult
import com.porarri.yamabikochat.utils.SvgLogger
import kotlinx.coroutines.delay

/**
 * ハイブリッドSVG表示コンポーネント（WebView + AndroidSVGの自動フォールバック）
 * 
 * @param svgContent SVGコンテンツ
 * @param modifier Modifier
 * @param maxHeight 最大高さ（dp）
 * @param enableZoom ズーム機能を有効にするか
 * @param onError エラー時のコールバック
 */
@Composable
fun SvgPreviewWebView(
    svgContent: String,
    modifier: Modifier = Modifier,
    maxHeight: Int = 400,
    enableZoom: Boolean = true,
    onError: (String) -> Unit = {}
) {
    val density = LocalDensity.current
    
    // dpをpxに変換（AndroidSVGで正確に使用するため）
    val maxHeightPx = with(density) { maxHeight.dp.roundToPx() }
    
    var displayMode by remember { mutableStateOf(SvgDisplayMode.AUTO_DETECT) }
    var isLoading by remember { mutableStateOf(true) }
    var hasError by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf("") }
    var fallbackTriggered by remember { mutableStateOf(false) }
    
    // SVGの分析結果を取得
    val analysisResult = remember(svgContent) {
        SvgLogger.logSvgProcessStart(svgContent.length)
        val result = SvgAnalyzer.analyzeSvg(svgContent)
        SvgLogger.d("SVG分析完了: result=${result::class.simpleName}")
        result
    }
    
    // 表示方式の自動選択
    LaunchedEffect(svgContent, fallbackTriggered) {
        displayMode = if (fallbackTriggered) {
            SvgLogger.logFallbackTriggered("WebView", "AndroidSVG", "WebView表示失敗またはタイムアウト")
            SvgDisplayMode.ANDROID_SVG_NATIVE
        } else {
            SvgLogger.d("WebView方式で表示開始")
            SvgDisplayMode.WEBVIEW_HTML
        }
        
        // WebViewの自動タイムアウト（3秒で強制フォールバック）
        if (!fallbackTriggered) {
            delay(3000)
            if (isLoading) {
                SvgLogger.logFallbackTriggered("WebView", "AndroidSVG", "WebViewタイムアウト(3秒)")
                fallbackTriggered = true
                isLoading = true
            }
        }
    }
    
    Box(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(max = maxHeight.dp)
            .clip(RoundedCornerShape(8.dp))
    ) {
        when (displayMode) {
            SvgDisplayMode.WEBVIEW_HTML -> {
                SvgWebViewDisplay(
                    svgContent = svgContent,
                    analysisResult = analysisResult,
                    maxHeight = maxHeight,
                    enableZoom = enableZoom,
                    onLoaded = { 
                        SvgLogger.logSvgProcessSuccess("WebView")
                        isLoading = false 
                    },
                    onError = { error ->
                        SvgLogger.logSvgProcessError("WebView", error)
                        errorMessage = error
                        fallbackTriggered = true
                        isLoading = true
                    }
                )
            }
            
            SvgDisplayMode.ANDROID_SVG_NATIVE -> {
                SvgNativeDisplay(
                    svgContent = svgContent,
                    analysisResult = analysisResult,
                    maxHeightPx = maxHeightPx,
                    onLoaded = { 
                        SvgLogger.logSvgProcessSuccess("AndroidSVG")
                        isLoading = false 
                    },
                    onError = { error ->
                        SvgLogger.logSvgProcessError("AndroidSVG", error)
                        hasError = true
                        errorMessage = "すべての表示方式が失敗: $error"
                        onError(errorMessage)
                        isLoading = false
                    }
                )
            }
            
            SvgDisplayMode.AUTO_DETECT -> {
                // 初期化中
                SvgLogger.d("SVG表示方式を自動選択中...")
            }
        }
        
        // エラー表示
        if (hasError) {
            SvgErrorDisplay(
                errorMessage = errorMessage,
                analysisResult = analysisResult,
                modifier = Modifier.fillMaxSize()
            )
        }
        
        // ローディングインジケータ
        if (isLoading && !hasError) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        strokeWidth = 2.dp
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = when (displayMode) {
                            SvgDisplayMode.WEBVIEW_HTML -> "WebView読み込み中..."
                            SvgDisplayMode.ANDROID_SVG_NATIVE -> "AndroidSVG描画中..."
                            SvgDisplayMode.AUTO_DETECT -> "表示方式選択中..."
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
        
        // フォールバック状態の表示
        if (fallbackTriggered && !hasError) {
            Text(
                text = "🔄 フォールバックモード",
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.primary
            )
        }
    }
}

/**
 * SVG表示モード列挙型
 */
enum class SvgDisplayMode {
    AUTO_DETECT,        // 自動選択中
    WEBVIEW_HTML,       // WebView + HTML方式
    ANDROID_SVG_NATIVE  // AndroidSVGライブラリ直接描画
}

/**
 * WebView方式でのSVG表示コンポーネント
 */
@Composable
private fun SvgWebViewDisplay(
    svgContent: String,
    analysisResult: SvgAnalysisResult,
    maxHeight: Int,
    enableZoom: Boolean,
    onLoaded: () -> Unit,
    onError: (String) -> Unit
) {
    val htmlContent = remember(svgContent, maxHeight) {
        SvgLogger.d("HTMLテンプレート生成: WebView方式")
        generateSvgHtml(svgContent, analysisResult, maxHeight)
    }

    var webViewRef by remember { mutableStateOf<WebView?>(null) }

    AndroidView(
        factory = { ctx ->
            WebView(ctx).apply {
                webViewRef = this
                webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView?, url: String?) {
                        super.onPageFinished(view, url)
                        SvgLogger.d("WebView読み込み完了")
                        onLoaded()
                    }

                    override fun onReceivedError(
                        view: WebView?,
                        errorCode: Int,
                        description: String?,
                        failingUrl: String?
                    ) {
                        super.onReceivedError(view, errorCode, description, failingUrl)
                        val error = description ?: "WebView表示エラー"
                        SvgLogger.e("WebViewエラー: code=$errorCode, desc=$error")
                        onError(error)
                    }

                    override fun shouldInterceptRequest(
                        view: WebView?,
                        request: WebResourceRequest?
                    ): WebResourceResponse? {
                        val url = request?.url?.toString().orEmpty()
                        return if (url.startsWith("about:") || url.startsWith("data:")) {
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
                        return if (safeUrl.startsWith("about:") || safeUrl.startsWith("data:")) {
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

                settings.apply {
                    // SVG表示にJavaScriptは不要なので無効化（XSS対策）
                    javaScriptEnabled = false
                    domStorageEnabled = false
                    loadWithOverviewMode = true
                    useWideViewPort = true
                    setSupportZoom(enableZoom)
                    builtInZoomControls = enableZoom
                    displayZoomControls = false
                    allowFileAccess = false
                    allowContentAccess = false
                    allowUniversalAccessFromFileURLs = false
                    allowFileAccessFromFileURLs = false
                    blockNetworkLoads = true
                    mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        safeBrowsingEnabled = true
                    }
                }

                SvgLogger.d("WebViewにHTMLを読み込み開始")
                loadDataWithBaseURL(null, htmlContent, "text/html", "UTF-8", null)
            }
        },
        update = { view ->
            view.loadDataWithBaseURL(null, htmlContent, "text/html", "UTF-8", null)
        },
        modifier = Modifier.fillMaxSize()
    )

    DisposableEffect(Unit) {
        onDispose {
            webViewRef?.let { webView ->
                webView.stopLoading()
                webView.clearHistory()
                webView.removeAllViews()
                webView.destroy()
            }
            webViewRef = null
        }
    }
}

/**
 * AndroidSVGライブラリ方式でのSVG表示コンポーネント
 */
@Composable
private fun SvgNativeDisplay(
    svgContent: String,
    analysisResult: SvgAnalysisResult,
    maxHeightPx: Int,
    onLoaded: () -> Unit,
    onError: (String) -> Unit
) {
    AndroidView(
        factory = { ctx ->
            SvgLogger.d("AndroidSVG描画開始")
            createSvgView(ctx, svgContent, maxHeightPx, onLoaded, onError)
        },
        modifier = Modifier.fillMaxSize()
    )
}

/**
 * AndroidSVGを使ったカスタムViewを作成（改善版）
 */
private fun createSvgView(
    context: Context,
    svgContent: String,
    maxHeightPx: Int,
    onLoaded: () -> Unit,
    onError: (String) -> Unit
): View {
    return object : View(context) {
        private var svg: SVG? = null
        private var viewWidth: Int = 400
        private var viewHeight: Int = 300
        private var parseSuccess = false
        private var hasValidViewBox = false
        private var viewBox: RectF? = null
        
        init {
            try {
                SvgLogger.d("AndroidSVG開始: content length=${svgContent.length}")
                
                // SVGパース処理（堅牢化）
                svg = SVG.getFromString(svgContent)
                parseSuccess = true
                
                // サイズ計算の改善
                calculateOptimalSize(maxHeightPx)
                
                SvgLogger.d("AndroidSVGパース成功: ${viewWidth}x${viewHeight}")
                onLoaded()
                
            } catch (e: SVGParseException) {
                val error = "SVGパースエラー: ${e.message}"
                SvgLogger.e(error, e)
                parseSuccess = false
                onError(error)
            } catch (e: IllegalArgumentException) {
                val error = "SVG形式エラー: ${e.message}"
                SvgLogger.e(error, e)
                parseSuccess = false
                onError(error)
            } catch (e: Exception) {
                val error = "AndroidSVG初期化エラー: ${e.message}"
                SvgLogger.e(error, e)
                parseSuccess = false
                onError(error)
            }
        }
        
        private fun calculateOptimalSize(maxHeightPx: Int) {
            svg?.let { svgInstance ->
                try {
                    // SVG寸法の取得と検証
                    val docWidth = svgInstance.documentWidth
                    val docHeight = svgInstance.documentHeight
                    
                    // ViewBox情報の取得
                    viewBox = try {
                        svgInstance.documentViewBox
                    } catch (e: Exception) {
                        null
                    }
                    
                    val hasExplicitDimensions = docWidth > 0 && docHeight > 0
                    hasValidViewBox = viewBox != null && viewBox!!.width() > 0 && viewBox!!.height() > 0
                    
                    when {
                        hasExplicitDimensions -> {
                            // width/height属性が明示されている場合
                            val aspectRatio = docWidth / docHeight
                            viewHeight = minOf(docHeight.toInt(), maxHeightPx)
                            viewWidth = (viewHeight * aspectRatio).toInt()
                            
                            // 描画サイズを設定
                            svgInstance.setDocumentWidth(viewWidth.toFloat())
                            svgInstance.setDocumentHeight(viewHeight.toFloat())
                            
                            SvgLogger.d("SVG明示寸法設定: ${viewWidth}x${viewHeight} (aspect ratio: $aspectRatio)")
                        }
                        hasValidViewBox -> {
                            // width/height未定義だがviewBoxがある場合
                            val vb = viewBox!!
                            val aspectRatio = vb.width() / vb.height()
                            viewHeight = minOf(400, maxHeightPx)  // デフォルト高さを基準
                            viewWidth = (viewHeight * aspectRatio).toInt()
                            
                            // ViewBoxを描画座標系として設定
                            svgInstance.setDocumentViewBox(vb.left, vb.top, vb.width(), vb.height())
                            svgInstance.setDocumentWidth(viewWidth.toFloat())
                            svgInstance.setDocumentHeight(viewHeight.toFloat())
                            
                            SvgLogger.d("SVG ViewBox設定: ${viewWidth}x${viewHeight}, viewBox=[${vb.left},${vb.top},${vb.width()},${vb.height()}]")
                        }
                        else -> {
                            // width/height・viewBox共に未定義の場合
                            viewWidth = 400
                            viewHeight = minOf(300, maxHeightPx)
                            SvgLogger.d("SVGデフォルト寸法使用: ${viewWidth}x${viewHeight}")
                        }
                    }
                } catch (e: Exception) {
                    SvgLogger.w("SVG寸法計算失敗、デフォルト値使用: ${e.message}")
                    viewWidth = 400
                    viewHeight = minOf(300, maxHeightPx)
                }
            }
        }
        
        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            
            if (!parseSuccess) {
                // パース失敗時のエラー表示
                drawErrorMessage(canvas, "SVG解析に失敗しました")
                return
            }
            
            svg?.let { svgInstance ->
                try {
                    canvas.save()
                    
                    // キャンバスサイズに合わせてスケーリング
                    val scaleX = width.toFloat() / viewWidth
                    val scaleY = height.toFloat() / viewHeight
                    val scale = minOf(scaleX, scaleY)
                    
                    if (scale > 0) {
                        // 中央寄せのための平行移動を計算
                        val scaledWidth = viewWidth * scale
                        val scaledHeight = viewHeight * scale
                        val translateX = (width - scaledWidth) / 2f
                        val translateY = (height - scaledHeight) / 2f
                        
                        // 中央寄せとスケーリングを適用
                        canvas.translate(translateX, translateY)
                        canvas.scale(scale, scale)
                        
                        // SVGを描画
                        svgInstance.renderToCanvas(canvas)
                        
                        SvgLogger.v("AndroidSVG描画完了: ${width}x${height}, scale: $scale, translate: ($translateX, $translateY)")
                    }
                    
                    canvas.restore()
                    
                } catch (e: Exception) {
                    SvgLogger.e("AndroidSVG描画エラー: ${e.message}", e)
                    drawErrorMessage(canvas, "SVG描画エラー")
                }
            }
        }
        
        private fun drawErrorMessage(canvas: Canvas, message: String) {
            // エラーメッセージを描画（フォールバック）
            val paint = android.graphics.Paint().apply {
                color = android.graphics.Color.RED
                textSize = 24f
                isAntiAlias = true
            }
            canvas.drawText(message, 20f, height / 2f, paint)
        }
        
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val availableWidth = MeasureSpec.getSize(widthMeasureSpec)
            val availableHeight = MeasureSpec.getSize(heightMeasureSpec)
            
            // アスペクト比を保持しつつ、制約内でサイズを決定
            val targetHeight = minOf(viewHeight, availableHeight, maxHeightPx)
            val targetWidth = minOf(viewWidth, availableWidth)
            
            setMeasuredDimension(targetWidth, targetHeight)
            SvgLogger.v("AndroidSVG測定完了: ${targetWidth}x${targetHeight}")
        }
    }
}

/**
 * SVGエラー表示コンポーネント（診断機能強化版）
 */
@Composable
private fun SvgErrorDisplay(
    errorMessage: String,
    analysisResult: SvgAnalysisResult? = null,
    modifier: Modifier = Modifier
) {
    // エラー表示時にログバッファを出力
    LaunchedEffect(errorMessage) {
        SvgLogger.dumpLogBuffer()
    }
    
    Card(
        modifier = modifier.padding(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = "🚨 SVG表示エラー",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onErrorContainer
            )
            
            Spacer(modifier = Modifier.height(8.dp))
            
            Text(
                text = errorMessage,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer
            )
            
            // ログバッファサマリーを表示
            Spacer(modifier = Modifier.height(12.dp))
            
            Text(
                text = "📊 診断情報",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onErrorContainer
            )
            
            Spacer(modifier = Modifier.height(4.dp))
            
            Text(
                text = SvgLogger.getLogBufferSummary(),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.9f)
            )
            
            // SVG分析結果があれば詳細診断情報を表示
            if (analysisResult is SvgAnalysisResult.Valid) {
                Spacer(modifier = Modifier.height(12.dp))
                
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.1f)
                    )
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp)
                    ) {
                        Text(
                            text = "📋 SVG詳細分析",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.8f)
                        )
                        
                        Spacer(modifier = Modifier.height(4.dp))
                        
                        Text(
                            text = buildString {
                                append("• 要素数: ${analysisResult.elementStats.totalElements}\n")
                                append("• 寸法: ${analysisResult.width?.toInt() ?: "未定義"} × ${analysisResult.height?.toInt() ?: "未定義"}\n")
                                append("• 複雑さ: ${analysisResult.complexity.displayName}\n")
                                append("• 名前空間: ${if (analysisResult.hasNamespace) "設定済み" else "未設定"}\n")
                                append("• ファイルサイズ: ${analysisResult.fileSize} bytes\n")
                                if (analysisResult.title != null) {
                                    append("• タイトル: ${analysisResult.title}\n")
                                }
                                append("• 形状要素: ${analysisResult.elementStats.shapeElements}個\n")
                                append("• テキスト要素: ${analysisResult.elementStats.textCount}個\n")
                                append("• グループ要素: ${analysisResult.elementStats.groupCount}個")
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.8f)
                        )
                    }
                }
            } else if (analysisResult is SvgAnalysisResult.Invalid) {
                Spacer(modifier = Modifier.height(8.dp))
                
                Text(
                    text = "❌ 解析エラー: ${analysisResult.reason}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.8f)
                )
            }
            
            // トラブルシューティングヒント
            Spacer(modifier = Modifier.height(12.dp))
            
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.05f)
                )
            ) {
                Column(
                    modifier = Modifier.padding(12.dp)
                ) {
                    Text(
                        text = "💡 対処方法",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.8f)
                    )
                    
                    Spacer(modifier = Modifier.height(4.dp))
                    
                    Text(
                        text = buildString {
                            append("• ハイブリッドシステムが自動的にフォールバック\n")
                            append("• WebView失敗時はAndroidSVGが代替表示\n")
                            append("• 複雑なSVGは簡素化を推奨\n")
                            append("• logcatで詳細な診断ログを確認可能")
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.7f)
                    )
                }
            }
        }
    }
}

/**
 * SVG用のHTMLテンプレートを生成（高互換性版）
 * アニメーション、グラデーション、フィルターなどの高度な機能に対応
 */
private fun generateSvgHtml(
    svgContent: String,
    analysisResult: SvgAnalysisResult,
    maxHeight: Int
): String {
    SvgLogger.d("SVGコンテンツ処理開始: 高互換性モード")

    // WebViewで安全に表示するための最小限サニタイズ
    val sanitizedSvg = sanitizeSvgForWebView(svgContent)

    SvgLogger.d("SVGサニタイズ完了: scriptタグ除去、イベントハンドラー除去")
    
    SvgLogger.d("SVG処理: 機能分析をスキップし、シンプルな表示に特化")
    
    // SVG名前空間と高度な属性を追加
    val enhancedSvg = if (!sanitizedSvg.contains("xmlns")) {
        SvgLogger.d("SVG名前空間とXLink名前空間を追加")
        sanitizedSvg.replace(
            "<svg", 
            "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\""
        )
    } else {
        if (!sanitizedSvg.contains("xmlns:xlink")) {
            sanitizedSvg.replace("xmlns=\"http://www.w3.org/2000/svg\"", 
                               "xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\"")
        } else {
            sanitizedSvg
        }
    }
    
    SvgLogger.d("SVGシンプル表示: 寸法調整をスキップ")
    
    // 動的CSS（maxHeightをパラメータで統一）
    val simpleCSS = """
        body {
            margin: 0;
            padding: 8px;
            background: transparent;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
        }
        
        svg {
            max-width: 100%;
            max-height: ${maxHeight}px;
            width: auto;
            height: auto;
            display: block;
        }
    """
    
    // シンプルなHTMLテンプレート（SVG表示に特化）
    val html = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>SVG Preview</title>
        <style>$simpleCSS</style>
    </head>
    <body>
        $enhancedSvg
    </body>
    </html>
    """.trimIndent()
    
    SvgLogger.d("シンプルHTMLテンプレート生成完了: length=${html.length}")
    
    return html
}

/**
 * WebView向けの安全なSVGサニタイズ
 * - script/foreignObject削除
 * - on* イベント属性削除
 * - 外部参照(href/url)を遮断
 */
private fun sanitizeSvgForWebView(svgContent: String): String {
    var sanitized = svgContent
        .replace(Regex("(?is)<script[^>]*>.*?</script>"), "")
        .replace(Regex("(?is)<foreignObject[^>]*>.*?</foreignObject>"), "")

    // イベントハンドラを削除
    sanitized = sanitized
        .replace(Regex("(?i)\\son\\w+\\s*=\\s*\"[^\"]*\""), "")
        .replace(Regex("(?i)\\son\\w+\\s*=\\s*'[^']*'"), "")
        .replace(Regex("(?i)\\son\\w+\\s*=\\s*[^\\s>]+"), "")

    // javascript: など危険なスキームを除去
    sanitized = sanitized.replace(Regex("(?i)javascript:"), "")

    // 外部参照を遮断（#id 参照のみ許可）
    val hrefRegex = Regex("(?i)\\b(xlink:href|href)\\s*=\\s*(['\"])(.*?)\\2")
    sanitized = hrefRegex.replace(sanitized) { match ->
        val attr = match.groupValues[1]
        val value = match.groupValues[3].trim()
        if (value.startsWith("#")) "$attr=\"$value\"" else ""
    }

    // url() で外部参照が使われるケースを遮断
    val urlRegex = Regex("(?i)url\\(([^)]+)\\)")
    sanitized = urlRegex.replace(sanitized) { match ->
        val raw = match.groupValues[1].trim().trim('"', '\'')
        if (raw.startsWith("#")) "url($raw)" else "none"
    }

    return sanitized
}

/**
 * SVGプレビューの設定オプション
 */
data class SvgPreviewOptions(
    val maxHeight: Int = 400,
    val enableZoom: Boolean = true,
    val showBorder: Boolean = true,
    val backgroundColor: String = "transparent",
    val centerContent: Boolean = true
)
