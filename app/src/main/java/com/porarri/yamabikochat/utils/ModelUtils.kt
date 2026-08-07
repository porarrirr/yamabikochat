package com.porarri.yamabikochat.utils

/**
 * Gemini APIモデル関連のユーティリティ関数
 * thinking機能の対応状況を判定する
 */
object ModelUtils {
    private val GEMINI_2_5_REGEX = Regex("(?i)gemini[-_/]2\\.5(?:[-_/]|$)")
    private val GEMINI_3_REGEX = Regex("(?i)gemini[-_/]3(?:[-_/]|$)")

    private fun isGemini25(model: String): Boolean {
        return GEMINI_2_5_REGEX.containsMatchIn(model)
    }

    private fun isGemini3(model: String): Boolean {
        return GEMINI_3_REGEX.containsMatchIn(model)
    }

    fun isThinkingLevelSupported(model: String): Boolean {
        return isGemini3(model)
    }

    fun getThinkingLevelOptions(model: String): List<String> {
        if (!isGemini3(model)) return emptyList()
        return if (model.contains("flash", ignoreCase = true)) {
            listOf("minimal", "low", "medium", "high")
        } else {
            listOf("low", "high")
        }
    }

    fun getDefaultThinkingLevel(model: String): String {
        return if (isGemini3(model)) "high" else ""
    }

    fun getMinimalThinkingLevel(model: String): String? {
        return if (isGemini3(model) && model.contains("flash", ignoreCase = true)) "minimal" else null
    }

    fun normalizeThinkingLevel(model: String, level: String?): String? {
        val normalized = level?.trim()?.lowercase().orEmpty()
        if (normalized.isBlank()) return null
        val options = getThinkingLevelOptions(model)
        return options.firstOrNull { it.equals(normalized, ignoreCase = true) }
    }

    /**
     * モデルがthinking機能をサポートしているかどうかを判定
     * @param model モデル名
     * @return thinking機能サポートの有無
     */
    fun isThinkingSupported(model: String): Boolean {
        return isGemini25(model) || isGemini3(model)
    }
    
    /**
     * モデルがthinking機能を常時ONにする必要があるかどうかを判定
     * Gemini 2.5/3 Proはthinking機能をオフにできない（Google仕様）
     * @param model モデル名
     * @return thinking機能が常時ON（無効化不可）かどうか
     */
    fun isThinkingAlwaysOn(model: String): Boolean {
        val isPro = model.contains("pro", ignoreCase = true)
        return isPro && (isGemini25(model) || isGemini3(model))
    }
    
    /**
     * モデルでthinking機能を無効化できるかどうかを判定
     * 2.5 Flash、2.5 Flash-Liteはthinkingを無効化可能
     * @param model モデル名
     * @return thinking機能を無効化可能かどうか
     */
    fun canDisableThinking(model: String): Boolean {
        return isGemini25(model) &&
            (model.contains("flash", ignoreCase = true) ||
                model.contains("lite", ignoreCase = true))
    }
    
    /**
     * モデルのthinking budget範囲を取得
     * @param model モデル名
     * @return Pair<最小値, 最大値> または null（thinking非対応）
     */
    fun getThinkingBudgetRange(model: String): Pair<Int, Int>? {
        return when {
            !isThinkingSupported(model) -> null
            isThinkingAlwaysOn(model) -> Pair(128, 32768) // 2.5/3 Pro
            isGemini3(model) && model.contains("flash", ignoreCase = true) -> Pair(0, 24576) // 3 Flash
            model.contains("flash-lite", ignoreCase = true) -> Pair(0, 24576) // 2.5 Flash-Lite
            model.contains("flash", ignoreCase = true) -> Pair(0, 24576) // 2.5 Flash
            else -> Pair(0, 24576) // デフォルト
        }
    }
    
    /**
     * モデルのthinking機能説明文を取得
     * @param model モデル名
     * @return 説明文
     */
    fun getThinkingDescription(model: String): String {
        return when {
            !isThinkingSupported(model) -> "このモデルはthinking機能をサポートしていません"
            isThinkingAlwaysOn(model) -> "このモデルはthinking機能が常時ONです（Google仕様）"
            isGemini3(model) && model.contains("flash", ignoreCase = true) ->
                "Gemini 3 Flashはthinkingレベル（minimal〜high）を調整できます"
            canDisableThinking(model) -> "thinking機能のON/OFFとbudget調整が可能です"
            else -> "thinking機能をサポートしています"
        }
    }
    
    /**
     * 有効なthinking budgetを計算する
     * @param model モデル名
     * @param userThinkingEnabled ユーザーのthinking設定
     * @param userThinkingBudget ユーザーのthinking budget設定
     * @return 実際にAPIに送信すべきthinking budget（nullの場合は送信しない）
     */
    fun calculateEffectiveThinkingBudget(
        model: String,
        userThinkingEnabled: Boolean,
        userThinkingBudget: Int
    ): Int? {
        return when {
            !isThinkingSupported(model) -> null // thinking非対応モデル
            isThinkingAlwaysOn(model) -> userThinkingBudget // Pro: 常時ON、budgetのみ適用
            userThinkingEnabled -> userThinkingBudget // Flash: ユーザー設定通り
            else -> 0 // Flash: 明示的にOFF
        }
    }
    
    /**
     * thinking budgetスライダーの最適なstep数を計算する
     * パフォーマンス向上のため、モデルに応じて適切なstep数を返す
     * @param model モデル名
     * @return 最適なstep数
     */
    fun getOptimalThinkingSteps(model: String): Int {
        val range = getThinkingBudgetRange(model) ?: return 64
        val totalRange = range.second - range.first
        
        return when {
            totalRange <= 1000 -> 50        // 小範囲: 50 steps
            totalRange <= 5000 -> 100       // 中範囲: 100 steps  
            totalRange <= 25000 -> 128      // 大範囲: 128 steps
            else -> 256                     // 超大範囲: 256 steps (最大)
        }.coerceAtMost(totalRange / 50)     // 最小でも50刻み
    }
    
    /**
     * thinking budgetスライダーの値範囲をFloatで取得する
     * @param model モデル名
     * @return ClosedFloatingPointRange<Float> または null（thinking非対応）
     */
    fun getThinkingBudgetFloatRange(model: String): ClosedFloatingPointRange<Float>? {
        val range = getThinkingBudgetRange(model) ?: return null
        return range.first.toFloat()..range.second.toFloat()
    }
    
    /**
     * モデル名からプロバイダーを取得
     * @param model モデル名
     * @return プロバイダー名
     */
    fun getProviderFromModel(model: String): String {
        return when {
            model.startsWith("gemini", ignoreCase = true) -> "GEMINI"
            model.startsWith("glm", ignoreCase = true) || model.startsWith("zhai", ignoreCase = true) -> "ZAI"
            model.contains("/") -> "OPENROUTER"
            else -> "GEMINI"
        }
    }
    
    /** 現行の Gemini 2.5 テキストモデル（参考用） */
    val GEMINI_2_5_MODELS = listOf(
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite"
    )

    /** 現行の Gemini 3.x テキストモデル（参考用） */
    val GEMINI_3_MODELS = listOf(
        "gemini-3.6-flash",
        "gemini-3.5-flash-lite",
        "gemini-3.5-flash",
        "gemini-3.1-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3.1-flash-lite"
    )
}
