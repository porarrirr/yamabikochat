package com.porarri.yamabikochat.ui.conversation

import com.porarri.yamabikochat.data.ChatRepository
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
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ConversationListViewModelTest {

    private val dispatcher = StandardTestDispatcher()
    private lateinit var repository: ChatRepository

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        repository = mockk()
        every { repository.getConversationListEntries() } returns MutableStateFlow(emptyList())
        every { repository.getProjects() } returns MutableStateFlow(emptyList())
        every { repository.searchMessages(any(), any(), any()) } returns flowOf(emptyList())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun searchMessagesPassesSelectedProject() = runTest {
        val viewModel = ConversationListViewModel(repository)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.searchResults.collect {}
        }

        viewModel.selectProject(42L)
        viewModel.updateSearchQuery("needle")
        advanceTimeBy(250)
        advanceUntilIdle()

        verify { repository.searchMessages("needle", 200, 42L) }
    }
}
