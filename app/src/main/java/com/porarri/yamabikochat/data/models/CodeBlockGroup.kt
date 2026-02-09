package com.porarri.yamabikochat.data.models

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 関連するコードブロックをグループ化するデータクラス
 * 主にHTML、CSS、JavaScriptなどの関連する技術のコードブロックを統合処理するために使用
 */
data class CodeBlockGroup(
    val blocks: List<CodeBlock>,
    val groupType: GroupType,
    val baseFilename: String? = null
) {
    /**
     * グループ内のHTMLブロックを取得
     */
    val htmlBlock: CodeBlock?
        get() = blocks.find { it.language.lowercase() == "html" }
    
    /**
     * グループ内のCSSブロックを取得
     */
    val cssBlocks: List<CodeBlock>
        get() = blocks.filter { it.language.lowercase() == "css" }
    
    /**
     * グループ内のJavaScriptブロックを取得
     */
    val jsBlocks: List<CodeBlock>
        get() = blocks.filter { it.language.lowercase() in listOf("js", "javascript") }
    
    /**
     * グループ内のその他のブロック
     */
    val otherBlocks: List<CodeBlock>
        get() = blocks.filter { block ->
            val lang = block.language.lowercase()
            lang !in listOf("html", "css", "js", "javascript")
        }
    
    /**
     * 統合可能かどうかを判定
     */
    val canIntegrate: Boolean
        get() = when (groupType) {
            GroupType.WEB_BUNDLE -> htmlBlock != null && (cssBlocks.isNotEmpty() || jsBlocks.isNotEmpty())
            GroupType.MIXED -> false
            GroupType.SINGLE -> false
        }
    
    /**
     * 統合HTMLファイル名を生成
     */
    fun generateIntegratedFilename(): String {
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
        
        val baseName = baseFilename 
            ?: htmlBlock?.filename?.substringBeforeLast(".")
            ?: extractFileNameFromHtml()
            ?: "integrated_page"
        
        return "${baseName}_$timestamp.html"
    }
    
    /**
     * HTML内容からファイル名を抽出
     */
    private fun extractFileNameFromHtml(): String? {
        return htmlBlock?.content?.let { content ->
            // <title>タグから名前を抽出
            val titleRegex = """<title[^>]*>(.*?)</title>""".toRegex(RegexOption.IGNORE_CASE)
            titleRegex.find(content)?.groupValues?.get(1)?.trim()
                ?.replace(Regex("[^a-zA-Z0-9_-]"), "_")
                ?.take(20)
                ?.lowercase()
        }
    }
    
    /**
     * グループの統計情報を取得
     */
    fun getStats(): GroupStats {
        return GroupStats(
            totalBlocks = blocks.size,
            htmlBlocks = if (htmlBlock != null) 1 else 0,
            cssBlocks = cssBlocks.size,
            jsBlocks = jsBlocks.size,
            otherBlocks = otherBlocks.size,
            totalLines = blocks.sumOf { it.lineCount },
            totalCharacters = blocks.sumOf { it.size },
            integrable = canIntegrate
        )
    }
    
    /**
     * 最初のブロックから最後のブロックまでの範囲を取得
     */
    val textRange: IntRange
        get() = if (blocks.isNotEmpty()) {
            blocks.minOf { it.startIndex }..blocks.maxOf { it.endIndex }
        } else {
            0..0
        }
    
    /**
     * グループ内のブロック間の最大距離を計算
     */
    val maxBlockDistance: Int
        get() = if (blocks.size < 2) {
            0
        } else {
            val sortedBlocks = blocks.sortedBy { it.startIndex }
            var maxDistance = 0
            for (i in 0 until sortedBlocks.size - 1) {
                val distance = sortedBlocks[i + 1].startIndex - sortedBlocks[i].endIndex
                if (distance > maxDistance) {
                    maxDistance = distance
                }
            }
            maxDistance
        }
}

/**
 * コードブロックグループのタイプ
 */
enum class GroupType(val displayName: String) {
    /** Web関連のバンドル（HTML + CSS + JS） */
    WEB_BUNDLE("Web バンドル"),
    
    /** 混合タイプ（様々な言語の組み合わせ） */
    MIXED("混合"),
    
    /** 単一ブロック */
    SINGLE("単一")
}

/**
 * グループ統計情報
 */
data class GroupStats(
    val totalBlocks: Int,
    val htmlBlocks: Int,
    val cssBlocks: Int,
    val jsBlocks: Int,
    val otherBlocks: Int,
    val totalLines: Int,
    val totalCharacters: Int,
    val integrable: Boolean
) {
    /**
     * グループの説明文を生成
     */
    fun getDescription(): String {
        val parts = mutableListOf<String>()
        
        if (htmlBlocks > 0) parts.add("HTML")
        if (cssBlocks > 0) parts.add("CSS${if (cssBlocks > 1) "×$cssBlocks" else ""}")
        if (jsBlocks > 0) parts.add("JS${if (jsBlocks > 1) "×$jsBlocks" else ""}")
        if (otherBlocks > 0) parts.add("その他×$otherBlocks")
        
        return parts.joinToString(" + ")
    }
}