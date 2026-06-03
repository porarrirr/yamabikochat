package com.porarri.yamabikochat.ui.conversation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.local.ChatProject
import com.porarri.yamabikochat.data.local.Conversation
import com.porarri.yamabikochat.data.local.ConversationListEntry
import com.porarri.yamabikochat.data.local.ConversationSearchResult
import com.porarri.yamabikochat.data.local.ProjectListEntry
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.utils.ModelUtils
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first

@OptIn(FlowPreview::class, ExperimentalCoroutinesApi::class)
class ConversationListViewModel(private val repository: ChatRepository) : ViewModel() {

    private val allConversationEntries: StateFlow<List<ConversationListEntry>> =
        repository.getConversationListEntries()
            .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    private val _selectedProjectId = MutableStateFlow<Long?>(null)
    val selectedProjectId = _selectedProjectId.asStateFlow()

    val projects: StateFlow<List<ProjectListEntry>> =
        repository.getProjects()
            .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    val conversationEntries: StateFlow<List<ConversationListEntry>> =
        combine(allConversationEntries, _selectedProjectId) { entries, selectedProjectId ->
            if (selectedProjectId == null) entries else entries.filter { it.projectId == selectedProjectId }
        }
            .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    private val _searchQuery = MutableStateFlow("")
    val searchQuery = _searchQuery.asStateFlow()

    val searchResults: StateFlow<List<ConversationSearchResult>> =
        combine(
            _searchQuery
                .map { it.trim() }
                .debounce(200)
                .distinctUntilChanged(),
            _selectedProjectId
        ) { query, selectedProjectId -> query to selectedProjectId }
            .flatMapLatest { (query, selectedProjectId) ->
                if (query.isBlank()) {
                    flowOf(emptyList())
                } else {
                    repository.searchMessages(query, projectId = selectedProjectId)
                }
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun updateSearchQuery(query: String) {
        _searchQuery.value = query
    }

    fun selectProject(projectId: Long?) {
        _selectedProjectId.value = projectId
    }

    suspend fun createNewConversation(
        title: String,
        model: String? = null,
        systemPrompt: String? = null,
        projectId: Long? = _selectedProjectId.value,
        secret: Boolean = false
    ): Long {
        if (title == "New Chat" && !secret) {
            repository.findLatestEmptyConversationByTitle(title, projectId)?.id?.let { return it }
        }
        val currentSettings = repository.getSettings().first() ?: Settings()
        val resolvedModel = model?.takeIf { it.isNotBlank() } ?: currentSettings.getCurrentModel()
        val resolvedProvider = if (model.isNullOrBlank()) {
            currentSettings.apiProvider
        } else {
            ModelUtils.getProviderFromModel(resolvedModel)
        }
        val resolvedSystemPrompt = systemPrompt ?: resolveSystemPromptForProject(projectId, currentSettings.systemPrompt)

        return repository.upsertConversation(
            Conversation(
                title = title,
                model = resolvedModel,
                systemPrompt = resolvedSystemPrompt,
                apiProvider = resolvedProvider,
                isSecret = secret,
                projectId = projectId
            )
        )
    }

    suspend fun createProject(title: String, instructions: String?): Long {
        val normalizedTitle = title.trim()
        require(normalizedTitle.isNotBlank()) { "Project title must not be blank" }
        val now = System.currentTimeMillis()
        val id = repository.upsertProject(
            ChatProject(
                title = normalizedTitle,
                instructions = instructions?.trim()?.takeIf { it.isNotBlank() },
                createdAtMs = now,
                updatedAtMs = now
            )
        )
        _selectedProjectId.value = id
        return id
    }

    fun assignConversation(conversationId: Long, projectId: Long?) {
        viewModelScope.launch {
            repository.assignConversationToProject(conversationId, projectId)
        }
    }

    fun deleteProject(projectId: Long, deleteConversations: Boolean) {
        viewModelScope.launch {
            repository.deleteProject(projectId, deleteConversations)
            if (_selectedProjectId.value == projectId) {
                _selectedProjectId.value = null
            }
        }
    }

    suspend fun projectConversationCount(projectId: Long): Int =
        repository.countConversationsInProject(projectId)

    fun deleteConversation(id: Long) {
        viewModelScope.launch {
            repository.deleteConversationById(id)
        }
    }

    private suspend fun resolveSystemPromptForProject(projectId: Long?, fallbackPrompt: String?): String? {
        if (projectId == null) return fallbackPrompt
        val projectPrompt = repository.getProjectById(projectId)
            ?.instructions
            ?.trim()
            ?.takeIf { it.isNotBlank() }
        return projectPrompt ?: fallbackPrompt
    }
}
