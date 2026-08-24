package com.porarri.yamabikochat.data.repositories

import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.modelsdev.CatalogModel
import com.porarri.yamabikochat.data.modelsdev.CatalogProvider
import com.porarri.yamabikochat.data.modelsdev.CatalogReasoningOption
import com.porarri.yamabikochat.data.modelsdev.ModelsDevCatalogRepository
import com.porarri.yamabikochat.data.remote.OpenRouterModelService
import com.porarri.yamabikochat.data.skills.AgentSkillRepository
import com.porarri.yamabikochat.data.model.ToolCall
import com.porarri.yamabikochat.data.model.ToolDefinition
import com.porarri.yamabikochat.data.model.ToolResult
import com.porarri.yamabikochat.data.tools.LocalToolExecutor
import com.porarri.yamabikochat.data.tools.LocalToolRegistry
import com.porarri.yamabikochat.data.tools.editor.StrReplaceEditorTool
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProviderRequestSettingsResolverModelsDevTest {
    @Test
    fun editorIsPublishedOnlyForNormalAndDualPiToolContexts() = runTest {
        val editorExecutor = object : LocalToolExecutor {
            override val definition = ToolDefinition(StrReplaceEditorTool.NAME, "editor", "{}")
            override suspend fun execute(call: ToolCall) = ToolResult(call.id, call.name, "ok")
        }
        val resolver = ProviderRequestSettingsResolver(
            modelService = mockk<OpenRouterModelService>(relaxed = true),
            skillRepository = mockk<AgentSkillRepository>(relaxed = true),
            localToolRegistry = LocalToolRegistry(listOf(editorExecutor))
        )
        suspend fun hasEditor(
            context: Settings.ReasoningContext,
            scope: ProviderRequestToolScope = ProviderRequestToolScope.All,
            provider: String = "GEMINI"
        ) = resolver.resolve(Settings(), provider, "gemini-2.5-flash", context, scope)
            .tools.any { it.payload["name"] == StrReplaceEditorTool.NAME }

        assertTrue(hasEditor(Settings.ReasoningContext.DEFAULT))
        assertTrue(hasEditor(Settings.ReasoningContext.DUAL_A))
        assertTrue(hasEditor(Settings.ReasoningContext.DUAL_B))
        assertFalse(hasEditor(Settings.ReasoningContext.AUTO_A))
        assertFalse(hasEditor(Settings.ReasoningContext.AUTO_B))
        assertFalse(hasEditor(Settings.ReasoningContext.DEFAULT, ProviderRequestToolScope.FusionPanel(true)))
        assertFalse(hasEditor(Settings.ReasoningContext.DEFAULT, provider = "APPLE_INTELLIGENCE"))
    }

    @Test
    fun toolCapabilityIsNotInventedWhenFalseOrMissing() = runTest {
        val provider = CatalogProvider(
            id = "example",
            name = "Example",
            npm = "example-sdk",
            models = listOf(
                CatalogModel(id = "disabled", name = "Disabled", toolCall = false),
                CatalogModel(id = "missing", name = "Missing", toolCall = null),
                CatalogModel(id = "enabled", name = "Enabled", toolCall = true)
            )
        )
        val catalog = mockk<ModelsDevCatalogRepository>()
        every { catalog.provider(any()) } returns provider
        val resolver = ProviderRequestSettingsResolver(
            modelService = mockk<OpenRouterModelService>(relaxed = true),
            skillRepository = mockk<AgentSkillRepository>(relaxed = true),
            modelsDevCatalogRepository = catalog
        )
        val settings = Settings(clientWebSearchToolEnabled = true)

        for (model in listOf("disabled", "missing")) {
            val resolved = resolver.resolve(settings, "MODELS_DEV:example", model)
            assertEquals("false", resolved.metadata["supportsClientTools"])
            assertFalse(resolved.tools.any { it.payload["name"] == "web_search" })
        }
        val enabled = resolver.resolve(settings, "MODELS_DEV:example", "enabled")
        assertEquals("true", enabled.metadata["supportsClientTools"])
        assertTrue(enabled.tools.any { it.payload["name"] == "web_search" })
    }

    @Test
    fun savedReasoningEffortIsAppliedWhenCatalogSupportsIt() = runTest {
        val resolved = museSparkResolver(savedEffort = "medium")
            .resolve(Settings(), "MODELS_DEV:opencode-go", "muse-spark-1.2-contributor")
        assertEquals("medium", resolved.thinking?.effort)
    }

    @Test
    fun blankReasoningEffortDoesNotInventThinkingConfig() = runTest {
        val resolved = museSparkResolver(savedEffort = "")
            .resolve(Settings(), "MODELS_DEV:opencode-go", "muse-spark-1.2-contributor")
        assertNull(resolved.thinking)
    }

    private fun museSparkResolver(savedEffort: String): ProviderRequestSettingsResolver {
        val provider = CatalogProvider(
            id = "opencode-go",
            name = "OpenCode Go",
            npm = "@ai-sdk/openai-compatible",
            models = listOf(
                CatalogModel(
                    id = "muse-spark-1.2-contributor",
                    name = "Muse Spark 1.2 Contributor",
                    reasoning = true,
                    reasoningOptions = listOf(
                        CatalogReasoningOption(
                            type = "effort",
                            values = listOf("minimal", "low", "medium", "high", "xhigh")
                        )
                    )
                )
            )
        )
        val catalog = mockk<ModelsDevCatalogRepository>()
        every { catalog.provider(any()) } returns provider
        return ProviderRequestSettingsResolver(
            modelService = mockk<OpenRouterModelService>(relaxed = true),
            skillRepository = mockk<AgentSkillRepository>(relaxed = true),
            modelsDevCatalogRepository = catalog,
            modelsDevReasoningEffort = { _, _ -> savedEffort }
        )
    }
}
