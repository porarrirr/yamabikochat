package com.porarri.yamabikochat.data.remote

import com.porarri.yamabikochat.data.skills.AgentSkillCatalogEntry
import com.porarri.yamabikochat.data.skills.SkillRequestContext
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OpenAIHostedSkillsPolicyTest {
    @Test
    fun acceptsOnlyDocumentedHostedSkillModels() {
        assertTrue(OpenAIHostedSkillsPolicy.supportsModel("gpt-5.4"))
        assertTrue(OpenAIHostedSkillsPolicy.supportsModel("gpt-5.4-mini-2026-03-17"))
        assertTrue(OpenAIHostedSkillsPolicy.supportsModel("gpt-5.5"))
        assertTrue(OpenAIHostedSkillsPolicy.supportsModel("gpt-5.6"))
        assertTrue(OpenAIHostedSkillsPolicy.supportsModel("gpt-5.6-terra"))

        assertFalse(OpenAIHostedSkillsPolicy.supportsModel("gpt-4.1-mini"))
        assertFalse(OpenAIHostedSkillsPolicy.supportsModel("gpt-5.4-pro"))
        assertFalse(OpenAIHostedSkillsPolicy.supportsModel("gpt-5.5-pro"))
    }

    @Test
    fun acceptsOnlyOfficialOpenAIBaseUrl() {
        assertTrue(OpenAIHostedSkillsPolicy.isOfficialBaseUrl("https://api.openai.com/v1/"))
        assertTrue(OpenAIHostedSkillsPolicy.isOfficialBaseUrl("https://API.OPENAI.COM/v1"))
        assertFalse(OpenAIHostedSkillsPolicy.isOfficialBaseUrl("http://api.openai.com/v1/"))
        assertFalse(OpenAIHostedSkillsPolicy.isOfficialBaseUrl("https://proxy.example.com/v1/"))
        assertFalse(OpenAIHostedSkillsPolicy.isOfficialBaseUrl("https://api.openai.com.evil.example/v1/"))
        assertNull(OpenAIHostedSkillsPolicy.validationError("gpt-5.6-sol", "https://api.openai.com/v1/"))
    }

    @Test
    fun cacheKeySeparatesCredentialsWithoutContainingThem() {
        val context = SkillRequestContext(
            catalog = listOf(AgentSkillCatalogEntry("test", "test")),
            explicitlyRequestedNames = emptyList(),
            explicitInstructions = emptyList(),
            resourceLists = emptyList(),
            conversationId = "conversation-1",
            enabledSkillSetHash = "skills-hash",
            hostedExecutionEnabled = true
        )

        val first = OpenAIHostedSkillsPolicy.cacheKey(context, "secret-key-a")
        val second = OpenAIHostedSkillsPolicy.cacheKey(context, "secret-key-b")

        assertNotEquals(first, second)
        assertFalse(first.contains("secret-key-a"))
        assertFalse(second.contains("secret-key-b"))
    }
}
