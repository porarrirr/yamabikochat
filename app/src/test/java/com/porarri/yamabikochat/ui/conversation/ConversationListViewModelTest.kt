package com.porarri.yamabikochat.ui.conversation

import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.local.ConversationSearchResult
import androidx.lifecycle.ViewModelStore
import io.mockk.clearMocks
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class ConversationListViewModelTest {

    private val dispatcher = StandardTestDispatcher()
    private lateinit var repository: ChatRepository
    private lateinit var viewModelStore: ViewModelStore

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        repository = mockk()
        every { repository.getConversationListEntries() } returns MutableStateFlow(emptyList())
        every { repository.getProjects() } returns MutableStateFlow(emptyList())
        every { repository.searchMessages(any(), any(), any()) } returns flowOf(emptyList())
        viewModelStore = ViewModelStore()
    }

    @After
    fun tearDown() {
        viewModelStore.clear()
        Dispatchers.resetMain()
    }

    @Test
    fun searchMessagesPassesSelectedProject() = runTest {
        val viewModel = makeViewModel()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.searchResults.collect {}
        }

        viewModel.selectProject(42L)
        viewModel.updateSearchQuery("needle")
        advanceTimeBy(250)
        advanceUntilIdle()

        verify { repository.searchMessages("needle", 200, 42L) }
    }

    @Test
    fun searchDebouncesTypingAndBlankQueryClearsResults() = runTest {
        val result = searchResult(1, "needle")
        every { repository.searchMessages("needle", 200, null) } returns flowOf(listOf(result))
        val viewModel = makeViewModel()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.searchResults.collect {}
        }

        viewModel.updateSearchQuery("nee")
        runCurrent()
        advanceTimeBy(100)
        viewModel.updateSearchQuery("  needle  ")
        runCurrent()
        advanceTimeBy(199)
        runCurrent()
        verify(exactly = 0) { repository.searchMessages(any(), any(), any()) }
        advanceTimeBy(1)
        runCurrent()
        verify(exactly = 1) { repository.searchMessages("needle", 200, null) }
        assertEquals(listOf(result), viewModel.searchResults.value)

        clearMocks(repository, answers = false)
        viewModel.updateSearchQuery(" \n ")
        advanceUntilIdle()
        assertTrue(viewModel.searchResults.value.isEmpty())
        verify(exactly = 0) { repository.searchMessages(any(), any(), any()) }
    }

    @Test
    fun switchingProjectReplacesResultsAndStopsObservingPreviousSearch() = runTest {
        val previous = MutableStateFlow(listOf(searchResult(1, "first project")))
        val selected = listOf(searchResult(2, "selected project"))
        every { repository.searchMessages("needle", 200, 1L) } returns previous
        every { repository.searchMessages("needle", 200, 2L) } returns flowOf(selected)
        val viewModel = makeViewModel()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.searchResults.collect {}
        }
        viewModel.selectProject(1L)
        viewModel.updateSearchQuery("needle")
        advanceUntilIdle()
        assertEquals(previous.value, viewModel.searchResults.value)

        viewModel.selectProject(2L)
        runCurrent()
        assertEquals(selected, viewModel.searchResults.value)

        previous.value = listOf(searchResult(3, "late result from previous project"))
        runCurrent()
        assertEquals(selected, viewModel.searchResults.value)
    }

    private fun makeViewModel() = ConversationListViewModel(repository).also {
        viewModelStore.put("conversation-list", it)
    }

    private fun searchResult(id: Long, snippet: String) = ConversationSearchResult(
        conversationId = id,
        conversationTitle = "Conversation $id",
        source = "CHAT",
        messageId = id,
        timestamp = id,
        role = "user",
        matchedField = "CHAT",
        snippet = snippet
    )
}
