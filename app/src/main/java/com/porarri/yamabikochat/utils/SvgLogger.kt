package com.porarri.yamabikochat.utils

import android.util.Log
import com.porarri.yamabikochat.BuildConfig

/**
 * Release版対応のSVG専用ログシステム
 * 
 * Debug版: 通常のAndroid Logを使用
 * Release版: 内部バッファにログを蓄積し、エラー時に一括出力
 */
object SvgLogger {
    
    private const val TAG = "SvgPreview"
    private const val MAX_LOG_ENTRIES = 100
    private val isDebug = BuildConfig.DEBUG
    
    private val logBuffer = mutableListOf<LogEntry>()
    
    data class LogEntry(
        val timestamp: Long,
        val level: LogLevel,
        val message: String,
        val throwable: Throwable? = null
    )
    
    enum class LogLevel(val symbol: String) {
        VERBOSE("📝"),
        DEBUG("🔍"), 
        INFO("ℹ️"),
        WARN("⚠️"),
        ERROR("❌")
    }
    
    /**
     * デバッグログ出力
     */
    fun d(message: String) {
        logInternal(LogLevel.DEBUG, message)
    }
    
    /**
     * 情報ログ出力
     */
    fun i(message: String) {
        logInternal(LogLevel.INFO, message)
    }
    
    /**
     * 警告ログ出力
     */
    fun w(message: String) {
        logInternal(LogLevel.WARN, message)
    }
    
    /**
     * エラーログ出力
     */
    fun e(message: String, throwable: Throwable? = null) {
        logInternal(LogLevel.ERROR, message, throwable)
    }
    
    /**
     * 詳細ログ出力
     */
    fun v(message: String) {
        logInternal(LogLevel.VERBOSE, message)
    }
    
    /**
     * 内部ログ処理
     */
    private fun logInternal(level: LogLevel, message: String, throwable: Throwable? = null) {
        val formattedMessage = "${level.symbol} $message"
        
        // Debug版: 通常のAndroid Logに出力
        if (isDebug && Log.isLoggable(TAG, Log.DEBUG)) {
            when (level) {
                LogLevel.VERBOSE -> Log.v(TAG, formattedMessage, throwable)
                LogLevel.DEBUG -> Log.d(TAG, formattedMessage, throwable)
                LogLevel.INFO -> Log.i(TAG, formattedMessage, throwable)
                LogLevel.WARN -> Log.w(TAG, formattedMessage, throwable)
                LogLevel.ERROR -> Log.e(TAG, formattedMessage, throwable)
            }
        }
        
        // Release版: 内部バッファに蓄積
        synchronized(logBuffer) {
            logBuffer.add(LogEntry(System.currentTimeMillis(), level, message, throwable))
            
            // バッファサイズ制限
            if (logBuffer.size > MAX_LOG_ENTRIES) {
                logBuffer.removeAt(0)
            }
            
            // エラー発生時は即座にバッファ内容をLogcatに出力
            if (level == LogLevel.ERROR && isDebug) {
                dumpLogBuffer()
            }
        }
    }
    
    /**
     * 蓄積されたログをすべて出力（エラー時の診断用）
     */
    fun dumpLogBuffer() {
        synchronized(logBuffer) {
            if (logBuffer.isEmpty()) return
            if (isDebug) {
                Log.i(TAG, "🔍 ====== SVG診断ログダンプ開始 ======")
                logBuffer.forEach { entry ->
                    val timestamp = android.text.format.DateUtils.formatDateTime(
                        null, entry.timestamp,
                        android.text.format.DateUtils.FORMAT_SHOW_TIME or
                            android.text.format.DateUtils.FORMAT_SHOW_DATE
                    )

                    val logMessage = "${entry.level.symbol} [$timestamp] ${entry.message}"

                    when (entry.level) {
                        LogLevel.VERBOSE -> Log.v(TAG, logMessage, entry.throwable)
                        LogLevel.DEBUG -> Log.d(TAG, logMessage, entry.throwable)
                        LogLevel.INFO -> Log.i(TAG, logMessage, entry.throwable)
                        LogLevel.WARN -> Log.w(TAG, logMessage, entry.throwable)
                        LogLevel.ERROR -> Log.e(TAG, logMessage, entry.throwable)
                    }
                }
                Log.i(TAG, "🔍 ====== SVG診断ログダンプ終了 ======")
            }
        }
    }
    
    /**
     * ログバッファをクリア
     */
    fun clearLogBuffer() {
        synchronized(logBuffer) {
            logBuffer.clear()
            Log.d(TAG, "🗑️ SVGログバッファをクリア")
        }
    }
    
    /**
     * 現在のログバッファの状態を取得
     */
    fun getLogBufferSummary(): String {
        synchronized(logBuffer) {
            val errorCount = logBuffer.count { it.level == LogLevel.ERROR }
            val warnCount = logBuffer.count { it.level == LogLevel.WARN }
            val totalCount = logBuffer.size
            
            return "ログバッファ: 合計${totalCount}件 (エラー${errorCount}件, 警告${warnCount}件)"
        }
    }
    
    /**
     * SVG表示プロセスの開始を記録
     */
    fun logSvgProcessStart(contentLength: Int) {
        i("SVG表示プロセス開始: content length=$contentLength")
    }
    
    /**
     * SVG表示プロセスの成功を記録
     */
    fun logSvgProcessSuccess(method: String) {
        i("SVG表示成功: method=$method")
    }
    
    /**
     * SVG表示プロセスの失敗を記録
     */
    fun logSvgProcessError(method: String, error: String, throwable: Throwable? = null) {
        e("SVG表示失敗: method=$method, error=$error", throwable)
    }
    
    /**
     * フォールバック発生を記録
     */
    fun logFallbackTriggered(fromMethod: String, toMethod: String, reason: String) {
        w("フォールバック発生: $fromMethod -> $toMethod, reason=$reason")
    }
    
    /**
     * SVGコンテンツの詳細分析を記録
     */
    fun logSvgContentAnalysis(svgContent: String) {
        val analysis = analyzeSvgContent(svgContent)
        i("SVG詳細分析: $analysis")
    }
    
    /**
     * パフォーマンス測定開始
     */
    private val performanceTimers = mutableMapOf<String, Long>()
    
    fun startPerformanceTimer(timerName: String) {
        performanceTimers[timerName] = System.currentTimeMillis()
        d("パフォーマンス測定開始: $timerName")
    }
    
    fun endPerformanceTimer(timerName: String) {
        val startTime = performanceTimers.remove(timerName)
        if (startTime != null) {
            val elapsed = System.currentTimeMillis() - startTime
            i("パフォーマンス測定完了: $timerName took ${elapsed}ms")
        } else {
            w("パフォーマンスタイマーが見つかりません: $timerName")
        }
    }
    
    /**
     * エラー分類と詳細診断
     */
    fun logDetailedError(method: String, error: String, svgContent: String? = null, throwable: Throwable? = null) {
        val errorType = classifyError(error, throwable)
        val diagnosis = generateDiagnosis(errorType, svgContent, throwable)
        
        e("[$method] $errorType: $error", throwable)
        i("診断結果: $diagnosis")
        
        // SVGコンテンツのサンプルを保存（エラー時のみ）
        svgContent?.let { content ->
            logSvgSample(content, "error_${System.currentTimeMillis()}")
        }
    }
    
    /**
     * SVGコンテンツの簡易分析
     */
    private fun analyzeSvgContent(svgContent: String): String {
        val length = svgContent.length
        val hasNamespace = svgContent.contains("xmlns")
        val hasViewBox = svgContent.contains("viewBox")
        val elementCount = "<\\w+".toRegex().findAll(svgContent).count()
        val hasPath = svgContent.contains("<path")
        val hasCircle = svgContent.contains("<circle")
        val hasRect = svgContent.contains("<rect")
        val hasText = svgContent.contains("<text")
        val hasAnimation = svgContent.contains("animate")
        val hasScript = svgContent.contains("<script")
        
        return "length=${length}b, namespace=$hasNamespace, viewBox=$hasViewBox, " +
                "elements=$elementCount, path=$hasPath, circle=$hasCircle, rect=$hasRect, " +
                "text=$hasText, animation=$hasAnimation, script=$hasScript"
    }
    
    /**
     * エラーを分類
     */
    private fun classifyError(error: String, throwable: Throwable?): String {
        return when {
            error.contains("パース", ignoreCase = true) || 
            throwable is com.caverock.androidsvg.SVGParseException -> "SVG_PARSE_ERROR"
            
            error.contains("WebView", ignoreCase = true) -> "WEBVIEW_ERROR"
            
            error.contains("描画", ignoreCase = true) || 
            error.contains("Canvas", ignoreCase = true) -> "RENDER_ERROR"
            
            error.contains("サイズ", ignoreCase = true) || 
            error.contains("寸法", ignoreCase = true) -> "SIZE_ERROR"
            
            error.contains("セキュリティ", ignoreCase = true) -> "SECURITY_ERROR"
            
            error.contains("タイムアウト", ignoreCase = true) -> "TIMEOUT_ERROR"
            
            throwable is IllegalArgumentException -> "ARGUMENT_ERROR"
            throwable is OutOfMemoryError -> "MEMORY_ERROR"
            
            else -> "UNKNOWN_ERROR"
        }
    }
    
    /**
     * エラーに対する診断結果を生成
     */
    private fun generateDiagnosis(errorType: String, svgContent: String?, throwable: Throwable?): String {
        return when (errorType) {
            "SVG_PARSE_ERROR" -> "SVG形式に問題があります。名前空間やタグの閉じ忘れを確認してください。"
            "WEBVIEW_ERROR" -> "WebViewでの表示に失敗しました。AndroidSVGフォールバックを確認してください。"
            "RENDER_ERROR" -> "描画処理でエラーが発生しました。SVGの複雑さやサイズを確認してください。"
            "SIZE_ERROR" -> "SVGサイズの計算に問題があります。width/height属性やviewBoxを確認してください。"
            "SECURITY_ERROR" -> "セキュリティ制限により表示できません。SVGのscriptタグや外部参照を確認してください。"
            "TIMEOUT_ERROR" -> "表示処理がタイムアウトしました。SVGファイルサイズや複雑さを確認してください。"
            "ARGUMENT_ERROR" -> "無効な引数が渡されました。SVGコンテンツの内容を確認してください。"
            "MEMORY_ERROR" -> "メモリ不足です。SVGファイルサイズを小さくしてください。"
            else -> "不明なエラーです。ログ詳細とSVGコンテンツを確認してください。"
        }
    }
    
    /**
     * SVGコンテンツのサンプルを記録（デバッグ用）
     */
    private fun logSvgSample(svgContent: String, identifier: String) {
        if (!isDebug) return
        val preview = if (svgContent.length > 200) {
            "${svgContent.take(200)}..."
        } else {
            svgContent
        }
        d("SVGサンプル[$identifier]: $preview")
    }
    
    /**
     * 包括的な診断レポートを生成
     */
    fun generateDiagnosticReport(): String {
        synchronized(logBuffer) {
            val errors = logBuffer.filter { it.level == LogLevel.ERROR }
            val warnings = logBuffer.filter { it.level == LogLevel.WARN }
            val infos = logBuffer.filter { it.level == LogLevel.INFO }
            
            val errorTypes = errors.groupBy { entry ->
                entry.message.substringBefore("]").substringAfter("[")
            }.mapValues { it.value.size }
            
            return buildString {
                appendLine("=== SVG診断レポート ===")
                appendLine("総ログ数: ${logBuffer.size}")
                appendLine("エラー数: ${errors.size}")
                appendLine("警告数: ${warnings.size}")
                appendLine("情報数: ${infos.size}")
                appendLine()
                
                if (errorTypes.isNotEmpty()) {
                    appendLine("エラー分類:")
                    errorTypes.forEach { (type, count) ->
                        appendLine("  - $type: ${count}件")
                    }
                    appendLine()
                }
                
                appendLine("最新エラー:")
                errors.takeLast(3).forEach { entry ->
                    appendLine("  - [${entry.level.symbol}] ${entry.message}")
                }
                
                if (warnings.isNotEmpty()) {
                    appendLine()
                    appendLine("最新警告:")
                    warnings.takeLast(2).forEach { entry ->
                        appendLine("  - [${entry.level.symbol}] ${entry.message}")
                    }
                }
                
                appendLine("\n実行時間測定:")
                performanceTimers.forEach { (name, startTime) ->
                    val elapsed = System.currentTimeMillis() - startTime
                    appendLine("  - $name: ${elapsed}ms (実行中)")
                }
            }
        }
    }
}
