package com.porarri.yamabikochat.ui.conversation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.local.Conversation
import com.porarri.yamabikochat.data.local.ConversationListEntry
import com.porarri.yamabikochat.data.local.ConversationSearchResult
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.utils.ModelUtils
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
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

    val conversationEntries: StateFlow<List<ConversationListEntry>> =
        repository.getConversationListEntries()
            .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    private val _searchQuery = MutableStateFlow("")
    val searchQuery = _searchQuery.asStateFlow()

    val searchResults: StateFlow<List<ConversationSearchResult>> =
        _searchQuery
            .map { it.trim() }
            .debounce(200)
            .distinctUntilChanged()
            .flatMapLatest { query ->
                if (query.isBlank()) {
                    flowOf(emptyList())
                } else {
                    repository.searchMessages(query)
                }
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun updateSearchQuery(query: String) {
        _searchQuery.value = query
    }

    suspend fun createNewConversation(title: String, model: String? = null, systemPrompt: String? = null): Long {
        val currentSettings = repository.getSettings().first() ?: Settings()
        val resolvedModel = model?.takeIf { it.isNotBlank() } ?: currentSettings.getCurrentModel()
        val resolvedProvider = if (model.isNullOrBlank()) {
            currentSettings.apiProvider
        } else {
            ModelUtils.getProviderFromModel(resolvedModel)
        }
        val resolvedSystemPrompt = systemPrompt ?: currentSettings.systemPrompt

        return repository.upsertConversation(
            Conversation(
                title = title,
                model = resolvedModel,
                systemPrompt = resolvedSystemPrompt,
                apiProvider = resolvedProvider
            )
        )
    }

    fun deleteConversation(id: Long) {
        viewModelScope.launch {
            repository.deleteConversationById(id)
        }
    }
}
