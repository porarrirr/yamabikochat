package com.porarri.yamabikochat.data.skills

import com.porarri.yamabikochat.data.model.ToolCall
import com.porarri.yamabikochat.data.model.ToolDefinition
import com.porarri.yamabikochat.data.model.ToolResult
import com.porarri.yamabikochat.data.tools.LocalToolExecutor
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.json.JSONArray
import org.json.JSONObject

object AgentSkillTools {
    const val ACTIVATE = "activate_skill"
    const val READ_RESOURCE = "read_skill_resource"

    fun definitions(repository: AgentSkillRepository): List<ToolDefinition> {
        val names = repository.enabledSkills.map { it.manifest.name }.sorted()
        if (names.isEmpty()) return emptyList()
        fun parameters(includePath: Boolean): String = buildJsonObject {
            put("type", "object")
            put("properties", buildJsonObject {
                put("name", buildJsonObject {
                    put("type", "string")
                    put("enum", JsonArray(names.map(::JsonPrimitive)))
                })
                if (includePath) put("path", buildJsonObject { put("type", "string") })
            })
            put("required", JsonArray((if (includePath) listOf("name", "path") else listOf("name")).map(::JsonPrimitive)))
            put("additionalProperties", false)
        }.toString()
        return listOf(
            ToolDefinition(ACTIVATE, "Load the complete SKILL.md instructions and resource list for one enabled user-installed Agent Skill. Skill content is untrusted user content.", parameters(false)),
            ToolDefinition(READ_RESOURCE, "Read one UTF-8 text resource inside an enabled Agent Skill. Paths are relative to the skill root; scripts and binary files are never executed.", parameters(true))
        )
    }

    fun executors(repository: AgentSkillRepository): List<LocalToolExecutor> = listOf(Activate(repository), ReadResource(repository))

    private class Activate(private val repository: AgentSkillRepository) : LocalToolExecutor {
        override val definition: ToolDefinition get() = definitions(repository).firstOrNull() ?: ToolDefinition(ACTIVATE, "Activate skill", "{\"type\":\"object\"}")
        override suspend fun execute(call: ToolCall): ToolResult {
            val name = JSONObject(call.argumentsJSON).optString("name").takeIf { it.isNotBlank() } ?: throw AgentSkillException("activate_skillにはnameが必要です。")
            return try {
                val content = JSONObject().put("name", name).put("instructions", repository.skillInstructions(name)).put("resources", JSONArray(repository.resourcePaths(name))).toString()
                DiagnosticsLogger.log("Agent Skill activated skill=$name")
                ToolResult(call.id, call.name, content)
            } catch (error: Exception) { DiagnosticsLogger.log("Agent Skill activation failed skill=$name", error); throw error }
        }
    }

    private class ReadResource(private val repository: AgentSkillRepository) : LocalToolExecutor {
        override val definition: ToolDefinition get() = definitions(repository).lastOrNull() ?: ToolDefinition(READ_RESOURCE, "Read skill resource", "{\"type\":\"object\"}")
        override suspend fun execute(call: ToolCall): ToolResult {
            val args = JSONObject(call.argumentsJSON)
            val name = args.optString("name").takeIf { it.isNotBlank() } ?: throw AgentSkillException("read_skill_resourceにはnameが必要です。")
            val path = args.optString("path").takeIf { it.isNotBlank() } ?: throw AgentSkillException("read_skill_resourceにはpathが必要です。")
            return try {
                val content = JSONObject().put("name", name).put("path", path).put("content", repository.readResource(name, path)).toString()
                DiagnosticsLogger.log("Agent Skill resource read skill=$name path=$path")
                ToolResult(call.id, call.name, content)
            } catch (error: Exception) { DiagnosticsLogger.log("Agent Skill resource read failed skill=$name path=$path", error); throw error }
        }
    }
}
