package com.porarri.yamabikochat.ui.chat

import java.util.regex.Pattern

/**
 * 数式検出とレンダリング方法決定のユーティリティクラス
 */
object MathUtils {
    
    // 数式を検出するためのパターン
    private val mathPatterns = listOf(
        Pattern.compile("\\$[^$\n]+\\$"),           // $...$
        Pattern.compile("\\$\\$[^$]+\\$\\$"),       // $$...$$
        Pattern.compile("\\\\\\([^)]+\\\\\\)"),     // \(...\)
        Pattern.compile("\\\\\\[[^]]+\\\\\\]"),     // \[...\]
        Pattern.compile("\\\\frac\\{[^}]+\\}\\{[^}]+\\}"), // \frac{...}{...}
        Pattern.compile("\\\\[a-zA-Z]+"),           // \sin, \cos, \theta など
        Pattern.compile("\\^\\{[^}]+\\}"),          // ^{...}
        Pattern.compile("_\\{[^}]+\\}"),            // _{...}
        Pattern.compile("\\\\text\\{[^}]+\\}")      // \text{...}
    )
    
    // 数学記号のパターン
    private val mathSymbolPatterns = listOf(
        Pattern.compile("[α-ωΑ-Ω]"),               // ギリシャ文字
        Pattern.compile("[≈≠≤≥±×÷∞∑∫∂∇√]"),        // 数学記号
        Pattern.compile("[²³⁴⁵⁶⁷⁸⁹⁰¹]"),          // 上付き文字
        Pattern.compile("[₀₁₂₃₄₅₆₇₈₉]")           // 下付き文字
    )
    
    /**
     * テキストに数式が含まれているかどうかを判定
     */
    fun containsMathExpression(text: String): Boolean {
        // LaTeX数式パターンをチェック
        for (pattern in mathPatterns) {
            if (pattern.matcher(text).find()) {
                return true
            }
        }
        
        // 数学記号パターンをチェック
        for (pattern in mathSymbolPatterns) {
            if (pattern.matcher(text).find()) {
                return true
            }
        }
        
        return false
    }
    
    /**
     * 数式の複雑さを評価（WebViewが必要かどうかの判定）
     */
    fun requiresWebViewRendering(text: String): Boolean {
        // 複雑な数式パターンをチェック
        val complexPatterns = listOf(
            Pattern.compile("\\\\frac\\{[^}]+\\}\\{[^}]+\\}"), // 分数
            Pattern.compile("\\$\\$[^$]+\\$\\$"),               // ディスプレイ数式
            Pattern.compile("\\\\[a-zA-Z]+\\{[^}]+\\}"),        // LaTeXコマンド
            Pattern.compile("\\^\\{[^}]+\\}"),                  // 複雑な上付き
            Pattern.compile("_\\{[^}]+\\}"),                    // 複雑な下付き
            Pattern.compile("\\\\sum|\\\\int|\\\\prod"),        // 積分・総和記号
            Pattern.compile("\\\\sqrt\\{[^}]+\\}"),             // 平方根
            Pattern.compile("\\\\left|\\\\right"),              // 括弧
            Pattern.compile("\\$[^$]+\\$")                      // 単純な数式も含める
        )
        
        for (pattern in complexPatterns) {
            if (pattern.matcher(text).find()) {
                return true
            }
        }
        
        return false
    }
    
    
    /**
     * 数式の統計情報を取得（デバッグ用）
     */
    fun getMathStatistics(text: String): MathStatistics {
        var inlineCount = 0
        var displayCount = 0
        var complexCount = 0
        
        // インライン数式をカウント
        val inlinePattern = Pattern.compile("\\$[^$\n]+\\$")
        val inlineMatcher = inlinePattern.matcher(text)
        while (inlineMatcher.find()) {
            inlineCount++
        }
        
        // ディスプレイ数式をカウント
        val displayPattern = Pattern.compile("\\$\\$[^$]+\\$\\$")
        val displayMatcher = displayPattern.matcher(text)
        while (displayMatcher.find()) {
            displayCount++
        }
        
        // 複雑な数式をカウント
        val complexPattern = Pattern.compile("\\\\frac|\\\\sqrt|\\\\sum|\\\\int|\\\\prod")
        val complexMatcher = complexPattern.matcher(text)
        while (complexMatcher.find()) {
            complexCount++
        }
        
        return MathStatistics(
            inlineCount = inlineCount,
            displayCount = displayCount,
            complexCount = complexCount,
            totalLength = text.length
        )
    }
    
    /**
     * 数式統計情報のデータクラス
     */
    data class MathStatistics(
        val inlineCount: Int,
        val displayCount: Int,
        val complexCount: Int,
        val totalLength: Int
    )
}