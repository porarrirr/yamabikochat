package com.porarri.yamabikochat.utils

import com.porarri.yamabikochat.data.models.CodeBlock
import com.porarri.yamabikochat.data.models.CodeBlockGroup
import com.porarri.yamabikochat.data.models.GroupType
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * LLM出力からコードブロックを検知・抽出するユーティリティクラス
 */
object CodeExtractorUtils {
    
    /**
     * 言語別ファイル拡張子マッピング
     */
    private val LANGUAGE_EXTENSIONS = mapOf(
        "python" to "py",
        "py" to "py",
        "javascript" to "js",
        "js" to "js",
        "typescript" to "ts",
        "ts" to "ts",
        "html" to "html",
        "css" to "css",
        "kotlin" to "kt",
        "kt" to "kt",
        "java" to "java",
        "json" to "json",
        "xml" to "xml",
        "svg" to "svg",
        "markdown" to "md",
        "md" to "md",
        "sql" to "sql",
        "shell" to "sh",
        "bash" to "sh",
        "sh" to "sh",
        "yaml" to "yml",
        "yml" to "yml",
        "c" to "c",
        "cpp" to "cpp",
        "cxx" to "cpp",
        "c++" to "cpp",
        "php" to "php",
        "ruby" to "rb",
        "go" to "go",
        "rust" to "rs",
        "swift" to "swift",
        "r" to "r"
    )
    
    /**
     * テキストからコードブロックを検知・抽出する
     * 
     * @param text 検索対象のテキスト
     * @return 検知されたコードブロックのリスト
     */
    fun extractCodeBlocks(text: String): List<CodeBlock> {
        val codeBlocks = mutableListOf<CodeBlock>()
        
        // 1. マークダウンコードブロックを検知
        codeBlocks.addAll(extractMarkdownCodeBlocks(text))
        
        // 2. カスタムタグコードブロックを検知
        codeBlocks.addAll(extractCustomTagCodeBlocks(text))
        
        // 3. インラインSVGコードブロックを検知（<svg>...</svg>）
        codeBlocks.addAll(extractInlineSvgBlocks(text))
        
        // 重複除去と開始位置でソート、SVG特有の後処理
        return codeBlocks
            .distinctBy { "${it.startIndex}-${it.endIndex}-${it.content}" }
            .sortedBy { it.startIndex }
            .map { codeBlock ->
                // SVGの場合、内容を検証して必要に応じて言語を修正
                if (isSvgContent(codeBlock.content) && !codeBlock.language.equals("svg", ignoreCase = true)) {
                    codeBlock.copy(
                        language = "svg",
                        filename = generateFilename("svg", codeBlock.content)
                    )
                } else {
                    codeBlock
                }
            }
    }
    
    /**
     * マークダウン形式のコードブロックを抽出
     * 
     * 例: ```python\nprint("Hello")\n```
     */
    private fun extractMarkdownCodeBlocks(text: String): List<CodeBlock> {
        val codeBlocks = mutableListOf<CodeBlock>()
        val markdownPattern = """```(\w*)\n?([\s\S]*?)\n?```""".toRegex()
        
        markdownPattern.findAll(text).forEach { match ->
            val language = match.groupValues[1].ifEmpty { "text" }
            val content = match.groupValues[2].trim()
            val startIndex = match.range.first
            val endIndex = match.range.last + 1
            
            if (content.isNotBlank()) {
                val filename = generateFilename(language, content)
                codeBlocks.add(
                    CodeBlock(
                        language = language,
                        content = content,
                        startIndex = startIndex,
                        endIndex = endIndex,
                        extractionMethod = "markdown",
                        filename = filename
                    )
                )
            }
        }
        
        return codeBlocks
    }
    
    /**
     * カスタムタグ形式のコードブロックを抽出
     * 
     * 例: <code_start:python>\nprint("Hello")\n<code_end:python>
     */
    private fun extractCustomTagCodeBlocks(text: String): List<CodeBlock> {
        val codeBlocks = mutableListOf<CodeBlock>()
        val customTagPattern = """<code_start:(\w+)>([\s\S]*?)<code_end:\1>""".toRegex()
        
        customTagPattern.findAll(text).forEach { match ->
            val language = match.groupValues[1]
            val content = match.groupValues[2].trim()
            val startIndex = match.range.first
            val endIndex = match.range.last + 1
            
            if (content.isNotBlank()) {
                val filename = generateFilename(language, content)
                codeBlocks.add(
                    CodeBlock(
                        language = language,
                        content = content,
                        startIndex = startIndex,
                        endIndex = endIndex,
                        extractionMethod = "custom_tag",
                        filename = filename
                    )
                )
            }
        }
        
        return codeBlocks
    }
    
    /**
     * コードの内容と言語に基づいてファイル名を生成
     */
    private fun generateFilename(language: String, content: String): String {
        val extension = LANGUAGE_EXTENSIONS[language.lowercase()] ?: "txt"
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
        
        // コードから意味のあるファイル名を抽出しようと試行
        val suggestedName = extractSuggestedFilename(content, language)
        
        return if (suggestedName.isNotEmpty()) {
            "${suggestedName}_$timestamp.$extension"
        } else {
            "code_$timestamp.$extension"
        }
    }
    
    /**
     * コードの内容から推奨ファイル名を抽出
     */
    private fun extractSuggestedFilename(content: String, language: String): String {
        val lines = content.lines().take(10) // 最初の10行のみを検索
        
        return when (language.lowercase()) {
            "python", "py" -> {
                // クラス名や関数名を検索
                lines.find { it.trim().startsWith("class ") }
                    ?.substringAfter("class ")?.substringBefore("(")?.substringBefore(":")?.trim()
                    ?: lines.find { it.trim().startsWith("def ") }
                        ?.substringAfter("def ")?.substringBefore("(")?.trim()
                    ?: ""
            }
            "javascript", "js", "typescript", "ts" -> {
                // 関数名やクラス名を検索
                lines.find { it.trim().startsWith("function ") }
                    ?.substringAfter("function ")?.substringBefore("(")?.trim()
                    ?: lines.find { it.trim().startsWith("class ") }
                        ?.substringAfter("class ")?.substringBefore("{")?.trim()
                    ?: ""
            }
            "html" -> {
                // title タグから名前を抽出
                lines.find { it.contains("<title>") }
                    ?.substringAfter("<title>")?.substringBefore("</title>")?.trim()
                    ?: "page"
            }
            "kotlin", "kt" -> {
                // クラス名や関数名を検索
                lines.find { it.trim().startsWith("class ") }
                    ?.substringAfter("class ")?.substringBefore("(")?.substringBefore(" ")?.trim()
                    ?: lines.find { it.trim().startsWith("fun ") }
                        ?.substringAfter("fun ")?.substringBefore("(")?.trim()
                    ?: ""
            }
            "java" -> {
                // クラス名を検索
                lines.find { it.trim().startsWith("public class ") || it.trim().startsWith("class ") }
                    ?.substringAfter("class ")?.substringBefore("{")?.trim()
                    ?: ""
            }
            "svg" -> {
                // SVGのtitleタグやid属性から名前を抽出
                val titleRegex = """<title[^>]*>(.*?)</title>""".toRegex(RegexOption.IGNORE_CASE)
                val idRegex = """id\s*=\s*["']([^"']+)["']""".toRegex(RegexOption.IGNORE_CASE)
                
                titleRegex.find(content)?.groupValues?.get(1)?.trim()
                    ?: idRegex.find(content)?.groupValues?.get(1)?.trim()
                    ?: "graphic"
            }
            else -> ""
        }.let { name ->
            // ファイル名として使用できない文字を除去
            name.replace(Regex("[^a-zA-Z0-9_-]"), "").take(20)
        }
    }
    
    /**
     * 指定された言語がサポートされているかチェック
     */
    fun isSupportedLanguage(language: String): Boolean {
        return LANGUAGE_EXTENSIONS.containsKey(language.lowercase())
    }
    
    /**
     * 言語から拡張子を取得
     */
    fun getFileExtension(language: String): String {
        return LANGUAGE_EXTENSIONS[language.lowercase()] ?: "txt"
    }
    
    /**
     * テキストがコードブロックを含んでいるかチェック
     */
    fun containsCodeBlocks(text: String): Boolean {
        return text.contains("```") || text.contains("<code_start:")
    }
    
    /**
     * 統計情報を取得
     */
    fun getCodeBlockStats(codeBlocks: List<CodeBlock>): CodeBlockStats {
        return CodeBlockStats(
            totalBlocks = codeBlocks.size,
            languageCount = codeBlocks.map { it.language }.distinct().size,
            totalLines = codeBlocks.sumOf { it.lineCount },
            totalCharacters = codeBlocks.sumOf { it.size },
            languageDistribution = codeBlocks.groupBy { it.language }.mapValues { it.value.size }
        )
    }
    
    /**
     * インラインSVGブロックを抽出（<svg>...</svg>）
     * マークダウンやカスタムタグ以外の場所にある生のSVGコードを検知
     */
    private fun extractInlineSvgBlocks(text: String): List<CodeBlock> {
        val codeBlocks = mutableListOf<CodeBlock>()
        val svgPattern = """<svg[^>]*>([\s\S]*?)</svg>""".toRegex(RegexOption.IGNORE_CASE)
        
        svgPattern.findAll(text).forEach { match ->
            val fullSvgContent = match.value
            val startIndex = match.range.first
            val endIndex = match.range.last + 1
            
            // マークダウンコードブロック内やカスタムタグ内のSVGは除外
            if (!isWithinCodeBlock(text, startIndex, endIndex)) {
                val filename = generateFilename("svg", fullSvgContent)
                codeBlocks.add(
                    CodeBlock(
                        language = "svg",
                        content = fullSvgContent,
                        startIndex = startIndex,
                        endIndex = endIndex,
                        extractionMethod = "inline_svg",
                        filename = filename
                    )
                )
            }
        }
        
        return codeBlocks
    }
    
    /**
     * 指定されたテキスト範囲がコードブロック内にあるかチェック
     */
    private fun isWithinCodeBlock(text: String, start: Int, end: Int): Boolean {
        val beforeText = text.substring(0, start)
        val afterText = text.substring(end)
        
        // マークダウンコードブロック内かチェック
        val markdownOpenCount = beforeText.split("```").size - 1
        val markdownCloseCount = afterText.split("```").size - 1
        if (markdownOpenCount % 2 == 1) return true
        
        // カスタムタグ内かチェック
        val customTagOpenRegex = """<code_start:\w+>""".toRegex()
        val customTagCloseRegex = """<code_end:\w+>""".toRegex()
        
        val openTags = customTagOpenRegex.findAll(beforeText).count()
        val closeTags = customTagCloseRegex.findAll(beforeText).count()
        
        return openTags > closeTags
    }
    
    /**
     * コンテンツがSVGかどうかを判定
     */
    private fun isSvgContent(content: String): Boolean {
        val trimmedContent = content.trim()
        
        // 基本的なSVGの特徴をチェック
        return trimmedContent.contains("<svg", ignoreCase = true) &&
                trimmedContent.contains("</svg>", ignoreCase = true) &&
                (trimmedContent.contains("xmlns", ignoreCase = true) || 
                 trimmedContent.contains("viewBox", ignoreCase = true) ||
                 trimmedContent.contains("<path", ignoreCase = true) ||
                 trimmedContent.contains("<circle", ignoreCase = true) ||
                 trimmedContent.contains("<rect", ignoreCase = true) ||
                 trimmedContent.contains("<line", ignoreCase = true) ||
                 trimmedContent.contains("<polygon", ignoreCase = true) ||
                 trimmedContent.contains("<polyline", ignoreCase = true))
    }
    
    /**
     * SVG専用のファイル名生成
     */
    private fun generateSvgFilename(content: String): String {
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
        
        // SVGからタイトルやID属性を抽出してファイル名として使用
        val titleRegex = """<title[^>]*>(.*?)</title>""".toRegex(RegexOption.IGNORE_CASE)
        val idRegex = """id\s*=\s*["']([^"']+)["']""".toRegex(RegexOption.IGNORE_CASE)
        
        val suggestedName = titleRegex.find(content)?.groupValues?.get(1)?.trim()
            ?: idRegex.find(content)?.groupValues?.get(1)?.trim()
            ?: "graphic"
        
        val cleanName = suggestedName
            .replace(Regex("[^a-zA-Z0-9_-]"), "_")
            .take(20)
            .ifEmpty { "graphic" }
        
        return "${cleanName}_$timestamp.svg"
    }
    
    /**
     * 抽出されたコードブロックを関連性に基づいてグループ化
     * 
     * @param codeBlocks グループ化するコードブロックのリスト
     * @return グループ化されたコードブロックグループのリスト
     */
    fun groupCodeBlocks(codeBlocks: List<CodeBlock>): List<CodeBlockGroup> {
        if (codeBlocks.isEmpty()) return emptyList()
        
        val groups = mutableListOf<CodeBlockGroup>()
        val processedBlocks = mutableSetOf<CodeBlock>()
        
        // 1. Web関連のバンドルを検知
        val webBundles = detectWebBundles(codeBlocks, processedBlocks)
        groups.addAll(webBundles)
        
        // 2. 残りの単一ブロックを処理
        codeBlocks.forEach { block ->
            if (block !in processedBlocks) {
                groups.add(CodeBlockGroup(
                    blocks = listOf(block),
                    groupType = GroupType.SINGLE
                ))
                processedBlocks.add(block)
            }
        }
        
        return groups.sortedBy { it.blocks.minOfOrNull { block -> block.startIndex } ?: 0 }
    }
    
    /**
     * Web関連のバンドル（HTML + CSS + JS）を検知
     */
    private fun detectWebBundles(
        codeBlocks: List<CodeBlock>,
        processedBlocks: MutableSet<CodeBlock>
    ): List<CodeBlockGroup> {
        val webBundles = mutableListOf<CodeBlockGroup>()
        
        // HTMLブロックを基準にしてバンドルを検出
        val htmlBlocks = codeBlocks.filter { it.language.lowercase() == "html" && it !in processedBlocks }
        
        htmlBlocks.forEach { htmlBlock ->
            val relatedBlocks = mutableListOf<CodeBlock>(htmlBlock)
            
            // HTML周辺のCSS/JSブロックを検索
            codeBlocks.forEach { candidateBlock ->
                if (candidateBlock != htmlBlock && 
                    candidateBlock !in processedBlocks &&
                    isRelatedToHtml(htmlBlock, candidateBlock)) {
                    relatedBlocks.add(candidateBlock)
                }
            }
            
            // 関連ブロックがある場合のみWebバンドルとして扱う
            if (relatedBlocks.size > 1) {
                val bundle = CodeBlockGroup(
                    blocks = relatedBlocks.sortedBy { it.startIndex },
                    groupType = GroupType.WEB_BUNDLE
                )
                webBundles.add(bundle)
                processedBlocks.addAll(relatedBlocks)
            }
        }
        
        return webBundles
    }
    
    /**
     * 指定されたブロックがHTMLブロックと関連しているかを判定
     * 
     * @param htmlBlock 基準となるHTMLブロック
     * @param candidateBlock 判定対象のブロック
     * @return 関連している場合はtrue
     */
    private fun isRelatedToHtml(htmlBlock: CodeBlock, candidateBlock: CodeBlock): Boolean {
        val candidateLang = candidateBlock.language.lowercase()
        
        // CSS、JavaScriptのみを対象とする
        if (candidateLang !in listOf("css", "js", "javascript")) {
            return false
        }
        
        // 距離による関連性判定
        val distance = calculateBlockDistance(htmlBlock, candidateBlock)
        val maxDistance = 500 // 最大500文字以内
        
        return distance <= maxDistance
    }
    
    /**
     * 2つのコードブロック間の距離を計算
     * 
     * @param block1 1つ目のブロック
     * @param block2 2つ目のブロック
     * @return ブロック間の文字数距離
     */
    private fun calculateBlockDistance(block1: CodeBlock, block2: CodeBlock): Int {
        return if (block1.endIndex < block2.startIndex) {
            block2.startIndex - block1.endIndex
        } else if (block2.endIndex < block1.startIndex) {
            block1.startIndex - block2.endIndex
        } else {
            0 // オーバーラップしている場合
        }
    }
    
    /**
     * テキスト内にWeb関連のバンドルが含まれているかを判定
     * 
     * @param text 判定対象のテキスト
     * @return Web関連バンドルを含む場合はtrue
     */
    fun containsWebBundle(text: String): Boolean {
        val hasHtml = text.contains("```html", ignoreCase = true) || 
                     text.contains("<html", ignoreCase = true)
        val hasCss = text.contains("```css", ignoreCase = true) || 
                    text.contains("<style", ignoreCase = true)
        val hasJs = text.contains("```js", ignoreCase = true) || 
                   text.contains("```javascript", ignoreCase = true) ||
                   text.contains("<script", ignoreCase = true)
        
        return hasHtml && (hasCss || hasJs)
    }
}

/**
 * コードブロック統計情報
 */
data class CodeBlockStats(
    val totalBlocks: Int,
    val languageCount: Int,
    val totalLines: Int,
    val totalCharacters: Int,
    val languageDistribution: Map<String, Int>
)