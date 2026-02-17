package com.porarri.yamabikochat

import android.app.Application
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.api.ApiRepository
import com.porarri.yamabikochat.data.auth.CodexAuthRepository
import com.porarri.yamabikochat.data.auth.GeminiAuthRepository
import com.porarri.yamabikochat.data.attachments.AttachmentStorage
import com.porarri.yamabikochat.data.database.DatabaseRepository
import com.porarri.yamabikochat.data.files.FileProcessingRepository
import com.porarri.yamabikochat.data.local.AppDatabase
import com.porarri.yamabikochat.data.local.SettingsManager
import com.porarri.yamabikochat.data.remote.GeminiCliProvider
import com.porarri.yamabikochat.data.model.ModelRepository
import com.porarri.yamabikochat.data.remote.GeminiProvider
import com.porarri.yamabikochat.data.remote.LiteLlmPricingRepository
import com.porarri.yamabikochat.data.remote.OpenRouterModelService
import com.porarri.yamabikochat.data.remote.OpenRouterProvider
import com.porarri.yamabikochat.data.remote.RetrofitClient
import com.porarri.yamabikochat.data.remote.ZaiProvider
import com.porarri.yamabikochat.data.remote.OpenAiProvider
import com.porarri.yamabikochat.data.remote.CodexResponsesProvider
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        DiagnosticsLogger.initialize(this)
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            databaseRepository.purgeSecretConversations()
        }
    }

    private val database by lazy { AppDatabase.getDatabase(this) }
    private val geminiApiService by lazy { RetrofitClient.geminiInstance }
    private val openRouterApiService by lazy { RetrofitClient.openRouterInstance }
    private val zaiApiService by lazy { RetrofitClient.zaiInstance }
    private val attachmentStorage by lazy { AttachmentStorage(applicationContext) }
    private val chatDao by lazy { database.chatDao() }
    private val databaseRepository by lazy { DatabaseRepository(chatDao) }
    private val modelService by lazy { OpenRouterModelService(openRouterApiService) }
    private val modelRepository by lazy { ModelRepository(modelService) }
    private val pricingRepository by lazy { LiteLlmPricingRepository(RetrofitClient.liteLlmPricingInstance) }
    private val settingsManager by lazy { SettingsManager.getInstance(applicationContext, chatDao) }
    private val codexAuthRepository by lazy { CodexAuthRepository(applicationContext) }
    private val geminiAuthRepository by lazy { GeminiAuthRepository(applicationContext) }
    private val apiRepository by lazy {
        ApiRepository(
            geminiProvider = GeminiProvider(geminiApiService),
            geminiCliProvider = GeminiCliProvider(),
            openRouterProvider = OpenRouterProvider(openRouterApiService),
            openAiProvider = OpenAiProvider { baseUrl -> RetrofitClient.makeOpenAiInstance(baseUrl) },
            codexResponsesProvider = CodexResponsesProvider(applicationContext),
            zaiProvider = ZaiProvider(zaiApiService),
            settingsManager = settingsManager,
            codexAuthRepository = codexAuthRepository,
            geminiAuthRepository = geminiAuthRepository,
            modelRepository = modelRepository,
            settingsProvider = { databaseRepository.getLatestSettings() }
        )
    }
    private val fileRepository by lazy {
        FileProcessingRepository(applicationContext, attachmentStorage)
    }
    val repository by lazy {
        ChatRepository(
            databaseRepository = databaseRepository,
            apiRepository = apiRepository,
            fileProcessingRepository = fileRepository,
            modelRepository = modelRepository,
            codexAuthRepository = codexAuthRepository,
            geminiAuthRepository = geminiAuthRepository,
            pricingRepository = pricingRepository
        )
    }
    val viewModelFactory by lazy { ViewModelFactory(repository) }
}
