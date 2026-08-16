package com.porarri.yamabikochat.data.models

import com.porarri.yamabikochat.utils.SvgAnalyzer
import com.porarri.yamabikochat.utils.SvgAnalysisResult

/**
 * LLM応答から検知されたコードブロックを表すデータクラス
 * 
 * @param language プログラミング言語（例: "python", "html", "javascript"）
 * @param content コードの内容
 * @param startIndex 元のテキスト内でのコードブロック開始位置
 * @param endIndex 元のテキスト内でのコードブロック終了位置
 * @param extractionMethod 検知方法（"markdown" または "custom_tag"）
 * @param filename 推奨ファイル名（拡張子含む）
 */
data class CodeBlock(
    val language: String,
    val content: String,
    val startIndex: Int,
    val endIndex: Int,
    val extractionMethod: String,
    val filename: String
) {
    /**
     * ファイル拡張子を取得
     */
    val fileExtension: String
        get() = filename.substringAfterLast(".", "")
    
    /**
     * 表示用の言語名を取得
     */
    val displayLanguage: String
        get() = when (language.lowercase()) {
            "py", "python" -> "Python"
            "js", "javascript" -> "JavaScript"
            "ts", "typescript" -> "TypeScript"
            "html" -> "HTML"
            "css" -> "CSS"
            "kt", "kotlin" -> "Kotlin"
            "java" -> "Java"
            "json" -> "JSON"
            "xml" -> "XML"
            "svg" -> "SVG"
            "md", "markdown" -> "Markdown"
            "sql" -> "SQL"
            "sh", "bash" -> "Shell"
            "yaml", "yml" -> "YAML"
            else -> language.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
        }
    
    /**
     * コードブロックのサイズを取得（文字数）
     */
    val size: Int
        get() = content.length
    
    /**
     * コードブロックの行数を取得
     */
    val lineCount: Int
        get() = content.lines().size
    
    /**
     * SVGコードかどうかを判定
     */
    val isSvg: Boolean
        get() = language.equals("svg", ignoreCase = true)

    val isHtml: Boolean
        get() = language.lowercase() in listOf("html", "htm", "xhtml")
    
    /**
     * プレビュー表示が可能かどうかを判定
     */
    val isPreviewable: Boolean
        get() = isSvg || isHtml
    
    /**
     * SVGの場合の解析結果を取得
     * 
     * 注意: この操作は重い可能性があるため、キャッシュして使用することを推奨
     */
    fun getSvgAnalysisResult(): SvgAnalysisResult? {
        return if (isSvg) {
            SvgAnalyzer.analyzeSvg(content)
        } else {
            null
        }
    }
    
    /**
     * ファイルタイプを取得
     */
    val fileType: CodeBlockType
        get() = when {
            isSvg -> CodeBlockType.SVG_GRAPHICS
            language.lowercase() in listOf("jpg", "jpeg", "png", "gif", "webp") -> CodeBlockType.IMAGE
            language.lowercase() in listOf("html", "css") -> CodeBlockType.WEB
            language.lowercase() in listOf("py", "python", "js", "javascript", "kt", "kotlin", "java") -> CodeBlockType.CODE
            language.lowercase() in listOf("json", "xml", "yaml", "yml") -> CodeBlockType.DATA
            else -> CodeBlockType.TEXT
        }
}

/**
 * コードブロックのタイプ分類
 */
enum class CodeBlockType {
    CODE,           // プログラムコード
    WEB,            // Web関連（HTML, CSS）
    DATA,           // データファイル（JSON, XML, YAML）
    SVG_GRAPHICS,   // SVGグラフィックス
    IMAGE,          // 画像ファイル
    TEXT            // テキストファイル
}