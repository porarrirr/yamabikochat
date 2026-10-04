package com.porarri.yamabikochat.pi

import android.security.NetworkSecurityPolicy
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.porarri.yamabikochat.data.remote.OpenCodeGoModelCatalog
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.BeforeClass
import org.junit.runner.RunWith
import java.io.File
import java.security.MessageDigest

/** Exercises the APK's real NodeMobile/JNA bridge without provider credentials or inference. */
@RunWith(AndroidJUnit4::class)
class PiAgentRuntimeTest {
    companion object {
        @BeforeClass
        @JvmStatic
        fun startsOnceEvenWhenInitialCallerIsCancelled() = runBlocking {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val runtime = PiAgentRuntime.getInstance(context)
            fun launchCount() = DiagnosticsLogger.read().lineSequence()
                .count { it.contains("PiNodeRunner starting node engine") }
            val before = launchCount()
            val owner = launch(Dispatchers.Default) { runtime.verifyReady() }
            withTimeout(15_000) {
                while (owner.isActive && launchCount() == before) delay(10)
            }
            owner.cancelAndJoin()
            runtime.verifyReady()
            assertEquals(maxOf(1, before), launchCount())
        }
    }

    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val runtime = PiAgentRuntime.getInstance(context)

    @Test
    fun startsBundledRuntimeAndExtractsCurrentScript() = runBlocking {
        val security = NetworkSecurityPolicy.getInstance()
        assertTrue(security.isCleartextTrafficPermitted("127.0.0.1"))
        assertFalse(security.isCleartextTrafficPermitted("example.com"))
        runtime.verifyReady()
        val bundled = context.assets.open("pi-runtime/main.js").use { it.readBytes() }
        val installed = File(context.filesDir, "pi-runtime/main.js").readBytes()
        val digest = MessageDigest.getInstance("SHA-256")
        assertArrayEquals(digest.digest(bundled), digest.digest(installed))
    }

    @Test
    fun resolvesEveryOpenCodeGoRouteWithNativeAndCatalogIdentities() = runBlocking {
        for (catalog in listOf(false, true)) {
            val models = OpenCodeGoModelCatalog.supportedModels
            val configurations = models.map { model ->
                PiAgentConfiguration(
                    provider = "opencode-go",
                    model = model.id,
                    catalogContract = if (catalog) PiCatalogModelContract(
                        providerName = "OpenCode Go",
                        npm = "@ai-sdk/openai-compatible",
                        api = "https://opencode.ai/zen/go/v1",
                        toolCall = true,
                        provenance = "provider"
                    ) else null
                )
            }
            val resolutions = runtime.resolveModels(configurations)
            assertEquals(models.size, resolutions.size)
            models.zip(resolutions).forEach { (model, resolution) ->
                if (model.id == "kimi-k2.6") {
                    // Pi 1.0.2 has no metadata for this officially listed route.
                    assertFalse(resolution.supported)
                    assertEquals(if (catalog) "catalog_contract_incomplete" else "pi_model_missing", resolution.reason)
                } else {
                    assertTrue("${model.id}: ${resolution.reason}", resolution.supported)
                    assertEquals(model.id, resolution.model)
                    assertEquals(model.endpointKind.piApi, resolution.api)
                    assertEquals("verified_official_contract", resolution.source)
                }
            }
        }
        val retired = runtime.resolveModels(listOf(PiAgentConfiguration(provider = "opencode-go", model = "glm-5.1")))
        assertFalse(retired.single().supported)
        assertEquals("pi_model_missing", retired.single().reason)
    }

    @Test
    fun resolvesBuiltInProtocolsAndRejectsUnverifiedModel() = runBlocking {
        val cases = listOf(
            Triple("amazon-bedrock", "amazon.nova-2-lite-v1:0", "bedrock-converse-stream"),
            Triple("anthropic", "claude-fable-5", "anthropic-messages"),
            Triple("azure-openai-responses", "gpt-4", "azure-openai-responses"),
            Triple("deepseek", "deepseek-flash", "openai-completions"),
            Triple("google", "deep-research-max-preview-04-2026", "google-generative-ai"),
            Triple("google-vertex", "gemini-2.5-flash", "google-vertex"),
            Triple("mistral", "codestral-latest", "mistral-conversations"),
            Triple("openai", "gpt-4", "openai-responses"),
            Triple("openai-codex", "gpt-6.1-sol", "openai-codex-responses"),
            Triple("radius", "balanced", "pi-messages")
        )
        for (catalog in listOf(false, true)) {
            val resolutions = runtime.resolveModels(cases.map { (provider, model, _) ->
                PiAgentConfiguration(
                    provider = provider,
                    model = model,
                    catalogContract = if (catalog) PiCatalogModelContract(provenance = "provider") else null
                )
            })
            assertEquals(cases.size, resolutions.size)
            cases.zip(resolutions).forEach { (expected, resolution) ->
                assertTrue("${expected.first}/${expected.second}: ${resolution.reason}", resolution.supported)
                assertEquals(expected.first, resolution.provider)
                assertEquals(expected.second, resolution.model)
                assertEquals(expected.third, resolution.api)
                assertTrue(resolution.contextWindow != null)
                assertTrue(resolution.maxTokens != null)
            }
        }
        val unsupported = runtime.resolveModels(listOf(PiAgentConfiguration(provider = "openai", model = "yamabiko-unverified-model")))
        assertFalse(unsupported.single().supported)
        assertEquals("pi_model_missing", unsupported.single().reason)
    }
}
