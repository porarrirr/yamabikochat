package com.porarri.yamabikochat.data.tools

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ToolCallingOrchestratorTest {

    @Test
    fun runsToolThenReturnsFinalText() = runBlocking {
        val registry = LocalToolRegistry(
            listOf(
                object : LocalToolExecutor {
                    override val definition = ToolDefinition(
                        name = "echo",
                        description = "echo",
                        parametersJSON = """{"type":"object","properties":{"q":{"type":"string"}},"required":["q"]}"""
                    )

                    override suspend fun execute(call: ToolCall): ToolResult {
                        return ToolResult(
                            callId = call.id,
                            name = call.name,
                            content = """{"ok":true,"echo":${call.argumentsJSON}}"""
                        )
                    }
                }
            )
        )

        var invokeCount = 0
        val orchestrator = ToolCallingOrchestrator(registry = registry, maxRounds = 3)
        val outcome = orchestrator.run(
            request = ToolTurnRequest(
                messages = mutableListOf(ToolTurnMessage(role = "user", content = "hi"))
            ),
            invoke = { _, _ ->
                invokeCount += 1
                if (invokeCount == 1) {
                    ToolTurnResponse(
                        text = "",
                        toolCalls = listOf(
                            ToolCall(
                                id = "call-0-echo",
                                name = "echo",
                                argumentsJSON = """{"q":"hello"}"""
                            )
                        )
                    )
                } else {
                    ToolTurnResponse(text = "done")
                }
            }
        )

        assertEquals(2, invokeCount)
        assertEquals("done", outcome.response.text)
        assertEquals(1, outcome.activities.size)
        assertEquals(ToolActivityStep.Status.completed, outcome.activities.single().status)
        assertTrue(outcome.rounds >= 2)
    }

    @Test
    fun suppressesDuplicateToolCalls() = runBlocking {
        val registry = LocalToolRegistry(
            listOf(
                object : LocalToolExecutor {
                    override val definition = ToolDefinition(
                        name = "echo",
                        description = "echo",
                        parametersJSON = """{"type":"object"}"""
                    )
                    override suspend fun execute(call: ToolCall): ToolResult {
                        return ToolResult(callId = call.id, name = call.name, content = """{"ok":true}""")
                    }
                }
            )
        )

        var executeViaRegistry = 0
        val countingRegistry = LocalToolRegistry(
            listOf(
                object : LocalToolExecutor {
                    override val definition = registry.definitions.single()
                    override suspend fun execute(call: ToolCall): ToolResult {
                        executeViaRegistry += 1
                        return registry.execute(call)
                    }
                }
            )
        )

        var invokeCount = 0
        val orchestrator = ToolCallingOrchestrator(registry = countingRegistry, maxRounds = 3)
        orchestrator.run(
            request = ToolTurnRequest(
                messages = mutableListOf(ToolTurnMessage(role = "user", content = "hi"))
            ),
            invoke = { _, _ ->
                invokeCount += 1
                if (invokeCount == 1) {
                    val call = ToolCall(id = "a", name = "echo", argumentsJSON = """{"q":"x"}""")
                    ToolTurnResponse(text = "", toolCalls = listOf(call, call.copy(id = "b")))
                } else {
                    ToolTurnResponse(text = "final")
                }
            }
        )

        assertEquals(1, executeViaRegistry)
    }
}
