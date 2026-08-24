package com.porarri.yamabikochat

import android.app.Application
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.attachments.AttachmentStorage
import com.porarri.yamabikochat.data.auth.CodexAuthRepository
import com.porarri.yamabikochat.data.auth.SuperGrokAuthRepository
import com.porarri.yamabikochat.data.database.DatabaseRepository
import com.porarri.yamabikochat.data.files.FileProcessingRepository
import com.porarri.yamabikochat.data.local.AppDatabase
import com.porarri.yamabikochat.data.model.ModelRepository
import com.porarri.yamabikochat.data.modelsdev.ModelsDevCatalogRepository
import com.porarri.yamabikochat.data.modelsdev.ModelsDevReasoningPreference
import com.porarri.yamabikochat.data.remote.LiteLlmPricingRepository
import com.porarri.yamabikochat.data.remote.OpenRouterModelService
import com.porarri.yamabikochat.data.remote.RetrofitClient
import com.porarri.yamabikochat.data.repositories.ProviderGateway
import com.porarri.yamabikochat.data.repositories.ProviderRequestSettingsResolver
import com.porarri.yamabikochat.data.skills.AgentSkillRepository
import com.porarri.yamabikochat.data.skills.AgentSkillTools
import com.porarri.yamabikochat.data.tools.LocalToolRegistry
import com.porarri.yamabikochat.data.tools.editor.EditorWorkspaceStore
import com.porarri.yamabikochat.data.tools.editor.StrReplaceEditorTool
import com.porarri.yamabikochat.data.tools.search.FetchUrlTool
import com.porarri.yamabikochat.data.tools.search.WebSearchTool
import com.porarri.yamabikochat.pi.PiAgentRuntime
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        DiagnosticsLogger.initialize(this)
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            val secretIds = databaseRepository.getSecretConversationIds()
            databaseRepository.purgeSecretConversations()
            secretIds.forEach { editorWorkspaceStore.delete(it.toString()) }
            editorWorkspaceStore.deleteOrphans(databaseRepository.getAllConversationIds().map(Long::toString))
        }
    }

    private val database by lazy { AppDatabase.getDatabase(this) }
    private val openRouterApiService by lazy { RetrofitClient.openRouterInstance }
    private val attachmentStorage by lazy { AttachmentStorage(applicationContext) }
    private val editorWorkspaceStore by lazy { EditorWorkspaceStore.forContext(applicationContext) }
    private val editorTool by lazy { StrReplaceEditorTool(editorWorkspaceStore, attachmentStorage) }
    val agentSkillRepository by lazy { AgentSkillRepository(applicationContext) }
    private val chatDao by lazy { database.chatDao() }
    private val databaseRepository by lazy { DatabaseRepository(chatDao) }
    private val modelService by lazy { OpenRouterModelService(openRouterApiService) }
    private val modelRepository by lazy { ModelRepository(modelService) }
    private val modelsDevCatalogRepository by lazy { ModelsDevCatalogRepository(applicationContext) }
    private val pricingRepository by lazy { LiteLlmPricingRepository(RetrofitClient.liteLlmPricingInstance) }
    private val securePreferences by lazy { SecurePreferencesManager.getInstance(applicationContext) }
    private val piRuntime by lazy { PiAgentRuntime.getInstance(applicationContext) }
    private val codexAuthRepository by lazy { CodexAuthRepository(applicationContext, securePreferences, piRuntime) }
    private val superGrokAuthRepository by lazy { SuperGrokAuthRepository(applicationContext, securePreferences, piRuntime) }

    private val providerGateway by lazy {
        // Recreate registry per request so AgentSkill enable/disable is reflected immediately.
        // WebSearch/FetchUrl are stateless; reuse of AgentSkill executors captures latest enabledSkills.
        val makeLocalTools = {
            LocalToolRegistry(
                listOf(WebSearchTool(), FetchUrlTool(), editorTool) + AgentSkillTools.executors(agentSkillRepository)
            )
        }
        ProviderGateway(
            settingsProvider = { databaseRepository.getLatestSettings() },
            securePreferences = securePreferences,
            codexAuthRepository = codexAuthRepository,
            superGrokAuthRepository = superGrokAuthRepository,
            modelsDevCatalogRepository = modelsDevCatalogRepository,
            openRouterModelService = modelService,
            localTools = makeLocalTools(),
            localToolFactory = makeLocalTools,
            piRuntime = piRuntime
        )
    }

    private val requestSettingsResolver by lazy {
        ProviderRequestSettingsResolver(
            modelService = modelService,
            skillRepository = agentSkillRepository,
            modelsDevCatalogRepository = modelsDevCatalogRepository,
            localToolRegistry = LocalToolRegistry(listOf(WebSearchTool(), FetchUrlTool(), editorTool)),
            modelsDevReasoningEffort = { providerId, modelId ->
                securePreferences.getModelsDevField(
                    providerId,
                    ModelsDevReasoningPreference.fieldName(modelId)
                )
            }
        )
    }

    private val fileRepository by lazy {
        FileProcessingRepository(applicationContext, attachmentStorage)
    }

    val repository by lazy {
        ChatRepository(
            databaseRepository = databaseRepository,
            providerGateway = providerGateway,
            requestSettingsResolver = requestSettingsResolver,
            fileProcessingRepository = fileRepository,
            modelRepository = modelRepository,
            codexAuthRepository = codexAuthRepository,
            superGrokAuthRepository = superGrokAuthRepository,
            pricingRepository = pricingRepository,
            modelsDevCatalogRepository = modelsDevCatalogRepository,
            agentSkillRepository = agentSkillRepository,
            securePreferences = securePreferences,
            editorWorkspaceStore = editorWorkspaceStore
        )
    }

    val viewModelFactory by lazy { ViewModelFactory(repository) }
}
