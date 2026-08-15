import http from "node:http";
import { Agent } from "@earendil-works/pi-agent-core";
import { Type } from "typebox";
import { streamSimple as streamOpenAICompletions } from "@earendil-works/pi-ai/api/openai-completions";
import { streamSimple as streamOpenAIResponses } from "@earendil-works/pi-ai/api/openai-responses";
import { streamSimple as streamOpenAICodex } from "@earendil-works/pi-ai/api/openai-codex-responses";
import { streamSimple as streamAnthropic } from "@earendil-works/pi-ai/api/anthropic-messages";
import { streamSimple as streamGoogle } from "@earendil-works/pi-ai/api/google-generative-ai";

const port = Number(process.argv[2]);
const token = process.argv[3];
const runs = new Map();
const pendingTools = new Map();

if (!Number.isInteger(port) || port < 1 || !token) {
  throw new Error("Pi runtime requires a loopback port and authentication token");
}

function json(res, status, value) {
  const body = JSON.stringify(value);
  res.writeHead(status, { "content-type": "application/json", "content-length": Buffer.byteLength(body) });
  res.end(body);
}

async function body(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
}

function send(res, event) {
  res.write(`${JSON.stringify(event)}\n`);
}

function modelFrom(config) {
  return {
    id: config.model,
    name: config.model,
    api: config.api,
    provider: config.provider,
    baseUrl: config.baseURL,
    reasoning: Boolean(config.reasoning),
    input: config.supportsImages ? ["text", "image"] : ["text"],
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: config.contextWindow || 128000,
    maxTokens: config.maxTokens || 8192,
    headers: config.headers || undefined,
    compat: config.compat || undefined
  };
}

function contentFor(message) {
  const blocks = [];
  if (message.content) blocks.push({ type: "text", text: message.content });
  for (const attachment of message.attachments || []) {
    if (attachment.data && attachment.mimeType) {
      blocks.push({ type: "image", data: attachment.data, mimeType: attachment.mimeType });
    }
  }
  return blocks.length === 1 && blocks[0].type === "text" ? blocks[0].text : blocks;
}

function usage(value) {
  return {
    input: value?.inputTokens || 0,
    output: value?.outputTokens || 0,
    cacheRead: value?.cachedInputTokens || 0,
    cacheWrite: value?.cacheCreationInputTokens || 0,
    reasoning: value?.reasoningTokens,
    totalTokens: value?.totalTokens || 0,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 }
  };
}

function messagesFrom(request, config) {
  return request.messages.map((message) => {
    if (message.role === "assistant" || message.role === "model") {
      const content = [];
      if (message.reasoningContent) content.push({ type: "thinking", thinking: message.reasoningContent });
      if (message.content) content.push({ type: "text", text: message.content });
      for (const call of message.toolCalls || []) {
        let args = {};
        try { args = JSON.parse(call.argumentsJSON || "{}"); } catch {}
        content.push({ type: "toolCall", id: call.id, name: call.name, arguments: args });
      }
      return {
        role: "assistant", content, api: config.api, provider: config.provider,
        model: config.model, usage: usage(message.usage), stopReason: message.toolCalls?.length ? "toolUse" : "stop",
        timestamp: Date.now()
      };
    }
    if (message.role === "tool") {
      return {
        role: "toolResult", toolCallId: message.toolCallId || "tool", toolName: message.toolName || "tool",
        content: [{ type: "text", text: message.content || "" }], isError: Boolean(message.toolResultIsError),
        timestamp: Date.now()
      };
    }
    return { role: "user", content: contentFor(message), timestamp: Date.now() };
  });
}

function nativeToolPayload(tool, api) {
  if (tool.type === "google_search") return { googleSearch: {} };
  if (tool.type === "code_execution") return { codeExecution: {} };
  if (tool.type === "url_context") return { urlContext: {} };
  if (tool.type === "google_maps") return { googleMaps: {} };
  if (tool.type === "computer_use") return { computerUse: {} };
  if (tool.type === "function_declarations") {
    try { return { functionDeclarations: JSON.parse(tool.payload?.json || "[]") }; } catch { return null; }
  }
  return api === "google-generative-ai"
    ? null
    : { type: tool.type, payload: tool.payload || {} };
}

function mutatePayload(payload, request, config) {
  const value = structuredClone(payload);
  const metadata = request.metadata || {};
  const nativeTools = (request.tools || []).filter((tool) => tool.type !== "function");
  if (config.api === "google-generative-ai" && nativeTools.length) {
    value.config ||= {};
    value.config.tools = [
      ...(value.config.tools || []),
      ...nativeTools.map((tool) => nativeToolPayload(tool, config.api)).filter(Boolean)
    ];
  } else if (nativeTools.length) {
    value.tools = [
      ...(value.tools || []),
      ...nativeTools.filter((tool) => tool.type !== "mcp_toolset")
        .map((tool) => nativeToolPayload(tool, config.api)).filter(Boolean)
    ];
  }
  if (request.provider && config.provider === "openrouter") value.provider = request.provider;
  if (request.thinking && config.api === "openai-completions") value.reasoning = request.thinking;
  const temperature = Number(metadata.temperature);
  if (Number.isFinite(temperature)) {
    if (config.api === "google-generative-ai") {
      value.config ||= {};
      value.config.temperature = temperature;
    } else {
      value.temperature = temperature;
    }
  }
  if (config.api === "google-generative-ai") {
    value.config ||= {};
    if (metadata.geminiResponseMimeType) value.config.responseMimeType = metadata.geminiResponseMimeType;
    if (metadata.geminiResponseJSONSchema) {
      try { value.config.responseJsonSchema = JSON.parse(metadata.geminiResponseJSONSchema); } catch {}
    }
    value.config.thinkingConfig ||= {};
    if (request.thinking?.budget != null) value.config.thinkingConfig.thinkingBudget = request.thinking.budget;
    if (request.thinking?.includeThoughts != null) value.config.thinkingConfig.includeThoughts = request.thinking.includeThoughts;
    if (metadata.geminiThinkingLevel) value.config.thinkingConfig.thinkingLevel = metadata.geminiThinkingLevel;
    if (!Object.keys(value.config.thinkingConfig).length) delete value.config.thinkingConfig;
  }
  if (config.api === "openai-responses" || config.api === "openai-codex-responses") {
    if (metadata.codexReasoningSummary) {
      value.reasoning ||= {};
      value.reasoning.summary = metadata.codexReasoningSummary;
    }
    if (metadata.codexVerbosity) value.text = { ...(value.text || {}), verbosity: metadata.codexVerbosity };
    if (metadata.codexPromptCacheEnabled !== "false" && metadata.promptCacheKey) {
      value.prompt_cache_key = metadata.promptCacheKey;
    }
  }
  if (config.api === "anthropic-messages") {
    const mcp = nativeTools.find((tool) => tool.type === "mcp_toolset");
    if (mcp) {
      const serverName = mcp.payload?.server_name || "yamabiko-mcp";
      const server = { type: "url", url: mcp.payload?.server_url, name: serverName };
      if (config.mcpAuthorizationToken) server.authorization_token = config.mcpAuthorizationToken;
      value.mcp_servers = [server];
      const allowed = (mcp.payload?.allowed_tools || "").split(",").map((item) => item.trim()).filter(Boolean);
      const toolset = { type: "mcp_toolset", mcp_server_name: serverName };
      if (allowed.length) {
        toolset.default_config = { enabled: false };
        toolset.configs = Object.fromEntries(allowed.map((name) => [name, { enabled: true }]));
      }
      value.tools = [...(value.tools || []), toolset];
    }
  }
  return value;
}

function timeoutMs(request) {
  const milliseconds = Number(request.timeoutInterval) * 1000;
  return Number.isFinite(milliseconds) && milliseconds > 0 && milliseconds <= 2147483647
    ? milliseconds
    : undefined;
}

function streamFunction(request, config) {
  const implementation = {
    "openai-completions": streamOpenAICompletions,
    "openai-responses": streamOpenAIResponses,
    "openai-codex-responses": streamOpenAICodex,
    "anthropic-messages": streamAnthropic,
    "google-generative-ai": streamGoogle
  }[config.api];
  if (!implementation) throw new Error(`Unsupported Pi API adapter: ${config.api}`);
  return (model, context, options = {}) => implementation(model, context, {
    ...options,
    apiKey: config.apiKey,
    headers: config.headers,
    timeoutMs: timeoutMs(request),
    reasoning: config.thinkingLevel,
    sessionId: request.metadata?.promptCacheKey || request.metadata?.codexSessionId,
    onPayload: (payload) => mutatePayload(payload, request, config)
  });
}

function makeTools(request, runId, res) {
  return (request.tools || []).filter((tool) => tool.type === "function").map((tool) => {
    let schema = {};
    try { schema = JSON.parse(tool.payload?.parameters || "{}"); } catch {}
    return {
      name: tool.payload?.name,
      label: tool.payload?.name,
      description: tool.payload?.description || "",
      parameters: Type.Unsafe(schema),
      execute: async (toolCallId, params, signal) => {
        const requestId = crypto.randomUUID();
        send(res, { type: "tool_request", runId, requestId, toolCallId, name: tool.payload?.name, arguments: params });
        return await new Promise((resolve, reject) => {
          const abort = () => { pendingTools.delete(requestId); reject(new Error("Tool execution aborted")); };
          signal?.addEventListener("abort", abort, { once: true });
          pendingTools.set(requestId, (result) => {
            signal?.removeEventListener("abort", abort);
            if (result.isError) {
              reject(new Error(result.content || `Tool ${tool.payload?.name} failed`));
              return;
            }
            resolve({
              content: [{ type: "text", text: result.content || "" }],
              details: { sources: result.sources || [] }
            });
          });
        });
      }
    };
  });
}

function finalResponse(agent) {
  const assistants = agent.state.messages.filter((message) => message.role === "assistant");
  const last = assistants.at(-1);
  const text = (last?.content || []).filter((part) => part.type === "text").map((part) => part.text).join("");
  const reasoning = (last?.content || []).filter((part) => part.type === "thinking").map((part) => part.thinking).join("");
  const totals = assistants.reduce((sum, message) => {
    sum.inputTokens += message.usage?.input || 0;
    sum.outputTokens += message.usage?.output || 0;
    sum.totalTokens += message.usage?.totalTokens || 0;
    sum.reasoningTokens += message.usage?.reasoning || 0;
    sum.cachedInputTokens += message.usage?.cacheRead || 0;
    sum.cacheCreationInputTokens += message.usage?.cacheWrite || 0;
    return sum;
  }, { inputTokens: 0, outputTokens: 0, totalTokens: 0, reasoningTokens: 0, cachedInputTokens: 0, cacheCreationInputTokens: 0 });
  const toolCalls = assistants.flatMap((message) => (message.content || [])
    .filter((part) => part.type === "toolCall")
    .map((part) => ({
      id: part.id,
      name: part.name,
      argumentsJSON: JSON.stringify(part.arguments || {}),
      providerMetadata: null
    })));
  return {
    text,
    reasoningSummary: reasoning || null,
    usage: assistants.length ? totals : null,
    toolCalls
  };
}

async function runAgent(envelope, res) {
  const { runId, request, config } = envelope;
  const agent = new Agent({
    initialState: {
      systemPrompt: request.systemPrompt || "",
      model: modelFrom(config),
      thinkingLevel: config.thinkingLevel || "off",
      tools: makeTools(request, runId, res),
      messages: messagesFrom(request, config)
    },
    streamFn: streamFunction(request, config),
    toolExecution: "sequential",
    maxRetryDelayMs: 60000
  });
  runs.set(runId, agent);
  agent.subscribe((event) => {
    if (event.type === "message_update") {
      const update = event.assistantMessageEvent;
      if (update.type === "text_delta") send(res, { type: "text_delta", delta: update.delta });
      if (update.type === "thinking_delta") send(res, { type: "reasoning_delta", delta: update.delta });
    } else if (event.type === "tool_execution_start") {
      send(res, { type: "tool_start", id: event.toolCallId, name: event.toolName, arguments: event.args });
    } else if (event.type === "tool_execution_end") {
      send(res, { type: "tool_end", id: event.toolCallId, name: event.toolName, isError: event.isError, result: event.result });
    }
  });
  try {
    await agent.continue();
    send(res, { type: "completed", response: finalResponse(agent) });
  } finally {
    runs.delete(runId);
  }
}

const server = http.createServer(async (req, res) => {
  if (req.headers.authorization !== `Bearer ${token}`) return json(res, 401, { error: "unauthorized" });
  try {
    if (req.method === "GET" && req.url === "/health") return json(res, 200, { ok: true, node: process.versions.node });
    if (req.method === "POST" && req.url === "/v1/tool-result") {
      const result = await body(req);
      const complete = pendingTools.get(result.requestId);
      if (!complete) return json(res, 404, { error: "unknown tool request" });
      pendingTools.delete(result.requestId);
      complete(result);
      return json(res, 200, { ok: true });
    }
    if (req.method === "POST" && req.url === "/v1/abort") {
      const value = await body(req);
      runs.get(value.runId)?.abort();
      return json(res, 200, { ok: true });
    }
    if (req.method === "POST" && req.url === "/v1/run") {
      const envelope = await body(req);
      res.writeHead(200, { "content-type": "application/x-ndjson", "cache-control": "no-store" });
      try { await runAgent(envelope, res); res.end(); }
      catch (error) { send(res, { type: "error", message: error?.message || String(error) }); res.end(); }
      return;
    }
    json(res, 404, { error: "not found" });
  } catch (error) {
    if (!res.headersSent) json(res, 500, { error: error?.message || String(error) });
    else { send(res, { type: "error", message: error?.message || String(error) }); res.end(); }
  }
});

server.listen(port, "127.0.0.1");
