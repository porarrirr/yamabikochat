package com.porarri.yamabikochat.utils

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.activity.compose.rememberLauncherForActivityResult
import com.porarri.yamabikochat.data.models.CodeBlock
import com.porarri.yamabikochat.data.models.CodeBlockGroup
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException

/**
 * コードブロックのファイルエクスポート機能を提供するユーティリティクラス
 */
object FileExportUtils {
    
    /**
     * MIMEタイプのマッピング
     */
    private val MIME_TYPES = mapOf(
        "py" to "text/x-python",
        "js" to "text/javascript", 
        "ts" to "text/typescript",
        "html" to "text/html",
        "css" to "text/css",
        "kt" to "text/x-kotlin",
        "java" to "text/x-java-source",
        "json" to "application/json",
        "xml" to "text/xml",
        "svg" to "image/svg+xml",
        "md" to "text/markdown",
        "sql" to "text/x-sql",
        "sh" to "text/x-shellscript",
        "yml" to "text/yaml",
        "yaml" to "text/yaml",
        "c" to "text/x-c",
        "cpp" to "text/x-c++",
        "php" to "text/x-php",
        "rb" to "text/x-ruby",
        "go" to "text/x-go",
        "rs" to "text/x-rust",
        "swift" to "text/x-swift",
        "r" to "text/x-r"
    )

    private const val EXPORT_DIR_NAME = "exports"
    
    /**
     * ファイルエクスポート結果
     */
    sealed class ExportResult {
        object Success : ExportResult()
        data class Error(val message: String) : ExportResult()
        object Cancelled : ExportResult()
    }
    
    /**
     * ファイル作成インテントを開始
     * 
     * @param context アプリケーションコンテキスト
     * @param codeBlock エクスポートするコードブロック
     * @param launcher ActivityResultLauncher
     */
    fun createFileIntent(
        context: Context,
        codeBlock: CodeBlock,
        launcher: ActivityResultLauncher<Intent>
    ) {
        try {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = getMimeType(codeBlock.fileExtension)
                putExtra(Intent.EXTRA_TITLE, codeBlock.filename)
            }
            
            launcher.launch(intent)
        } catch (e: Exception) {
            throw IOException("ファイル作成インテントの開始に失敗しました: ${e.message}")
        }
    }
    
    /**
     * 指定されたURIにコードブロックを保存
     * 
     * @param context アプリケーションコンテキスト
     * @param uri 保存先URI
     * @param codeBlock 保存するコードブロック
     * @return エクスポート結果
     */
    suspend fun saveCodeToUri(
        context: Context,
        uri: Uri,
        codeBlock: CodeBlock
    ): ExportResult = withContext(Dispatchers.IO) {
        try {
            context.contentResolver.openOutputStream(uri)?.use { outputStream ->
                outputStream.write(codeBlock.content.toByteArray(Charsets.UTF_8))
                outputStream.flush()
            } ?: return@withContext ExportResult.Error("ファイルストリームを開けませんでした")
            
            ExportResult.Success
        } catch (e: IOException) {
            ExportResult.Error("ファイル書き込みエラー: ${e.message}")
        } catch (e: SecurityException) {
            ExportResult.Error("ファイルアクセス権限エラー: ${e.message}")
        } catch (e: Exception) {
            ExportResult.Error("予期しないエラー: ${e.message}")
        }
    }
    
    /**
     * 内部ストレージに一時ファイルとして保存
     * 
     * @param context アプリケーションコンテキスト
     * @param codeBlock 保存するコードブロック
     * @return 保存されたファイルのURI
     */
    suspend fun saveToInternalStorage(
        context: Context,
        codeBlock: CodeBlock
    ): Uri? = withContext(Dispatchers.IO) {
        try {
            val file = createExportFile(context, codeBlock.filename)
            file.writeText(codeBlock.content, Charsets.UTF_8)
            
            // FileProviderを使用してURIを取得
            androidx.core.content.FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file
            )
        } catch (e: Exception) {
            null
        }
    }
    
    /**
     * ファイル共有インテントを作成
     * 
     * @param context アプリケーションコンテキスト
     * @param codeBlock 共有するコードブロック
     * @return 共有インテント
     */
    suspend fun createShareIntent(
        context: Context,
        codeBlock: CodeBlock
    ): Intent? {
        val uri = saveToInternalStorage(context, codeBlock) ?: return null
        
        return Intent(Intent.ACTION_SEND).apply {
            type = getMimeType(codeBlock.fileExtension)
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, "コードファイル: ${codeBlock.filename}")
            putExtra(Intent.EXTRA_TEXT, "やまびこチャットで生成されたコード")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }
    
    /**
     * 複数のコードブロックを一括エクスポート
     * 
     * @param context アプリケーションコンテキスト
     * @param codeBlocks エクスポートするコードブロックのリスト
     * @param baseFilename ベースファイル名
     * @return エクスポート結果のマップ
     */
    suspend fun exportMultipleFiles(
        context: Context,
        codeBlocks: List<CodeBlock>,
        baseFilename: String = "codes"
    ): Map<CodeBlock, ExportResult> = withContext(Dispatchers.IO) {
        val results = mutableMapOf<CodeBlock, ExportResult>()
        
        codeBlocks.forEachIndexed { index, codeBlock ->
            try {
                val filename = if (codeBlocks.size == 1) {
                    codeBlock.filename
                } else {
                    "${baseFilename}_${index + 1}_${codeBlock.displayLanguage}.${codeBlock.fileExtension}"
                }

                val sanitizedName = sanitizeFilename(filename)
                val modifiedCodeBlock = codeBlock.copy(filename = sanitizedName)
                val uri = saveToInternalStorage(context, modifiedCodeBlock)

                if (uri != null) {
                    results[codeBlock] = ExportResult.Success
                } else {
                    results[codeBlock] = ExportResult.Error("内部ストレージへの保存に失敗")
                }
            } catch (e: Exception) {
                results[codeBlock] = ExportResult.Error("エクスポートエラー: ${e.message}")
            }
        }
        
        results
    }
    
    /**
     * ファイル拡張子からMIMEタイプを取得
     */
    private fun getMimeType(extension: String): String {
        return MIME_TYPES[extension.lowercase()] ?: "text/plain"
    }
    
    /**
     * ファイルサイズの検証
     */
    fun validateFileSize(content: String, maxSizeBytes: Long = 10 * 1024 * 1024): Boolean {
        return content.toByteArray(Charsets.UTF_8).size <= maxSizeBytes
    }
    
    /**
     * ファイル名のサニタイズ
     */
    fun sanitizeFilename(filename: String): String {
        return filename
            .replace(Regex("[^a-zA-Z0-9._-]"), "_")
            .take(100) // 長すぎるファイル名を制限
            .ifEmpty { "code_${System.currentTimeMillis()}" }
    }

    private fun ensureExportDirectory(context: Context): File {
        val dir = File(context.filesDir, EXPORT_DIR_NAME)
        if (!dir.exists() && !dir.mkdirs()) {
            throw IOException("エクスポート用ディレクトリの作成に失敗しました")
        }
        return dir
    }

    private fun createExportFile(context: Context, rawFilename: String): File {
        val dir = ensureExportDirectory(context)
        val sanitizedName = sanitizeFilename(rawFilename)
        return File(dir, sanitizedName)
    }
    
    /**
     * CodeBlockGroupから統合HTMLファイルを生成
     * 
     * @param group 統合対象のCodeBlockGroup
     * @return 統合されたHTMLコンテンツ
     */
    fun generateIntegratedHtml(group: CodeBlockGroup): String {
        if (!group.canIntegrate) {
            throw IllegalArgumentException("指定されたグループは統合できません")
        }
        
        val htmlBlock = group.htmlBlock ?: throw IllegalArgumentException("HTMLブロックが見つかりません")
        var htmlContent = htmlBlock.content.trim()
        
        // HTML構造の検証と修正
        if (!htmlContent.contains("<!DOCTYPE", ignoreCase = true)) {
            htmlContent = "<!DOCTYPE html>\n$htmlContent"
        }
        
        // CSSの統合
        if (group.cssBlocks.isNotEmpty()) {
            val combinedCss = group.cssBlocks.joinToString("\n\n") { "/* ${it.filename} */\n${it.content}" }
            val styleTag = "\n<style>\n$combinedCss\n</style>"
            
            // headタグ内にstyleタグを挿入
            htmlContent = if (htmlContent.contains("</head>", ignoreCase = true)) {
                htmlContent.replace("</head>", "$styleTag\n</head>", ignoreCase = true)
            } else if (htmlContent.contains("<head>", ignoreCase = true)) {
                htmlContent.replace("<head>", "<head>$styleTag", ignoreCase = true)
            } else {
                // headタグがない場合は作成
                htmlContent.replace("<html>", "<html>\n<head>$styleTag\n</head>", ignoreCase = true)
            }
        }
        
        // JavaScriptの統合
        if (group.jsBlocks.isNotEmpty()) {
            val combinedJs = group.jsBlocks.joinToString("\n\n") { "/* ${it.filename} */\n${it.content}" }
            val scriptTag = "\n<script>\n$combinedJs\n</script>"
            
            // bodyタグの直前にscriptタグを挿入
            htmlContent = when {
                htmlContent.contains("</body>", ignoreCase = true) -> 
                    htmlContent.replace("</body>", "$scriptTag\n</body>", ignoreCase = true)
                htmlContent.contains("</html>", ignoreCase = true) -> 
                    htmlContent.replace("</html>", "$scriptTag\n</html>", ignoreCase = true)
                else -> {
                    // bodyタグがない場合は末尾に追加
                    htmlContent + scriptTag
                }
            }
        }
        
        // HTML構造の最終チェックと修正
        if (!htmlContent.contains("</html>", ignoreCase = true) && !htmlContent.endsWith("</html>")) {
            htmlContent += "\n</html>"
        }
        
        return htmlContent
    }
    
    /**
     * 統合HTMLファイルをエクスポート
     * 
     * @param context アプリケーションコンテキスト
     * @param uri 保存先URI
     * @param group エクスポートするCodeBlockGroup
     * @return エクスポート結果
     */
    suspend fun saveIntegratedHtmlToUri(
        context: Context,
        uri: Uri,
        group: CodeBlockGroup
    ): ExportResult = withContext(Dispatchers.IO) {
        try {
            val integratedHtml = generateIntegratedHtml(group)
            
            context.contentResolver.openOutputStream(uri)?.use { outputStream ->
                outputStream.write(integratedHtml.toByteArray(Charsets.UTF_8))
                outputStream.flush()
            } ?: return@withContext ExportResult.Error("ファイルストリームを開けませんでした")
            
            ExportResult.Success
        } catch (e: IllegalArgumentException) {
            ExportResult.Error("統合エラー: ${e.message}")
        } catch (e: IOException) {
            ExportResult.Error("ファイル書き込みエラー: ${e.message}")
        } catch (e: SecurityException) {
            ExportResult.Error("ファイルアクセス権限エラー: ${e.message}")
        } catch (e: Exception) {
            ExportResult.Error("予期しないエラー: ${e.message}")
        }
    }
    
    /**
     * 統合HTMLファイル用のファイル作成インテントを開始
     * 
     * @param context アプリケーションコンテキスト
     * @param group エクスポートするCodeBlockGroup
     * @param launcher ActivityResultLauncher
     */
    fun createIntegratedHtmlIntent(
        context: Context,
        group: CodeBlockGroup,
        launcher: ActivityResultLauncher<Intent>
    ) {
        try {
            val filename = group.generateIntegratedFilename()
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "text/html"
                putExtra(Intent.EXTRA_TITLE, filename)
            }
            
            launcher.launch(intent)
        } catch (e: Exception) {
            throw IOException("統合HTMLファイル作成インテントの開始に失敗しました: ${e.message}")
        }
    }
    
    /**
     * 統合HTMLファイルの共有インテントを作成
     * 
     * @param context アプリケーションコンテキスト
     * @param group 共有するCodeBlockGroup
     * @return 共有インテント
     */
    suspend fun createIntegratedHtmlShareIntent(
        context: Context,
        group: CodeBlockGroup
    ): Intent? {
        try {
            val integratedHtml = generateIntegratedHtml(group)
            val filename = group.generateIntegratedFilename()
            
            // 一時的なCodeBlockを作成してファイル保存
            val tempCodeBlock = CodeBlock(
                language = "html",
                content = integratedHtml,
                startIndex = 0,
                endIndex = integratedHtml.length,
                extractionMethod = "integrated",
                filename = filename
            )
            
            val uri = saveToInternalStorage(context, tempCodeBlock) ?: return null
            
            return Intent(Intent.ACTION_SEND).apply {
                type = "text/html"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, "統合HTMLファイル: $filename")
                putExtra(Intent.EXTRA_TEXT, "やまびこチャットで統合されたWebファイル\n${group.getStats().getDescription()}")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        } catch (e: Exception) {
            return null
        }
    }
    
    /**
     * 統合HTMLファイルのサイズ検証
     * 
     * @param group 検証対象のCodeBlockGroup
     * @param maxSizeBytes 最大サイズ（バイト）
     * @return サイズが有効な場合はtrue
     */
    fun validateIntegratedHtmlSize(group: CodeBlockGroup, maxSizeBytes: Long = 10 * 1024 * 1024): Boolean {
        return try {
            val integratedHtml = generateIntegratedHtml(group)
            integratedHtml.toByteArray(Charsets.UTF_8).size <= maxSizeBytes
        } catch (e: Exception) {
            false
        }
    }
}

/**
 * Composable関数でファイルエクスポート機能を使用するためのヘルパー
 */
@Composable
fun rememberFileExportLauncher(
    onResult: (Uri?, CodeBlock?) -> Unit
): FileExportLauncher {
    val context = LocalContext.current
    var pendingCodeBlock: CodeBlock? = null
    
    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            result.data?.data?.let { uri ->
                onResult(uri, pendingCodeBlock)
            }
        } else {
            onResult(null, pendingCodeBlock)
        }
        pendingCodeBlock = null
    }
    
    return remember {
        FileExportLauncher(
            context = context,
            launcher = launcher,
            setPendingCodeBlock = { pendingCodeBlock = it }
        )
    }
}

/**
 * ファイルエクスポート機能のラッパークラス
 */
class FileExportLauncher(
    private val context: Context,
    private val launcher: ActivityResultLauncher<Intent>,
    private val setPendingCodeBlock: (CodeBlock) -> Unit
) {
    fun exportFile(codeBlock: CodeBlock) {
        setPendingCodeBlock(codeBlock)
        FileExportUtils.createFileIntent(context, codeBlock, launcher)
    }
}
