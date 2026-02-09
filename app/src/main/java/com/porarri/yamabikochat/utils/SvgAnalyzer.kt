package com.porarri.yamabikochat.utils

import kotlin.math.max
import kotlin.math.min

/**
 * SVGコンテンツの解析とメタデータ抽出を行うユーティリティクラス
 */
object SvgAnalyzer {
    
    /**
     * SVGの基本的な情報を解析
     * 
     * @param svgContent SVGコンテンツ
     * @return SVG解析結果
     */
    fun analyzeSvg(svgContent: String): SvgAnalysisResult {
        try {
            val cleanContent = svgContent.trim()
            
            if (!isValidSvg(cleanContent)) {
                return SvgAnalysisResult.Invalid("有効なSVGではありません")
            }
            
            val dimensions = extractDimensions(cleanContent)
            val viewBox = extractViewBox(cleanContent)
            val elementStats = analyzeElements(cleanContent)
            val complexity = calculateComplexity(elementStats, cleanContent)
            val title = extractTitle(cleanContent)
            val description = extractDescription(cleanContent)
            
            return SvgAnalysisResult.Valid(
                width = dimensions.width,
                height = dimensions.height,
                viewBox = viewBox,
                elementStats = elementStats,
                complexity = complexity,
                title = title,
                description = description,
                hasNamespace = hasNamespace(cleanContent),
                fileSize = cleanContent.toByteArray(Charsets.UTF_8).size
            )
        } catch (e: Exception) {
            return SvgAnalysisResult.Invalid("SVG解析中にエラーが発生しました: ${e.message}")
        }
    }
    
    /**
     * SVGの寸法情報を抽出
     */
    private fun extractDimensions(svgContent: String): SvgDimensions {
        val svgTagRegex = """<svg[^>]*>""".toRegex(RegexOption.IGNORE_CASE)
        val svgTag = svgTagRegex.find(svgContent)?.value ?: ""
        
        val widthRegex = """width\s*=\s*["']?([^"'\s>]+)["']?""".toRegex(RegexOption.IGNORE_CASE)
        val heightRegex = """height\s*=\s*["']?([^"'\s>]+)["']?""".toRegex(RegexOption.IGNORE_CASE)
        
        val widthMatch = widthRegex.find(svgTag)
        val heightMatch = heightRegex.find(svgTag)
        
        val width = widthMatch?.groupValues?.get(1)?.let { parseNumber(it) }
        val height = heightMatch?.groupValues?.get(1)?.let { parseNumber(it) }
        
        return SvgDimensions(width, height)
    }
    
    /**
     * ViewBox情報を抽出
     */
    private fun extractViewBox(svgContent: String): SvgViewBox? {
        val viewBoxRegex = """viewBox\s*=\s*["']([^"']+)["']""".toRegex(RegexOption.IGNORE_CASE)
        val match = viewBoxRegex.find(svgContent) ?: return null
        
        val values = match.groupValues[1].trim().split(Regex("\\s+"))
        if (values.size != 4) return null
        
        return try {
            SvgViewBox(
                x = values[0].toDouble(),
                y = values[1].toDouble(),
                width = values[2].toDouble(),
                height = values[3].toDouble()
            )
        } catch (e: NumberFormatException) {
            null
        }
    }
    
    /**
     * SVG要素の統計を分析
     */
    private fun analyzeElements(svgContent: String): SvgElementStats {
        val elementRegex = """<(?!/)([a-zA-Z][a-zA-Z0-9:_-]*)[^>]*?>""".toRegex(RegexOption.IGNORE_CASE)
        val elements = elementRegex.findAll(svgContent)
            .map { it.groupValues[1].lowercase() }
            .filter { it != "svg" } // svg要素自体は除外
            .groupingBy { it }
            .eachCount()
        
        val pathCount = elements["path"] ?: 0
        val circleCount = elements["circle"] ?: 0
        val rectCount = elements["rect"] ?: 0
        val lineCount = elements["line"] ?: 0
        val polygonCount = elements["polygon"] ?: 0
        val polylineCount = elements["polyline"] ?: 0
        val ellipseCount = elements["ellipse"] ?: 0
        val textCount = elements["text"] ?: 0
        val imageCount = elements["image"] ?: 0
        val groupCount = elements["g"] ?: 0
        val useCount = elements["use"] ?: 0
        
        val shapeElements = pathCount + circleCount + rectCount + lineCount + 
                           polygonCount + polylineCount + ellipseCount
        val totalElements = elements.values.sum()
        
        return SvgElementStats(
            totalElements = totalElements,
            shapeElements = shapeElements,
            pathCount = pathCount,
            circleCount = circleCount,
            rectCount = rectCount,
            lineCount = lineCount,
            polygonCount = polygonCount,
            polylineCount = polylineCount,
            ellipseCount = ellipseCount,
            textCount = textCount,
            imageCount = imageCount,
            groupCount = groupCount,
            useCount = useCount,
            otherElements = totalElements - shapeElements - textCount - imageCount - groupCount - useCount
        )
    }
    
    /**
     * SVGの複雑さを計算
     */
    private fun calculateComplexity(elementStats: SvgElementStats, svgContent: String): SvgComplexity {
        var score = 0
        
        // 要素数による複雑さ
        score += when {
            elementStats.totalElements <= 5 -> 1
            elementStats.totalElements <= 15 -> 2
            elementStats.totalElements <= 50 -> 3
            else -> 4
        }

        if (elementStats.shapeElements >= 5) {
            score += 1
        }

        if (elementStats.textCount > 0 || elementStats.imageCount > 0 || elementStats.useCount > 0) {
            score += 1
        }
        
        // Path要素の複雑さ（パスコマンド数による）
        val pathCommandRegex = """d\s*=\s*["']([^"']+)["']""".toRegex(RegexOption.IGNORE_CASE)
        val pathCommands = pathCommandRegex.findAll(svgContent)
            .sumOf { match ->
                val pathData = match.groupValues[1]
                pathData.count { it.uppercaseChar() in "MLHVCSQTAZ" }
            }
        
        score += when {
            pathCommands <= 10 -> 0
            pathCommands <= 50 -> 1
            pathCommands <= 200 -> 2
            else -> 3
        }
        
        // グループ化による複雑さ
        score += min(elementStats.groupCount / 3, 2)
        
        // アニメーション要素の存在
        val animationElements = listOf("animate", "animateTransform", "animateMotion", "animateColor")
        val hasAnimation = animationElements.any { svgContent.contains("<$it", ignoreCase = true) }
        if (hasAnimation) score += 2
        
        // グラデーションやパターンの存在
        val hasGradient = svgContent.contains("<linearGradient", ignoreCase = true) or
                         svgContent.contains("<radialGradient", ignoreCase = true)
        val hasPattern = svgContent.contains("<pattern", ignoreCase = true)
        if (hasGradient || hasPattern) score += 1
        
        return when {
            score <= 2 -> SvgComplexity.SIMPLE
            score <= 5 -> SvgComplexity.MODERATE
            score <= 8 -> SvgComplexity.COMPLEX
            else -> SvgComplexity.VERY_COMPLEX
        }
    }
    
    /**
     * SVGのタイトルを抽出
     */
    private fun extractTitle(svgContent: String): String? {
        val titleRegex = """<title[^>]*>(.*?)</title>""".toRegex(RegexOption.IGNORE_CASE)
        return titleRegex.find(svgContent)?.groupValues?.get(1)?.trim()
    }
    
    /**
     * SVGの説明を抽出
     */
    private fun extractDescription(svgContent: String): String? {
        val descRegex = """<desc[^>]*>(.*?)</desc>""".toRegex(RegexOption.IGNORE_CASE)
        return descRegex.find(svgContent)?.groupValues?.get(1)?.trim()
    }
    
    /**
     * SVGが名前空間を持っているかチェック
     */
    private fun hasNamespace(svgContent: String): Boolean {
        return svgContent.contains("xmlns", ignoreCase = true)
    }
    
    /**
     * SVGが有効かどうかをチェック
     */
    private fun isValidSvg(content: String): Boolean {
        return content.contains("<svg", ignoreCase = true) &&
               content.contains("</svg>", ignoreCase = true)
    }
    
    /**
     * 数値文字列をパース（単位付きも対応）
     */
    private fun parseNumber(value: String): Double? {
        return try {
            val numericValue = value.replace(Regex("[^0-9.-]"), "")
            if (numericValue.isEmpty()) null else numericValue.toDouble()
        } catch (e: NumberFormatException) {
            null
        }
    }
}

/**
 * SVG解析結果
 */
sealed class SvgAnalysisResult {
    data class Valid(
        val width: Double?,
        val height: Double?,
        val viewBox: SvgViewBox?,
        val elementStats: SvgElementStats,
        val complexity: SvgComplexity,
        val title: String?,
        val description: String?,
        val hasNamespace: Boolean,
        val fileSize: Int
    ) : SvgAnalysisResult()
    
    data class Invalid(val reason: String) : SvgAnalysisResult()
}

/**
 * SVG寸法情報
 */
data class SvgDimensions(
    val width: Double?,
    val height: Double?
) {
    val aspectRatio: Double?
        get() = if (width != null && height != null && height != 0.0) width / height else null
}

/**
 * SVG ViewBox情報
 */
data class SvgViewBox(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double
) {
    val aspectRatio: Double
        get() = if (height != 0.0) width / height else 1.0
}

/**
 * SVG要素統計
 */
data class SvgElementStats(
    val totalElements: Int,
    val shapeElements: Int,
    val pathCount: Int,
    val circleCount: Int,
    val rectCount: Int,
    val lineCount: Int,
    val polygonCount: Int,
    val polylineCount: Int,
    val ellipseCount: Int,
    val textCount: Int,
    val imageCount: Int,
    val groupCount: Int,
    val useCount: Int,
    val otherElements: Int
) {
    val isTextHeavy: Boolean
        get() = textCount > shapeElements / 2
    
    val isPrimarilyShapes: Boolean
        get() = shapeElements > totalElements * 0.7
}

/**
 * SVG複雑さレベル
 */
enum class SvgComplexity {
    SIMPLE,         // 単純な図形
    MODERATE,       // 中程度の複雑さ
    COMPLEX,        // 複雑
    VERY_COMPLEX;   // 非常に複雑
    
    val displayName: String
        get() = when (this) {
            SIMPLE -> "シンプル"
            MODERATE -> "標準"
            COMPLEX -> "複雑"
            VERY_COMPLEX -> "高度"
        }
}
