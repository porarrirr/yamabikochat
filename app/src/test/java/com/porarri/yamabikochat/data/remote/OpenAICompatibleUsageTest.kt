package com.porarri.yamabikochat.data.remote

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OpenAICompatibleUsageTest {
    @Test
    fun topLevelDeepSeekCacheUsageUsesDshDisjointBuckets() {
        val usage = OpenRouterUsage(
            prompt_tokens = 12_071,
            completion_tokens = 61,
            total_tokens = 12_132,
            promptCacheHitTokens = 12_032,
            promptCacheMissTokens = 39
        ).toTokenUsageSnapshot()

        assertEquals(39, usage.inputTokens)
        assertEquals(12_032, usage.cachedInputTokens)
        assertEquals(61, usage.outputTokens)
        assertEquals(12_132, usage.totalTokens)
    }

    @Test
    fun nestedCachedTokensTakePrecedenceWithoutTreatingMissAsCacheWrite() {
        val usage = OpenRouterUsage(
            prompt_tokens = 100,
            completion_tokens = 10,
            promptCacheHitTokens = 70,
            promptCacheMissTokens = 30,
            prompt_tokens_details = OpenRouterPromptTokenDetails(cached_tokens = 80)
        ).toTokenUsageSnapshot()

        assertEquals(20, usage.inputTokens)
        assertEquals(80, usage.cachedInputTokens)
        assertNull(usage.reasoningTokens)
        assertEquals(110, usage.totalTokens)
    }
}
