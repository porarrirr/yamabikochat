package com.porarri.yamabikochat.utils

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import javax.crypto.AEADBadTagException

class SecurePreferencesManager private constructor(private val context: Context) {

    companion object {
        private const val TAG = "SecurePreferencesManager"

        @Volatile
        private var INSTANCE: SecurePreferencesManager? = null

        fun getInstance(context: Context): SecurePreferencesManager {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: SecurePreferencesManager(context.applicationContext).also { INSTANCE = it }
            }
        }

        private const val SECURE_PREFS_NAME = "secure_app_prefs"
        private const val KEY_GEMINI_API_KEY = "gemini_api_key"
        private const val KEY_OPENROUTER_API_KEY = "openrouter_api_key"
        private const val KEY_OPENAI_API_KEY = "openai_api_key"
        private const val KEY_MINIMAX_API_KEY = "minimax_api_key"
        private const val KEY_ZAI_API_KEY = "zai_api_key"
        private const val KEY_OPENCODE_GO_API_KEY = "opencode_go_api_key"
        private const val KEY_ALIBABA_CODING_PLAN_API_KEY = "alibaba_coding_plan_api_key"
        private const val KEY_ALIBABA_MCP_AUTH_TOKEN = "alibaba_mcp_authorization_token"
        private const val KEY_CODEX_AUTH_JSON = "codex_auth_json"
        private const val KEY_CODEX_USER_AGENT_PRESET = "codex_user_agent_preset"
        private const val KEY_CODEX_USER_AGENT_CLI_VERSION = "codex_user_agent_cli_version"
    }

    private val encryptedPrefs: SharedPreferences? by lazy {
        try {
            val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
            EncryptedSharedPreferences.create(
                SECURE_PREFS_NAME,
                masterKeyAlias,
                context,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        } catch (e: Exception) {
            DiagnosticsLogger.log("EncryptedSharedPreferences init failed", e)
            Log.e(TAG, "暗号化ストレージの初期化に失敗しました: ${e.message}", e)
            null
        }
    }

    private val fallbackPrefs: SharedPreferences by lazy {
        context.getSharedPreferences("${SECURE_PREFS_NAME}_fallback", Context.MODE_PRIVATE)
    }

    @Volatile
    private var fallbackLogged = false

    fun isEncryptionAvailable(): Boolean = encryptedPrefs != null

    private fun logFallbackOnce() {
        if (fallbackLogged) return
        fallbackLogged = true
        DiagnosticsLogger.log("Encrypted storage unavailable; using fallback SharedPreferences (API keys will NOT be encrypted).")
        Log.w(TAG, "暗号化ストレージが利用できないため、フォールバックストレージを使用します。")
    }

    private fun storeString(key: String, value: String?, label: String): Boolean {
        val encrypted = encryptedPrefs
        if (encrypted != null) {
            try {
                val editor = encrypted.edit()
                if (value == null) editor.remove(key) else editor.putString(key, value)
                editor.apply()
                runCatching { fallbackPrefs.edit().remove(key).apply() }
                return true
            } catch (e: Exception) {
                DiagnosticsLogger.log("$label store failed (encrypted); falling back", e)
                Log.w(TAG, "$label の保存に失敗（暗号化）: ${e.message}", e)
            }
        } else {
            logFallbackOnce()
        }

        return try {
            val editor = fallbackPrefs.edit()
            if (value == null) editor.remove(key) else editor.putString(key, value)
            editor.apply()
            true
        } catch (e: Exception) {
            DiagnosticsLogger.log("$label store failed (fallback)", e)
            Log.w(TAG, "$label の保存に失敗（フォールバック）: ${e.message}", e)
            false
        }
    }

    private fun clearEncryptedKey(key: String) {
        val encrypted = encryptedPrefs ?: return
        runCatching { encrypted.edit().remove(key).apply() }
    }

    private fun readString(key: String, label: String): String? {
        val encrypted = encryptedPrefs
        if (encrypted != null) {
            try {
                val value = encrypted.getString(key, null)
                if (!value.isNullOrEmpty()) return value
            } catch (e: AEADBadTagException) {
                DiagnosticsLogger.log("$label decrypt failed (clearing encrypted key)", e)
                Log.w(TAG, "$label の復号に失敗（キーをクリア）: ${e.message}", e)
                clearEncryptedKey(key)
            } catch (e: Exception) {
                DiagnosticsLogger.log("$label read failed (encrypted)", e)
                Log.w(TAG, "$label の取得に失敗（暗号化）: ${e.message}", e)
            }
        } else {
            logFallbackOnce()
        }

        val fallbackValue = runCatching { fallbackPrefs.getString(key, null) }.getOrNull()
        if (encrypted != null && !fallbackValue.isNullOrEmpty()) {
            runCatching {
                encrypted.edit().putString(key, fallbackValue).apply()
                fallbackPrefs.edit().remove(key).apply()
            }.onFailure { e ->
                DiagnosticsLogger.log("$label migration to encrypted failed", e)
            }
        }
        return fallbackValue
    }

    private fun hasString(key: String, label: String): Boolean {
        val encrypted = encryptedPrefs
        if (encrypted != null) {
            try {
                return !encrypted.getString(key, null).isNullOrEmpty()
            } catch (e: AEADBadTagException) {
                DiagnosticsLogger.log("$label decrypt failed during has() (clearing encrypted key)", e)
                clearEncryptedKey(key)
            } catch (e: Exception) {
                DiagnosticsLogger.log("$label has() failed (encrypted)", e)
            }
        } else {
            logFallbackOnce()
        }

        return runCatching { !fallbackPrefs.getString(key, null).isNullOrEmpty() }.getOrDefault(false)
    }

    private fun clearKey(key: String, label: String) {
        runCatching { encryptedPrefs?.edit()?.remove(key)?.apply() }.onFailure { e ->
            DiagnosticsLogger.log("$label clear failed (encrypted)", e)
        }
        runCatching { fallbackPrefs.edit().remove(key).apply() }.onFailure { e ->
            DiagnosticsLogger.log("$label clear failed (fallback)", e)
        }
    }

    fun storeGeminiApiKey(apiKey: String?): Boolean =
        storeString(KEY_GEMINI_API_KEY, apiKey, "Gemini APIキー")

    fun hasGeminiApiKey(): Boolean =
        hasString(KEY_GEMINI_API_KEY, "Gemini APIキー")

    fun getGeminiApiKey(): String? =
        readString(KEY_GEMINI_API_KEY, "Gemini APIキー")

    fun clearGeminiApiKey() =
        clearKey(KEY_GEMINI_API_KEY, "Gemini APIキー")

    fun storeOpenRouterApiKey(apiKey: String?): Boolean =
        storeString(KEY_OPENROUTER_API_KEY, apiKey, "OpenRouter APIキー")

    fun hasOpenRouterApiKey(): Boolean =
        hasString(KEY_OPENROUTER_API_KEY, "OpenRouter APIキー")

    fun getOpenRouterApiKey(): String? =
        readString(KEY_OPENROUTER_API_KEY, "OpenRouter APIキー")

    fun clearOpenRouterApiKey() =
        clearKey(KEY_OPENROUTER_API_KEY, "OpenRouter APIキー")

    fun storeOpenAiApiKey(apiKey: String?): Boolean =
        storeString(KEY_OPENAI_API_KEY, apiKey, "OpenAI APIキー")

    fun hasOpenAiApiKey(): Boolean =
        hasString(KEY_OPENAI_API_KEY, "OpenAI APIキー")

    fun getOpenAiApiKey(): String? =
        readString(KEY_OPENAI_API_KEY, "OpenAI APIキー")

    fun clearOpenAiApiKey() =
        clearKey(KEY_OPENAI_API_KEY, "OpenAI APIキー")

    fun storeMiniMaxApiKey(apiKey: String?): Boolean =
        storeString(KEY_MINIMAX_API_KEY, apiKey, "MiniMax APIキー")

    fun hasMiniMaxApiKey(): Boolean =
        hasString(KEY_MINIMAX_API_KEY, "MiniMax APIキー")

    fun getMiniMaxApiKey(): String? =
        readString(KEY_MINIMAX_API_KEY, "MiniMax APIキー")

    fun clearMiniMaxApiKey() =
        clearKey(KEY_MINIMAX_API_KEY, "MiniMax APIキー")

    fun storeZaiApiKey(apiKey: String?): Boolean =
        storeString(KEY_ZAI_API_KEY, apiKey, "Z.ai APIキー")

    fun hasZaiApiKey(): Boolean =
        hasString(KEY_ZAI_API_KEY, "Z.ai APIキー")

    fun getZaiApiKey(): String? =
        readString(KEY_ZAI_API_KEY, "Z.ai APIキー")

    fun clearZaiApiKey() =
        clearKey(KEY_ZAI_API_KEY, "Z.ai APIキー")

    fun storeOpenCodeGoApiKey(apiKey: String?): Boolean =
        storeString(KEY_OPENCODE_GO_API_KEY, apiKey, "OpenCode Go APIキー")

    fun hasOpenCodeGoApiKey(): Boolean =
        hasString(KEY_OPENCODE_GO_API_KEY, "OpenCode Go APIキー")

    fun getOpenCodeGoApiKey(): String? =
        readString(KEY_OPENCODE_GO_API_KEY, "OpenCode Go APIキー")

    fun clearOpenCodeGoApiKey() =
        clearKey(KEY_OPENCODE_GO_API_KEY, "OpenCode Go APIキー")

    fun storeAlibabaCodingPlanApiKey(apiKey: String?): Boolean =
        storeString(KEY_ALIBABA_CODING_PLAN_API_KEY, apiKey, "Alibaba Coding Plan APIキー")

    fun hasAlibabaCodingPlanApiKey(): Boolean =
        hasString(KEY_ALIBABA_CODING_PLAN_API_KEY, "Alibaba Coding Plan APIキー")

    fun getAlibabaCodingPlanApiKey(): String? =
        readString(KEY_ALIBABA_CODING_PLAN_API_KEY, "Alibaba Coding Plan APIキー")

    fun clearAlibabaCodingPlanApiKey() =
        clearKey(KEY_ALIBABA_CODING_PLAN_API_KEY, "Alibaba Coding Plan APIキー")

    fun storeAlibabaMcpAuthorizationToken(token: String?): Boolean =
        storeString(KEY_ALIBABA_MCP_AUTH_TOKEN, token, "Alibaba MCP authorization token")

    fun getAlibabaMcpAuthorizationToken(): String? =
        readString(KEY_ALIBABA_MCP_AUTH_TOKEN, "Alibaba MCP authorization token")

    fun hasAlibabaMcpAuthorizationToken(): Boolean =
        hasString(KEY_ALIBABA_MCP_AUTH_TOKEN, "Alibaba MCP authorization token")

    fun clearAlibabaMcpAuthorizationToken() =
        clearKey(KEY_ALIBABA_MCP_AUTH_TOKEN, "Alibaba MCP authorization token")

    fun storeCodexAuthJson(payload: String?): Boolean =
        storeString(KEY_CODEX_AUTH_JSON, payload, "Codex Auth")

    fun getCodexAuthJson(): String? =
        readString(KEY_CODEX_AUTH_JSON, "Codex Auth")

    fun hasCodexAuthJson(): Boolean =
        hasString(KEY_CODEX_AUTH_JSON, "Codex Auth")

    fun clearCodexAuthJson() =
        clearKey(KEY_CODEX_AUTH_JSON, "Codex Auth")

    fun storeCodexUserAgentPreset(preset: String?): Boolean =
        storeString(KEY_CODEX_USER_AGENT_PRESET, preset, "Codex User-Agent preset")

    fun getCodexUserAgentPreset(): String? =
        readString(KEY_CODEX_USER_AGENT_PRESET, "Codex User-Agent preset")

    fun storeCodexUserAgentCliVersion(version: String?): Boolean =
        storeString(KEY_CODEX_USER_AGENT_CLI_VERSION, version, "Codex User-Agent CLI version")

    fun getCodexUserAgentCliVersion(): String? =
        readString(KEY_CODEX_USER_AGENT_CLI_VERSION, "Codex User-Agent CLI version")

    // Generic custom alias helpers for OpenAI-compatible presets
    fun storeCustomApiKey(alias: String, apiKey: String?): Boolean =
        storeString(alias, apiKey, "Custom APIキー($alias)")

    fun getCustomApiKey(alias: String): String? =
        readString(alias, "Custom APIキー($alias)")

    fun hasCustomApiKey(alias: String): Boolean =
        hasString(alias, "Custom APIキー($alias)")

    fun clearCustomApiKey(alias: String) =
        clearKey(alias, "Custom APIキー($alias)")

    fun clearAllSecureData() {
        runCatching {
            encryptedPrefs?.edit()?.clear()?.apply()
        }.onFailure { e ->
            DiagnosticsLogger.log("Secure data clear failed (encrypted)", e)
        }
        runCatching { fallbackPrefs.edit().clear().apply() }.onFailure { e ->
            DiagnosticsLogger.log("Secure data clear failed (fallback)", e)
        }
    }
}
