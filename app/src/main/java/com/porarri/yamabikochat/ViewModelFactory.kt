package com.porarri.yamabikochat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewmodel.CreationExtras
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.ui.chat.ChatViewModel
import com.porarri.yamabikochat.ui.conversation.ConversationListViewModel
import com.porarri.yamabikochat.ui.settings.SettingsViewModel

class ViewModelFactory(private val repository: ChatRepository) : ViewModelProvider.Factory {
    override fun <T : ViewModel> create(modelClass: Class<T>, extras: CreationExtras): T {
        val savedStateHandle = extras.createSavedStateHandle()
        return when {
            modelClass.isAssignableFrom(SettingsViewModel::class.java) -> {
                @Suppress("UNCHECKED_CAST")
                SettingsViewModel(repository) as T
            }
            modelClass.isAssignableFrom(ConversationListViewModel::class.java) -> {
                @Suppress("UNCHECKED_CAST")
                ConversationListViewModel(repository) as T
            }
            modelClass.isAssignableFrom(ChatViewModel::class.java) -> {
                @Suppress("UNCHECKED_CAST")
                ChatViewModel(repository, savedStateHandle) as T
            }
            else -> throw IllegalArgumentException("Unknown ViewModel class")
        }
    }
}
