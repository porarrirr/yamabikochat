package com.porarri.yamabikochat.utils

import org.junit.Test
import org.junit.Assert.*

class ModelUtilsTest {

    @Test
    fun `isThinkingSupported returns true for Gemini 2_5 and 3 models`() {
        // 2.5系モデルはthinking対応
        assertTrue(ModelUtils.isThinkingSupported("gemini-2.5-pro"))
        assertTrue(ModelUtils.isThinkingSupported("gemini-2.5-flash"))
        assertTrue(ModelUtils.isThinkingSupported("gemini-2.5-flash-lite"))
        assertTrue(ModelUtils.isThinkingSupported("Gemini-2.5-Pro")) // 大文字小文字不問

        // 3系モデルもthinking対応
        assertTrue(ModelUtils.isThinkingSupported("gemini-3-flash-preview"))
        assertTrue(ModelUtils.isThinkingSupported("gemini-3-pro-preview"))
        
        // 2.0系や1.5系はthinking非対応
        assertFalse(ModelUtils.isThinkingSupported("gemini-2.0-pro"))
        assertFalse(ModelUtils.isThinkingSupported("gemini-1.5-pro"))
        assertFalse(ModelUtils.isThinkingSupported("gpt-4"))
        assertFalse(ModelUtils.isThinkingSupported("claude-3"))
        assertFalse(ModelUtils.isThinkingSupported(""))
    }

    @Test
    fun `isThinkingAlwaysOn returns true only for Gemini 2_5 and 3 Pro models`() {
        // 2.5 Proと3 Proは常時ON
        assertTrue(ModelUtils.isThinkingAlwaysOn("gemini-2.5-pro"))
        assertTrue(ModelUtils.isThinkingAlwaysOn("Gemini-2.5-Pro-Preview"))
        assertTrue(ModelUtils.isThinkingAlwaysOn("gemini-3-pro"))
        
        // その他は常時ONではない
        assertFalse(ModelUtils.isThinkingAlwaysOn("gemini-2.5-flash"))
        assertFalse(ModelUtils.isThinkingAlwaysOn("gemini-2.5-flash-lite"))
        assertFalse(ModelUtils.isThinkingAlwaysOn("gemini-3-flash-preview"))
        assertFalse(ModelUtils.isThinkingAlwaysOn("gemini-2.0-pro"))
        assertFalse(ModelUtils.isThinkingAlwaysOn("gpt-4"))
        assertFalse(ModelUtils.isThinkingAlwaysOn(""))
    }

    @Test
    fun `canDisableThinking returns true for Flash and Lite models`() {
        // Flash系とLite系は無効化可能
        assertTrue(ModelUtils.canDisableThinking("gemini-2.5-flash"))
        assertTrue(ModelUtils.canDisableThinking("gemini-2.5-flash-lite"))
        assertTrue(ModelUtils.canDisableThinking("Gemini-2.5-Flash-Preview"))
        
        // Pro系や非2.5系は無効化不可
        assertFalse(ModelUtils.canDisableThinking("gemini-2.5-pro"))
        assertFalse(ModelUtils.canDisableThinking("gemini-3-flash-preview"))
        assertFalse(ModelUtils.canDisableThinking("gemini-2.0-flash"))
        assertFalse(ModelUtils.canDisableThinking("gpt-4"))
        assertFalse(ModelUtils.canDisableThinking(""))
    }

    @Test
    fun `getThinkingBudgetRange returns correct ranges for different models`() {
        // 2.5 Pro: 128-32768
        val proRange = ModelUtils.getThinkingBudgetRange("gemini-2.5-pro")
        assertNotNull(proRange)
        assertEquals(Pair(128, 32768), proRange)
        
        // 2.5 Flash: 0-24576  
        val flashRange = ModelUtils.getThinkingBudgetRange("gemini-2.5-flash")
        assertNotNull(flashRange)
        assertEquals(Pair(0, 24576), flashRange)
        
        // 2.5 Flash-Lite: 0-24576
        val liteRange = ModelUtils.getThinkingBudgetRange("gemini-2.5-flash-lite")
        assertNotNull(liteRange)
        assertEquals(Pair(0, 24576), liteRange)

        // 3 Pro: 128-32768 (compat)
        val gemini3ProRange = ModelUtils.getThinkingBudgetRange("gemini-3-pro-preview")
        assertNotNull(gemini3ProRange)
        assertEquals(Pair(128, 32768), gemini3ProRange)

        // 3 Flash: 0-24576 (compat)
        val gemini3FlashRange = ModelUtils.getThinkingBudgetRange("gemini-3-flash-preview")
        assertNotNull(gemini3FlashRange)
        assertEquals(Pair(0, 24576), gemini3FlashRange)
        
        // thinking非対応モデル: null
        assertNull(ModelUtils.getThinkingBudgetRange("gemini-2.0-pro"))
        assertNull(ModelUtils.getThinkingBudgetRange("gpt-4"))
        assertNull(ModelUtils.getThinkingBudgetRange(""))
    }

    @Test
    fun `getThinkingDescription returns appropriate descriptions`() {
        // thinking非対応
        assertEquals(
            "このモデルはthinking機能をサポートしていません",
            ModelUtils.getThinkingDescription("gemini-2.0-pro")
        )
        
        // 常時ON（Pro）
        assertEquals(
            "このモデルはthinking機能が常時ONです（Google仕様）",
            ModelUtils.getThinkingDescription("gemini-2.5-pro")
        )
        
        // ON/OFF可能（Flash）
        assertEquals(
            "thinking機能のON/OFFとbudget調整が可能です",
            ModelUtils.getThinkingDescription("gemini-2.5-flash")
        )

        // Gemini 3 Flash（thinking level）
        assertEquals(
            "Gemini 3 Flashはthinkingレベル（minimal〜high）を調整できます",
            ModelUtils.getThinkingDescription("gemini-3-flash-preview")
        )
        
        // その他のthinking対応モデル（まれなケース）
        assertEquals(
            "thinking機能をサポートしています",
            ModelUtils.getThinkingDescription("gemini-2.5-unknown")
        )
    }

    @Test
    fun `calculateEffectiveThinkingBudget returns correct values`() {
        val userBudget = 1000
        
        // thinking非対応モデル: null
        assertNull(ModelUtils.calculateEffectiveThinkingBudget("gemini-2.0-pro", true, userBudget))
        
        // Pro（常時ON）: ユーザー設定に関係なくbudgetのみ適用
        assertEquals(userBudget, ModelUtils.calculateEffectiveThinkingBudget("gemini-2.5-pro", false, userBudget))
        assertEquals(userBudget, ModelUtils.calculateEffectiveThinkingBudget("gemini-2.5-pro", true, userBudget))
        assertEquals(userBudget, ModelUtils.calculateEffectiveThinkingBudget("gemini-3-pro", false, userBudget))
        assertEquals(userBudget, ModelUtils.calculateEffectiveThinkingBudget("gemini-3-pro", true, userBudget))
        
        // Flash（ON）: ユーザー設定通り
        assertEquals(userBudget, ModelUtils.calculateEffectiveThinkingBudget("gemini-2.5-flash", true, userBudget))
        
        // Flash（OFF）: 0
        assertEquals(0, ModelUtils.calculateEffectiveThinkingBudget("gemini-2.5-flash", false, userBudget))
    }

    @Test
    fun `getOptimalThinkingSteps returns appropriate step counts`() {
        // thinking非対応: デフォルト64
        assertEquals(64, ModelUtils.getOptimalThinkingSteps("gemini-2.0-pro"))
        
        // 2.5 Pro (範囲: 32640): 256 steps (最大)
        assertEquals(256, ModelUtils.getOptimalThinkingSteps("gemini-2.5-pro"))
        
        // 2.5 Flash (範囲: 24576): 128 steps
        assertEquals(128, ModelUtils.getOptimalThinkingSteps("gemini-2.5-flash"))

        // 3 Pro (範囲: 32640): 256 steps (最大)
        assertEquals(256, ModelUtils.getOptimalThinkingSteps("gemini-3-pro-preview"))
        
        // 最小値制限のテスト（総範囲が小さい場合）
        // このテストは実際の範囲に基づいて調整が必要になる場合があります
    }

    @Test
    fun `getThinkingBudgetFloatRange returns correct float ranges`() {
        // 2.5 Pro
        val proRange = ModelUtils.getThinkingBudgetFloatRange("gemini-2.5-pro")
        assertNotNull(proRange)
        assertEquals(128.0f, proRange!!.start, 0.01f)
        assertEquals(32768.0f, proRange.endInclusive, 0.01f)

        // 3 Flash
        val gemini3FlashRange = ModelUtils.getThinkingBudgetFloatRange("gemini-3-flash-preview")
        assertNotNull(gemini3FlashRange)
        assertEquals(0.0f, gemini3FlashRange!!.start, 0.01f)
        assertEquals(24576.0f, gemini3FlashRange.endInclusive, 0.01f)
        
        // 2.5 Flash
        val flashRange = ModelUtils.getThinkingBudgetFloatRange("gemini-2.5-flash")
        assertNotNull(flashRange)
        assertEquals(0.0f, flashRange!!.start, 0.01f)
        assertEquals(24576.0f, flashRange.endInclusive, 0.01f)
        
        // thinking非対応
        assertNull(ModelUtils.getThinkingBudgetFloatRange("gemini-2.0-pro"))
    }

    @Test
    fun `getProviderFromModel returns correct providers`() {
        // Gemini models
        assertEquals("GEMINI", ModelUtils.getProviderFromModel("gemini-2.5-pro"))
        assertEquals("GEMINI", ModelUtils.getProviderFromModel("Gemini-2.0-Flash"))
        
        // OpenRouter models (contains "/")
        assertEquals("OPENROUTER", ModelUtils.getProviderFromModel("anthropic/claude-3"))
        assertEquals("OPENROUTER", ModelUtils.getProviderFromModel("openai/gpt-4"))
        assertEquals("OPENROUTER", ModelUtils.getProviderFromModel("google/gemini-pro"))
        
        // その他はGeminiとして扱う
        assertEquals("GEMINI", ModelUtils.getProviderFromModel("claude-3"))
        assertEquals("GEMINI", ModelUtils.getProviderFromModel("gpt-4"))
        assertEquals("GEMINI", ModelUtils.getProviderFromModel(""))
    }

    @Test
    fun `model lists contain expected models`() {
        // 2.5系モデルの確認
        assertTrue(ModelUtils.GEMINI_2_5_MODELS.contains("gemini-2.5-pro"))
        assertTrue(ModelUtils.GEMINI_2_5_MODELS.contains("gemini-2.5-flash"))
        assertTrue(ModelUtils.GEMINI_2_5_MODELS.contains("gemini-2.5-flash-lite"))
        assertTrue(ModelUtils.GEMINI_2_5_MODELS.contains("gemini-2.5-pro-tts"))
        assertEquals(7, ModelUtils.GEMINI_2_5_MODELS.size)
        
        // 2.0系モデルの確認
        assertTrue(ModelUtils.GEMINI_2_0_MODELS.contains("gemini-2.0-pro"))
        assertTrue(ModelUtils.GEMINI_2_0_MODELS.contains("gemini-2.0-flash"))
        assertTrue(ModelUtils.GEMINI_2_0_MODELS.contains("gemini-2.0-flash-exp"))
        assertEquals(3, ModelUtils.GEMINI_2_0_MODELS.size)
    }

    @Test
    fun `case insensitive handling works correctly`() {
        // 大文字小文字を混在させてテスト
        assertTrue(ModelUtils.isThinkingSupported("GEMINI-2.5-PRO"))
        assertTrue(ModelUtils.isThinkingSupported("gemini-2.5-pro"))
        assertTrue(ModelUtils.isThinkingSupported("Gemini-2.5-Pro"))
        
        assertTrue(ModelUtils.isThinkingAlwaysOn("GEMINI-2.5-PRO"))
        assertTrue(ModelUtils.canDisableThinking("GEMINI-2.5-FLASH"))
        
        assertEquals("GEMINI", ModelUtils.getProviderFromModel("GEMINI-2.5-PRO"))
        assertEquals("OPENROUTER", ModelUtils.getProviderFromModel("ANTHROPIC/CLAUDE-3"))
    }

    @Test
    fun `edge cases and error handling`() {
        // 空文字列
        assertFalse(ModelUtils.isThinkingSupported(""))
        assertFalse(ModelUtils.isThinkingAlwaysOn(""))
        assertFalse(ModelUtils.canDisableThinking(""))
        assertNull(ModelUtils.getThinkingBudgetRange(""))
        assertEquals("GEMINI", ModelUtils.getProviderFromModel(""))
        
        // スペースを含む文字列
        assertFalse(ModelUtils.isThinkingSupported(" "))
        assertFalse(ModelUtils.isThinkingSupported("gemini 2.5 pro"))
        
        // 部分一致のテスト
        assertTrue(ModelUtils.isThinkingSupported("custom-gemini-2.5-pro-modified"))
        assertTrue(ModelUtils.isThinkingAlwaysOn("custom-gemini-2.5-pro-modified"))
    }

    @Test
    fun `thinking level helpers work for Gemini 3 models`() {
        assertTrue(ModelUtils.isThinkingLevelSupported("gemini-3-flash-preview"))
        assertTrue(ModelUtils.isThinkingLevelSupported("gemini-3-pro-preview"))
        assertFalse(ModelUtils.isThinkingLevelSupported("gemini-2.5-flash"))

        assertEquals(
            listOf("minimal", "low", "medium", "high"),
            ModelUtils.getThinkingLevelOptions("gemini-3-flash-preview")
        )
        assertEquals(
            listOf("low", "high"),
            ModelUtils.getThinkingLevelOptions("gemini-3-pro-preview")
        )
        assertEquals("high", ModelUtils.getDefaultThinkingLevel("gemini-3-flash-preview"))
        assertEquals("minimal", ModelUtils.getMinimalThinkingLevel("gemini-3-flash-preview"))
        assertNull(ModelUtils.getMinimalThinkingLevel("gemini-3-pro-preview"))
        assertEquals("low", ModelUtils.normalizeThinkingLevel("gemini-3-pro-preview", "LOW"))
        assertNull(ModelUtils.normalizeThinkingLevel("gemini-3-pro-preview", "medium"))
    }
}
