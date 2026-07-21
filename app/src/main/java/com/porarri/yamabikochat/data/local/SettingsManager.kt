package com.porarri.yamabikochat.data.local

import android.content.Context
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import kotlinx.coroutines.flow.Flow

class SettingsManager private constructor(
    private val context: Context,
    private val chatDao: ChatDao
) {
    companion object {
        @Volatile
        private var INSTANCE: SettingsManager? = null
        
        fun getInstance(context: Context, chatDao: ChatDao): SettingsManager {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: SettingsManager(context.applicationContext, chatDao).also { INSTANCE = it }
            }
        }
    }
    
    private val securePrefs = SecurePreferencesManager.getInstance(context)
    
    suspend fun saveSettings(settings: Settings) {
        chatDao.saveSettings(settings.normalizedForPersistence())
    }
    
    fun getSettings(): Flow<Settings?> {
        return chatDao.getSettings()
    }
    
    suspend fun saveApiKey(provider: String, apiKey: String?): Boolean {        
        return when (provider.uppercase()) {
            "GEMINI" -> securePrefs.storeGeminiApiKey(apiKey)
            "OPENROUTER" -> securePrefs.storeOpenRouterApiKey(apiKey)
            "OPENAI" -> securePrefs.storeOpenAiApiKey(apiKey)
            "MINIMAX" -> securePrefs.storeMiniMaxApiKey(apiKey)
            "ZAI" -> securePrefs.storeZaiApiKey(apiKey)
            "OPENCODE_GO" -> securePrefs.storeOpenCodeGoApiKey(apiKey)
            "CLINEPASS" -> securePrefs.storeClinePassApiKey(apiKey)
            "ALIBABA_CODING_PLAN" -> securePrefs.storeAlibabaCodingPlanApiKey(apiKey)
            else -> false
        }
    }

    fun getApiKey(provider: String): String? {
        return when (provider.uppercase()) {
            "GEMINI" -> securePrefs.getGeminiApiKey()
            "OPENROUTER" -> securePrefs.getOpenRouterApiKey()
            "OPENAI" -> securePrefs.getOpenAiApiKey()
            "MINIMAX" -> securePrefs.getMiniMaxApiKey()
                ?: getOpenAiCompatApiKey("MiniMax")
                ?: getOpenAiCompatApiKey("MiniMax (CN)")
            "ZAI" -> securePrefs.getZaiApiKey()
            "OPENCODE_GO" -> securePrefs.getOpenCodeGoApiKey()
            "CLINEPASS" -> securePrefs.getClinePassApiKey()
            "ALIBABA_CODING_PLAN" -> securePrefs.getAlibabaCodingPlanApiKey()
            else -> null
        }
    }

    fun hasApiKey(provider: String): Boolean {
        return when (provider.uppercase()) {
            "GEMINI" -> securePrefs.hasGeminiApiKey()
            "OPENROUTER" -> securePrefs.hasOpenRouterApiKey()
            "OPENAI" -> securePrefs.hasOpenAiApiKey()
            "MINIMAX" -> securePrefs.hasMiniMaxApiKey() ||
                hasOpenAiCompatApiKey("MiniMax") ||
                hasOpenAiCompatApiKey("MiniMax (CN)")
            "ZAI" -> securePrefs.hasZaiApiKey()
            "OPENCODE_GO" -> securePrefs.hasOpenCodeGoApiKey()
            "CLINEPASS" -> securePrefs.hasClinePassApiKey()
            "ALIBABA_CODING_PLAN" -> securePrefs.hasAlibabaCodingPlanApiKey()
            else -> false
        }
    }

    suspend fun clearApiKey(provider: String) {
        when (provider.uppercase()) {
            "GEMINI" -> securePrefs.clearGeminiApiKey()
            "OPENROUTER" -> securePrefs.clearOpenRouterApiKey()
            "OPENAI" -> securePrefs.clearOpenAiApiKey()
            "MINIMAX" -> {
                securePrefs.clearMiniMaxApiKey()
                clearOpenAiCompatApiKey("MiniMax")
                clearOpenAiCompatApiKey("MiniMax (CN)")
            }
            "ZAI" -> securePrefs.clearZaiApiKey()
            "OPENCODE_GO" -> securePrefs.clearOpenCodeGoApiKey()
            "CLINEPASS" -> securePrefs.clearClinePassApiKey()
            "ALIBABA_CODING_PLAN" -> securePrefs.clearAlibabaCodingPlanApiKey()
        }
    }

    suspend fun saveAlibabaMcpAuthorizationToken(token: String?): Boolean =
        securePrefs.storeAlibabaMcpAuthorizationToken(token)

    fun getAlibabaMcpAuthorizationToken(): String? =
        securePrefs.getAlibabaMcpAuthorizationToken()

    suspend fun clearAlibabaMcpAuthorizationToken() =
        securePrefs.clearAlibabaMcpAuthorizationToken()

    // --- OpenAI-compatible dynamic key helpers ---
    private fun compatAliasFor(name: String): String {
        val slug = name.lowercase().replace(Regex("[^a-z0-9]+"), "_").trim('_')
        return "openai_compat_${slug}_api_key"
    }

    fun getOpenAiCompatApiKey(name: String?): String? {
        val n = name?.takeIf { it.isNotBlank() } ?: return null
        return securePrefs.getCustomApiKey(compatAliasFor(n))
    }

    fun hasOpenAiCompatApiKey(name: String?): Boolean {
        val n = name?.takeIf { it.isNotBlank() } ?: return false
        return securePrefs.hasCustomApiKey(compatAliasFor(n))
    }

    suspend fun saveOpenAiCompatApiKey(name: String, apiKey: String?): Boolean {
        return securePrefs.storeCustomApiKey(compatAliasFor(name), apiKey)
    }

    suspend fun clearOpenAiCompatApiKey(name: String) {
        securePrefs.clearCustomApiKey(compatAliasFor(name))
    }
    
    suspend fun clearAllSecureData() {
        securePrefs.clearAllSecureData()
    }
}
