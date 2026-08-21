import http from "node:http";
import { Agent } from "@earendil-works/pi-agent-core";
import { createModels, createProvider, envApiKeyAuth, InMemoryCredentialStore } from "@earendil-works/pi-ai";
import { builtinModels } from "@earendil-works/pi-ai/providers/all";
import { registerBunOAuthFlows } from "@earendil-works/pi-ai/bun-oauth";
import { Type } from "typebox";
import { streamSimple as streamOpenAIResponses } from "@earendil-works/pi-ai/api/openai-responses";
import { openaiCodexProvider } from "@earendil-works/pi-ai/providers/openai-codex";
import * as grokOAuth from "pi-grok/oauth.ts";
import { buildProxyHeaders, CLI_PROXY_BASE_URL, FALLBACK_MODELS } from "pi-grok/models.ts";
import { sanitizePayload as sanitizeGrokPayload } from "pi-grok/sanitize.ts";

const port = Number(process.argv[2]);
const token = process.argv[3];
const runs = new Map();
const pendingTools = new Map();
const authCredentials = new InMemoryCredentialStore();
const RUNTIME_CONTRACT_VERSION = 2;
// The iOS app ships one self-contained JS bundle. Register Pi's OAuth modules
// statically so its intentionally opaque lazy imports do not look for sibling
// files that are absent from the application bundle.
registerBunOAuthFlows();
const authModels = createModels({ credentials: authCredentials });
authModels.setProvider(openaiCodexProvider());
const runtimeModels = builtinModels({ credentials: authCredentials });
let activeAuthLogin = null;

const VERIFIED_MODEL_SOURCES = new Map();
const DYNAMIC_CONTRACT_MODELS = new Map();
const DYNAMIC_PROVIDER_BASES = new Map();
const VERIFIED_OPENCODE_GO_ROUTES = [
  { id: "grok-4.5", api: "openai-responses" },
  { id: "gpt-5.6-luna", api: "openai-responses" },
  { id: "glm-5.3", api: "openai-completions" },
  { id: "glm-5.2", api: "openai-completions" },
  { id: "glm-5.1", api: "openai-completions" },
  { id: "kimi-k3", api: "openai-completions" },
  { id: "kimi-k2.7-code", api: "openai-completions" },
  { id: "kimi-k2.6", api: "openai-completions" },
  { id: "deepseek-v4-pro", api: "openai-completions" },
  { id: "deepseek-v4-flash", api: "openai-completions" },
  { id: "mimo-v2.5", api: "openai-completions" },
  { id: "mimo-v2.5-pro", api: "openai-completions" },
  { id: "minimax-m3", api: "anthropic-messages" },
  { id: "minimax-m2.7", api: "anthropic-messages" },
  { id: "minimax-m2.5", api: "anthropic-messages" },
  { id: "muse-spark-1.2-contributor", api: "openai-responses" },
  { id: "qwen3.8-max", api: "anthropic-messages" },
  { id: "qwen3.7-max", api: "anthropic-messages" },
  { id: "qwen3.7-plus", api: "anthropic-messages" },
  { id: "qwen3.6-plus", api: "anthropic-messages" },
  { id: "hy3", api: "openai-completions" }
];

function zeroCost() {
  return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
}

function installVerifiedOpenCodeGoContracts() {
  const provider = runtimeModels.getProvider("opencode-go");
  if (!provider) throw new Error("Pi does not provide the required opencode-go provider");
  const missingModels = new Map([
    ["minimax-m2.5", {
      id: "minimax-m2.5",
      name: "MiniMax-M2.5",
      provider: "opencode-go",
      reasoning: true,
      input: ["text"],
      cost: { input: 0.3, output: 1.2, cacheRead: 0.03, cacheWrite: 0 },
      contextWindow: 204800,
      maxTokens: 65536
    }],
    ["muse-spark-1.2-contributor", {
      id: "muse-spark-1.2-contributor",
      name: "Muse Spark 1.2 Contributor",
      provider: "opencode-go",
      reasoning: true,
      input: ["text", "image"],
      cost: { input: 0.1, output: 0.2, cacheRead: 0.002, cacheWrite: 0 },
      contextWindow: 1048576,
      maxTokens: 131072,
      thinkingLevelMap: { off: null, minimal: "minimal", low: "low", medium: "medium", high: "high", xhigh: "xhigh" }
    }]
  ]);
  const originals = provider.getModels();
  const byId = new Map(originals.map((model) => [model.id, model]));
  const merged = VERIFIED_OPENCODE_GO_ROUTES.map(({ id, api }) => {
    const original = byId.get(id) || missingModels.get(id);
    if (!original) throw new Error(`Pi is missing metadata for verified OpenCode Go model: ${id}`);
    const model = {
      ...original,
      api,
      provider: "opencode-go",
      baseUrl: api === "anthropic-messages"
        ? "https://opencode.ai/zen/go"
        : "https://opencode.ai/zen/go/v1"
    };
    VERIFIED_MODEL_SOURCES.set(`${model.provider}/${model.id}`, "verified_official_contract");
    return model;
  });
  runtimeModels.setProvider({ ...provider, getModels: () => merged });
}

function installSuperGrokProvider() {
  const models = FALLBACK_MODELS.map((model) => ({
    ...model,
    api: "openai-responses",
    provider: "xai-oauth",
    baseUrl: CLI_PROXY_BASE_URL,
    cost: model.cost || zeroCost(),
    headers: buildProxyHeaders(model.id)
  }));
  runtimeModels.setProvider(createProvider({
    id: "xai-oauth",
    name: "SuperGrok OAuth",
    auth: { apiKey: envApiKeyAuth("SuperGrok OAuth access token", ["XAI_OAUTH_TOKEN"]) },
    models,
    api: {
      "openai-responses": {
        stream: streamOpenAIResponses,
        streamSimple: streamOpenAIResponses
      }
    }
  }));
  for (const model of models) VERIFIED_MODEL_SOURCES.set(`xai-oauth/${model.id}`, "verified_official_contract");
}

installVerifiedOpenCodeGoContracts();
installSuperGrokProvider();

const AUTH_PROVIDER_IDS = {
  codex: "openai-codex",
  supergrok: "xai-oauth"
};

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

function oauthCredential(value) {
  if (!value || typeof value !== "object" || !value.access || !value.refresh || !Number.isFinite(value.expires)) {
    throw new Error("Pi OAuth credential is missing required fields");
  }
  return { ...value, type: "oauth" };
}

function decodeJwtPayload(token) {
  if (!token || typeof token !== "string") return null;
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
  } catch {
    return null;
  }
}

function authProfile(provider, credential) {
  const payload = decodeJwtPayload(provider === "supergrok" ? credential.idToken : credential.access) || {};
  const openAIAuth = payload["https://api.openai.com/auth"] || {};
  return {
    email: typeof payload.email === "string" ? payload.email : null,
    planType: provider === "codex" && typeof openAIAuth.chatgpt_plan_type === "string"
      ? openAIAuth.chatgpt_plan_type
      : null,
    accountId: provider === "codex"
      ? (credential.accountId || openAIAuth.chatgpt_account_id || null)
      : null
  };
}

function authProviderId(provider) {
  const providerId = AUTH_PROVIDER_IDS[provider];
  if (!providerId) throw new Error(`Unsupported Pi OAuth provider: ${provider}`);
  return providerId;
}

function waitForPromptAbort(prompt) {
  return new Promise((_, reject) => {
    const signal = prompt?.signal;
    if (signal?.aborted) return reject(new Error("Login cancelled"));
    signal?.addEventListener("abort", () => reject(new Error("Login cancelled")), { once: true });
  });
}

function codexInteraction(method, res, signal) {
  return {
    signal,
    notify(event) {
      if (event.type === "auth_url") send(res, { type: "auth_url", url: event.url, instructions: event.instructions });
      if (event.type === "device_code") {
        send(res, {
          type: "device_code",
          userCode: event.userCode,
          verificationUri: event.verificationUri,
          intervalSeconds: event.intervalSeconds,
          expiresInSeconds: event.expiresInSeconds
        });
      }
      if (event.type === "progress" || event.type === "info") {
        send(res, { type: "auth_progress", message: event.message });
      }
    },
    prompt(prompt) {
      if (prompt.type === "select") return Promise.resolve(method === "device" ? "device_code" : "browser");
      return waitForPromptAbort(prompt);
    }
  };
}

function grokCallbacks(res, signal) {
  return {
    signal,
    onAuth(info) {
      send(res, { type: "auth_url", url: info.url, instructions: info.instructions });
    },
    onDeviceCode(info) {
      send(res, {
        type: "device_code",
        userCode: info.userCode,
        verificationUri: info.verificationUri,
        intervalSeconds: info.intervalSeconds,
        expiresInSeconds: info.expiresInSeconds
      });
    },
    onProgress(message) {
      send(res, { type: "auth_progress", message });
    },
    onPrompt: waitForPromptAbort,
    onSelect: async (prompt) => prompt.options?.[0]?.id
  };
}

async function withGrokBrowserLogin(operation) {
  const previous = process.env.PI_XAI_LOGIN_METHOD;
  process.env.PI_XAI_LOGIN_METHOD = "callback";
  try {
    return await operation();
  } finally {
    if (previous === undefined) delete process.env.PI_XAI_LOGIN_METHOD;
    else process.env.PI_XAI_LOGIN_METHOD = previous;
  }
}

async function loginOAuth(provider, method, res) {
  if (activeAuthLogin) throw new Error("Another Pi OAuth login is already running");
  const controller = new AbortController();
  activeAuthLogin = controller;
  try {
    let credential;
    if (provider === "codex") {
      credential = await authModels.login(
        authProviderId(provider),
        "oauth",
        codexInteraction(method, res, controller.signal)
      );
    } else if (provider === "supergrok") {
      const callbacks = grokCallbacks(res, controller.signal);
      credential = method === "browser"
        ? await withGrokBrowserLogin(() => grokOAuth.login(callbacks))
        : await grokOAuth.loginDeviceCode(callbacks);
      credential = oauthCredential(credential);
      await authCredentials.modify(authProviderId(provider), async () => credential);
    } else {
      throw new Error(`Unsupported Pi OAuth provider: ${provider}`);
    }
    const normalized = oauthCredential(credential);
    send(res, { type: "auth_completed", credential: normalized, profile: authProfile(provider, normalized) });
  } finally {
    activeAuthLogin = null;
  }
}

async function resolveOAuth(provider, rawCredential, force) {
  const providerId = authProviderId(provider);
  let credential = oauthCredential(rawCredential);
  if (force) credential = { ...credential, expires: 0 };
  await authCredentials.modify(providerId, async () => credential);

  if (provider === "codex") {
    const resolved = await authModels.getAuth(providerId);
    if (!resolved?.auth?.apiKey) throw new Error("Pi did not resolve Codex OAuth credentials");
  } else {
    const expiresSoon = Date.now() + 5 * 60 * 1000 >= credential.expires;
    if (expiresSoon) {
      credential = oauthCredential(await grokOAuth.refresh(credential));
      await authCredentials.modify(providerId, async () => credential);
    }
  }

  const updated = oauthCredential(await authCredentials.read(providerId));
  const profile = authProfile(provider, updated);
  return {
    credential: updated,
    accessToken: updated.access,
    accountId: provider === "codex" ? (updated.accountId || profile.accountId) : null,
    profile
  };
}

function diagnostic(res, runId, stage, message, metadata = {}) {
  send(res, { type: "diagnostic", runId, stage, message, metadata });
}

function effectiveHeaders(config) {
  return config.provider === "xai-oauth"
    ? { ...buildProxyHeaders(config.model), ...(config.headers || {}) }
    : config.headers;
}

function expectedApiForShape(shape) {
  if (shape === "responses") return "openai-responses";
  if (shape === "completions") return "openai-completions";
  if (shape === "messages") return "anthropic-messages";
  return null;
}

function expectedApiForNpm(npm) {
  if (npm === "@ai-sdk/openai") return "openai-responses";
  if (npm === "@ai-sdk/openai-compatible") return "openai-completions";
  if (npm === "@openrouter/ai-sdk-provider") return "openai-completions";
  if (npm === "@ai-sdk/anthropic") return "anthropic-messages";
  if (npm === "@ai-sdk/google") return "google-generative-ai";
  return null;
}

function normalizedURL(value) {
  if (typeof value !== "string" || !value.trim() || value.includes("${")) return null;
  return value.trim().replace(/\/+$/, "");
}

function endpointURL(baseUrl, api) {
  const base = normalizedURL(baseUrl);
  if (!base) return null;
  if (api === "anthropic-messages") {
    if (base.endsWith("/v1/messages")) return base;
    if (base.endsWith("/v1")) return `${base}/messages`;
    return `${base}/v1/messages`;
  }
  if (api === "openai-completions") {
    return base.endsWith("/chat/completions") ? base : `${base}/chat/completions`;
  }
  if (api === "openai-responses") {
    return base.endsWith("/responses") ? base : `${base}/responses`;
  }
  return null;
}

function trustedCatalogContract(contract) {
  return ["model", "provider", "official_provider_catalog"].includes(contract?.provenance);
}

function installCatalogModel(config, provider, expectedApi) {
  const contract = config.catalogContract;
  if (!trustedCatalogContract(contract)) return null;
  const contractURL = normalizedURL(contract.api);
  const name = typeof contract.name === "string" ? contract.name.trim() : "";
  const input = Array.isArray(contract.input)
    ? contract.input.filter((value) => typeof value === "string" && value.trim()).map((value) => value.trim())
    : [];
  const contextWindow = Number(contract.contextWindow);
  const maxTokens = Number(contract.maxTokens);
  if (!expectedApi || !contractURL || !name || !input.includes("text") ||
      !Number.isInteger(contextWindow) || contextWindow <= 0 ||
      !Number.isInteger(maxTokens) || maxTokens <= 0 ||
      typeof contract.reasoning !== "boolean") {
    return null;
  }

  const reference = provider.getModels().find((model) => model.api === expectedApi);
  if (!reference) return null;
  const contractEndpoint = endpointURL(contractURL, expectedApi) || contractURL;
  const referenceEndpoint = endpointURL(reference.baseUrl, expectedApi) || normalizedURL(reference.baseUrl);
  if (!referenceEndpoint || contractEndpoint !== referenceEndpoint) return null;

  const model = {
    id: config.model,
    name,
    api: expectedApi,
    provider: config.provider,
    baseUrl: contractURL,
    reasoning: contract.reasoning,
    input,
    cost: zeroCost(),
    contextWindow,
    maxTokens
  };
  let dynamic = DYNAMIC_CONTRACT_MODELS.get(config.provider);
  if (!dynamic) {
    dynamic = new Map();
    DYNAMIC_CONTRACT_MODELS.set(config.provider, dynamic);
  }
  dynamic.set(model.id, model);
  let baseProvider = DYNAMIC_PROVIDER_BASES.get(config.provider);
  if (!baseProvider) {
    baseProvider = provider;
    DYNAMIC_PROVIDER_BASES.set(config.provider, baseProvider);
  }
  runtimeModels.setProvider({
    ...baseProvider,
    getModels: () => {
      const dynamicModels = DYNAMIC_CONTRACT_MODELS.get(config.provider) || new Map();
      return [
        ...baseProvider.getModels().filter((entry) => !dynamicModels.has(entry.id)),
        ...dynamicModels.values()
      ];
    }
  });
  VERIFIED_MODEL_SOURCES.set(`${model.provider}/${model.id}`, contract.provenance);
  return model;
}

function resolutionFor(config) {
  if (config.contractVersion !== RUNTIME_CONTRACT_VERSION) {
    throw new Error(`Pi runtime contract mismatch: expected ${RUNTIME_CONTRACT_VERSION}, received ${config.contractVersion ?? "missing"}`);
  }
  const provider = runtimeModels.getProvider(config.provider);
  if (!provider) {
    return { supported: false, reason: "pi_provider_missing", provider: config.provider, model: config.model };
  }
  const contract = config.catalogContract;
  const isAuthoritativeContract = trustedCatalogContract(contract);
  const shapeApi = expectedApiForShape(contract?.shape);
  const npmApi = expectedApiForNpm(contract?.npm);
  const expectedApi = shapeApi || npmApi;
  if (isAuthoritativeContract && contract?.shape && !shapeApi) {
    return {
      supported: false,
      reason: "catalog_contract_ambiguous",
      provider: config.provider,
      model: config.model,
      contractShape: contract.shape
    };
  }
  if (isAuthoritativeContract && shapeApi && npmApi && shapeApi !== npmApi) {
    return {
      supported: false,
      reason: "protocol_conflict",
      provider: config.provider,
      model: config.model,
      contractApi: shapeApi,
      contractNpmApi: npmApi
    };
  }
  if (isAuthoritativeContract && !expectedApi) {
    return {
      supported: false,
      reason: "catalog_contract_ambiguous",
      provider: config.provider,
      model: config.model,
      contractNpm: contract?.npm
    };
  }
  let model = runtimeModels.getModel(config.provider, config.model);
  if (!model) {
    const contractEndpoint = endpointURL(contract?.api, expectedApi) || normalizedURL(contract?.api);
    const reference = provider.getModels().find((entry) => entry.api === expectedApi);
    const referenceEndpoint = endpointURL(reference?.baseUrl, expectedApi) || normalizedURL(reference?.baseUrl);
    if (contractEndpoint && referenceEndpoint && contractEndpoint !== referenceEndpoint) {
      return {
        supported: false,
        reason: "endpoint_conflict",
        provider: config.provider,
        model: config.model,
        contractApi: expectedApi,
        contractURL: contractEndpoint,
        modelURL: referenceEndpoint
      };
    }
    model = installCatalogModel(config, provider, expectedApi);
    if (!model) {
      return {
        supported: false,
        reason: isAuthoritativeContract ? "catalog_contract_incomplete" : "pi_model_missing",
        provider: config.provider,
        model: config.model
      };
    }
  }
  if (isAuthoritativeContract && expectedApi && expectedApi !== model.api) {
    return {
      supported: false,
      reason: "protocol_conflict",
      provider: model.provider,
      model: model.id,
      api: model.api,
      contractApi: expectedApi
    };
  }
  if (isAuthoritativeContract && contract?.api) {
    if (!expectedApi) {
      return {
        supported: false,
        reason: "catalog_contract_ambiguous",
        provider: model.provider,
        model: model.id,
        api: model.api,
        contractURL: normalizedURL(contract.api)
      };
    }
    const contractEndpoint = endpointURL(contract.api, expectedApi);
    const modelEndpoint = endpointURL(model.baseUrl, model.api);
    if (contractEndpoint && modelEndpoint && contractEndpoint !== modelEndpoint) {
      return {
        supported: false,
        reason: "endpoint_conflict",
        provider: model.provider,
        model: model.id,
        api: model.api,
        contractApi: expectedApi,
        contractURL: contractEndpoint,
        modelURL: modelEndpoint
      };
    }
  }
  return {
    supported: true,
    provider: model.provider,
    model: model.id,
    api: model.api,
    source: VERIFIED_MODEL_SOURCES.get(`${model.provider}/${model.id}`) || "pi_builtin",
    reasoning: model.reasoning,
    input: model.input,
    contextWindow: model.contextWindow,
    maxTokens: model.maxTokens,
    toolCall: contract ? contract.toolCall === true : true
  };
}

function resolveModel(config) {
  const resolution = resolutionFor(config);
  if (!resolution.supported) {
    throw new Error(`Unsupported model contract (${resolution.reason}): ${config.provider}/${config.model}`);
  }
  return { model: runtimeModels.getModel(config.provider, config.model), resolution };
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

function providerUsage(value) {
  if (!value) return null;
  return {
    inputTokens: value.input || 0,
    outputTokens: value.output || 0,
    totalTokens: value.totalTokens || 0,
    reasoningTokens: value.reasoning,
    cachedInputTokens: value.cacheRead || 0,
    cacheCreationInputTokens: value.cacheWrite || 0
  };
}

function messagesFrom(request, model) {
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
        role: "assistant", content, api: model.api, provider: model.provider,
        model: model.id, usage: usage(message.usage), stopReason: message.toolCalls?.length ? "toolUse" : "stop",
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
  // Google places a live AbortSignal instance in config.abortSignal. A structured clone
  // strips its prototype, leaving an object without addEventListener and breaking every
  // Google request before it reaches the network. Copy only containers we mutate so the
  // SDK-owned AbortSignal and other runtime objects retain their identity.
  const value = { ...payload };
  if (payload.config && typeof payload.config === "object") {
    value.config = { ...payload.config };
    if (payload.config.thinkingConfig && typeof payload.config.thinkingConfig === "object") {
      value.config.thinkingConfig = { ...payload.config.thinkingConfig };
    }
  }
  if (payload.reasoning && typeof payload.reasoning === "object") {
    value.reasoning = { ...payload.reasoning };
  }
  if (payload.text && typeof payload.text === "object") {
    value.text = { ...payload.text };
  }
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
    const thinkingLevel = String(config.thinkingLevel || "").toLowerCase();
    const usesThinkingLevel = ["minimal", "low", "medium", "high"].includes(thinkingLevel);
    if (!usesThinkingLevel) {
      value.config.thinkingConfig ||= {};
      if (request.thinking?.budget != null) value.config.thinkingConfig.thinkingBudget = request.thinking.budget;
      if (request.thinking?.includeThoughts != null) value.config.thinkingConfig.includeThoughts = request.thinking.includeThoughts;
      if (metadata.geminiThinkingLevel) value.config.thinkingConfig.thinkingLevel = metadata.geminiThinkingLevel;
      if (!Object.keys(value.config.thinkingConfig).length) delete value.config.thinkingConfig;
    }
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

function exportableProviderPayload(value) {
  const seen = new WeakSet();
  return JSON.parse(JSON.stringify(value, (key, nested) => {
    const normalizedKey = key.toLowerCase();
    if (["apikey", "api_key", "authorization", "accesstoken", "access_token", "credential"].includes(normalizedKey)) {
      return "[REDACTED]";
    }
    if (normalizedKey === "abortsignal" || normalizedKey === "signal") return undefined;
    if (typeof nested === "function") return undefined;
    if (nested && typeof nested === "object") {
      if (seen.has(nested)) return "[CIRCULAR]";
      seen.add(nested);
    }
    return nested;
  }));
}

function standardStreamFunction(request, config, report, captureProviderRequest) {
  return (model, context, options = {}) => runtimeModels.streamSimple(model, context, {
    ...options,
    apiKey: config.apiKey,
    env: config.env || undefined,
    headers: config.provider === "xai-oauth" && (request.metadata?.promptCacheKey || request.metadata?.codexSessionId)
      ? {
          ...effectiveHeaders(config),
          "x-grok-conv-id": request.metadata?.promptCacheKey || request.metadata?.codexSessionId
        }
      : effectiveHeaders(config),
    timeoutMs: timeoutMs(request),
    reasoning: config.thinkingLevel,
    sessionId: request.metadata?.promptCacheKey || request.metadata?.codexSessionId,
    onPayload: (payload) => {
      const mutated = mutatePayload(payload, request, config);
      captureProviderRequest(exportableProviderPayload(mutated));
      report("provider_request", "Pi provider request payload prepared", {
        api: config.api,
        provider: config.provider,
        model: config.model,
        hasSystemPrompt: String(Boolean(request.systemPrompt)),
        messageCount: String(request.messages?.length || 0),
        toolTypes: (request.tools || []).map((tool) => tool.type).join(","),
        thinkingLevel: config.thinkingLevel || "none",
        abortSignalType: mutated.config?.abortSignal?.constructor?.name || "none",
        abortSignalListener: typeof mutated.config?.abortSignal?.addEventListener
      });
      return config.provider === "xai-oauth"
        ? sanitizeGrokPayload(
            mutated,
            config.model,
            request.metadata?.promptCacheKey || request.metadata?.codexSessionId,
            Boolean(config.reasoning)
          )
        : mutated;
    }
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

function finalResponse(assistants, contextUsage) {
  const last = assistants.at(-1);
  if (!last) throw new Error("Pi provider returned no assistant message");
  if (last.stopReason === "error" || last.errorMessage) {
    const detail = last.errorMessage || last.rawStopReason || "unknown provider error";
    throw new Error(`Pi provider failed: ${detail}`);
  }
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
  if (!text && !reasoning && !toolCalls.length) {
    throw new Error(`Pi provider completed without content (stopReason=${last.stopReason || "unknown"})`);
  }
  const aggregateUsage = assistants.length ? totals : null;
  const usageSamples = assistants.map((message) => providerUsage(message.usage)).filter(Boolean);
  if (contextUsage) {
    if (aggregateUsage) {
      aggregateUsage.contextTokens = contextUsage.tokens;
      aggregateUsage.contextWindow = contextUsage.contextWindow;
    }
    const lastSample = usageSamples.at(-1);
    if (lastSample) {
      lastSample.contextTokens = contextUsage.tokens;
      lastSample.contextWindow = contextUsage.contextWindow;
    }
  }
  return {
    text,
    reasoningSummary: reasoning || null,
    usage: aggregateUsage,
    usageSamples,
    toolCalls
  };
}

function piExecutionSnapshot({ agent, effectiveRequest, providerRequests, resolution, startedAtMs, failure = null }) {
  return {
    format: "yamabiko.pi-agent-execution",
    version: 1,
    runtimeContractVersion: RUNTIME_CONTRACT_VERSION,
    startedAtMs,
    completedAtMs: Date.now(),
    resolution,
    request: exportableProviderPayload(effectiveRequest),
    state: exportableProviderPayload({
      systemPrompt: agent.state.systemPrompt,
      model: {
        id: agent.state.model.id,
        name: agent.state.model.name,
        api: agent.state.model.api,
        provider: agent.state.model.provider,
        baseUrl: agent.state.model.baseUrl,
        reasoning: agent.state.model.reasoning,
        input: agent.state.model.input,
        contextWindow: agent.state.model.contextWindow,
        maxTokens: agent.state.model.maxTokens
      },
      thinkingLevel: agent.state.thinkingLevel,
      messages: agent.state.messages,
      streamingMessage: agent.state.streamingMessage,
      errorMessage: agent.state.errorMessage
    }),
    providerRequests,
    failure,
    redactions: ["API keys, authorization values, credentials, access tokens, and abort signals"]
  };
}

async function runAgent(envelope, res) {
  const { runId, request, config } = envelope;
  const startedAtMs = Date.now();
  const { model, resolution } = resolveModel(config);
  const resolvedConfig = { ...config, api: model.api, provider: model.provider, model: model.id };
  const report = (stage, message, metadata) => diagnostic(res, runId, stage, message, metadata);
  report("received", "Pi runtime accepted request", {
    contractVersion: String(RUNTIME_CONTRACT_VERSION),
    api: model.api,
    provider: model.provider,
    model: model.id,
    resolutionSource: resolution.source,
    hasCredential: String(Boolean(config.apiKey)),
    messageCount: String(request.messages?.length || 0),
    toolTypes: (request.tools || []).map((tool) => tool.type).join(",")
  });
  const hasImageAttachments = (request.messages || []).some((message) => (message.attachments || []).length > 0);
  if (hasImageAttachments && !(model.input || []).includes("image")) {
    throw new Error(`Model does not support image input: ${model.provider}/${model.id}`);
  }
  const effectiveRequest = resolution.toolCall
    ? request
    : { ...request, tools: [] };
  const providerRequests = [];
  const agent = new Agent({
    initialState: {
      systemPrompt: request.systemPrompt || "",
      model,
      thinkingLevel: config.thinkingLevel || "off",
      tools: makeTools(effectiveRequest, runId, res),
      messages: messagesFrom(effectiveRequest, model)
    },
    streamFn: standardStreamFunction(effectiveRequest, resolvedConfig, report, (payload) => {
      providerRequests.push({
        step: providerRequests.length + 1,
        capturedAtMs: Date.now(),
        payload
      });
    }),
    toolExecution: "sequential",
    maxRetryDelayMs: 60000
  });
  runs.set(runId, agent);
  let step = 0;
  let activeStep = null;
  const runAssistants = [];
  agent.subscribe((event) => {
    if (event.type === "turn_start") {
      activeStep = ++step;
      send(res, { type: "llm_start", stepId: activeStep, timeMs: Date.now() });
    } else if (event.type === "message_update") {
      const update = event.assistantMessageEvent;
      if (update.type === "text_delta") send(res, { type: "text_delta", delta: update.delta });
      if (update.type === "thinking_delta") send(res, { type: "reasoning_delta", delta: update.delta });
    } else if (event.type === "message_end" && event.message?.role === "assistant") {
      runAssistants.push(event.message);
      send(res, {
        type: "llm_end",
        stepId: activeStep,
        timeMs: Date.now(),
        succeeded: event.message.stopReason !== "error" && event.message.stopReason !== "aborted" && !event.message.errorMessage,
        usage: providerUsage(event.message.usage)
      });
      activeStep = null;
    } else if (event.type === "tool_execution_start") {
      send(res, { type: "tool_start", toolCallId: event.toolCallId, name: event.toolName, timeMs: Date.now() });
    } else if (event.type === "tool_execution_end") {
      send(res, { type: "tool_end", toolCallId: event.toolCallId, name: event.toolName, timeMs: Date.now(), succeeded: !event.isError });
    }
  });
  try {
    report("agent_start", "Pi agent execution starting");
    await agent.continue();
    const last = runAssistants.at(-1);
    report("provider_result", "Pi provider stream finished", {
      stopReason: last?.stopReason || "missing",
      rawStopReason: last?.rawStopReason || "none",
      contentTypes: (last?.content || []).map((part) => part.type).join(","),
      errorMessage: last?.errorMessage || "none"
    });
    const contextWindow = model.contextWindow || null;
    const contextEstimate = contextWindow && last?.usage
      ? { tokens: last.usage.totalTokens, contextWindow }
      : null;
    const response = finalResponse(runAssistants, contextEstimate);
    response.piExecution = piExecutionSnapshot({
      agent,
      effectiveRequest,
      providerRequests,
      resolution,
      startedAtMs
    });
    report("agent_complete", "Pi agent execution completed");
    send(res, { type: "completed", response });
  } catch (error) {
    send(res, {
      type: "execution_snapshot",
      execution: piExecutionSnapshot({
        agent,
        effectiveRequest,
        providerRequests,
        resolution,
        startedAtMs,
        failure: {
          name: error?.name || "Error",
          message: error?.message || String(error)
        }
      })
    });
    report("agent_error", "Pi agent execution failed", {
      errorName: error?.name || "Error",
      errorMessage: error?.message || String(error)
    });
    throw error;
  } finally {
    runs.delete(runId);
  }
}

const server = http.createServer(async (req, res) => {
  if (req.headers.authorization !== `Bearer ${token}`) return json(res, 401, { error: "unauthorized" });
  try {
    if (req.method === "GET" && req.url === "/health") {
      return json(res, 200, { ok: true, node: process.versions.node, contractVersion: RUNTIME_CONTRACT_VERSION });
    }
    if (req.method === "POST" && req.url === "/v1/models/resolve") {
      const value = await body(req);
      const configs = Array.isArray(value.models) ? value.models : [value];
      return json(res, 200, {
        contractVersion: RUNTIME_CONTRACT_VERSION,
        models: configs.map((config) => {
          try { return resolutionFor(config); }
          catch (error) {
            return {
              supported: false,
              reason: "runtime_contract_mismatch",
              provider: config?.provider,
              model: config?.model,
              message: error?.message || String(error)
            };
          }
        })
      });
    }
    if (req.method === "POST" && req.url === "/v1/auth/login") {
      const value = await body(req);
      res.writeHead(200, { "content-type": "application/x-ndjson", "cache-control": "no-store" });
      try { await loginOAuth(value.provider, value.method || "browser", res); res.end(); }
      catch (error) { send(res, { type: "error", message: error?.message || String(error) }); res.end(); }
      return;
    }
    if (req.method === "POST" && req.url === "/v1/auth/resolve") {
      const value = await body(req);
      return json(res, 200, await resolveOAuth(value.provider, value.credential, Boolean(value.force)));
    }
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
      catch (error) { send(res, { type: "error", stage: "run", message: error?.message || String(error) }); res.end(); }
      return;
    }
    json(res, 404, { error: "not found" });
  } catch (error) {
    if (!res.headersSent) json(res, 500, { error: error?.message || String(error) });
    else { send(res, { type: "error", message: error?.message || String(error) }); res.end(); }
  }
});

server.listen(port, "127.0.0.1");
