// Model-level models.dev routes, verified against Microsoft Foundry contracts.
// Drift check: scripts/check-azure-contract.py. No protocol/endpoint fallback.
import { createProvider } from "@earendil-works/pi-ai";
import * as messages from "@earendil-works/pi-ai/api/anthropic-messages";
import * as completions from "@earendil-works/pi-ai/api/openai-completions";
import * as responses from "@earendil-works/pi-ai/api/azure-openai-responses";

export const AZURE_PROVIDER = "azure-openai-responses";
export const AZURE_ROUTES = {
  "@ai-sdk/anthropic": { api: "anthropic-messages", path: "anthropic/v1" },
  "@ai-sdk/openai-compatible": { api: "openai-completions", path: "models" }
};
export const AZURE_ADAPTIVE_MODELS = new Set([
  "claude-fable-5", "claude-fable-5-1", "claude-haiku-5-5", "claude-mythos-5",
  "claude-mythos-5-1", "claude-mythos-preview", "claude-opus-4-6", "claude-opus-4-7",
  "claude-opus-4-8", "claude-opus-5", "claude-opus-5-5", "claude-sonnet-4-6",
  "claude-sonnet-5", "claude-sonnet-5-5"
]);
const mandatoryThinking = new Set(["claude-fable-5", "claude-fable-5-1", "claude-mythos-5", "claude-mythos-5-1", "claude-mythos-preview"]);
const entraOnly = new Set(["claude-mythos-5", "claude-mythos-5-1", "claude-mythos-preview"]);

export function installAzureProvider(models) {
  const original = models.getProvider(AZURE_PROVIDER);
  if (!original) throw new Error("Pi Azure provider is required");
  const extended = createProvider({
    id: original.id, name: original.name, models: original.getModels(),
    auth: { apiKey: {
      ...original.auth.apiKey,
      resolve: async (context) => {
        const token = await context.ctx.env("AZURE_AUTH_TOKEN");
        if (token) return { auth: { headers: { Authorization: `Bearer ${token}` } }, source: "AZURE_AUTH_TOKEN" };
        return original.auth.apiKey.resolve(context);
      }
    } },
    api: { "azure-openai-responses": responses, "anthropic-messages": messages, "openai-completions": completions }
  });
  models.setProvider({ ...original, auth: extended.auth, stream: extended.stream, streamSimple: extended.streamSimple });
}

export function azureCatalogResolution(config, models) {
  if (["cohere-embed-v3-english", "cohere-embed-v3-multilingual", "cohere-embed-v-4-0", "cohere-embed-v4-0"].includes(config.model)) {
    return { supported: false, reason: "model_operation_unsupported", provider: config.provider, model: config.model };
  }
  const contract = config.catalogContract;
  // Provider-level @ai-sdk/azure is insufficient to infer a non-built-in route.
  const verifiedResponse = config.model === "gpt-chat-latest" && contract?.npm === "@ai-sdk/azure";
  if (!contract || (!contract.npm && !contract.api && !contract.shape) || (contract.npm === "@ai-sdk/azure" && !verifiedResponse)) return null;
  const fail = (reason) => ({ supported: false, reason, provider: config.provider, model: config.model });
  if (!(verifiedResponse ? ["model", "provider", "official_provider_catalog"] : ["model", "official_provider_catalog"]).includes(contract.provenance)) return fail("catalog_contract_ambiguous");
  // Explicit Microsoft Responses allowlist, never inferred from @ai-sdk/azure.
  const route = verifiedResponse ? { api: "azure-openai-responses" } : AZURE_ROUTES[contract.npm];
  if (!route) return fail("catalog_contract_ambiguous");
  if (contract.shape && contract.shape !== (verifiedResponse ? "responses" : route.api === "anthropic-messages" ? "messages" : "completions")) return fail("protocol_conflict");
  const template = `https://\${AZURE_RESOURCE_NAME}.services.ai.azure.com/${route.path}`;
  if (verifiedResponse ? Boolean(contract.api) : contract.api?.replace(/\/+$/, "") !== template) return fail("endpoint_conflict");
  if (!contract.name?.trim() || typeof contract.reasoning !== "boolean" ||
      !Array.isArray(contract.input) || !contract.input.includes("text") ||
      !Number.isSafeInteger(contract.contextWindow) || contract.contextWindow <= 0 ||
      !Number.isSafeInteger(contract.maxTokens) || contract.maxTokens <= 0) return fail("catalog_contract_incomplete");
  const model = {
    id: config.model, name: contract.name, provider: AZURE_PROVIDER, api: route.api,
    baseUrl: verifiedResponse ? models.getModel(AZURE_PROVIDER, "gpt-5.2").baseUrl : contract.api, reasoning: contract.reasoning, input: contract.input,
    contextWindow: contract.contextWindow, maxTokens: contract.maxTokens,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    ...(verifiedResponse ? { thinkingLevelMap: { off: null } } : {}),
    ...(route.api === "openai-completions" ? { compat: {
      // Fields accepted by the versioned Foundry Model Inference REST contract.
      supportsStore: false, supportsDeveloperRole: false, supportsReasoningEffort: false,
      supportsUsageInStreaming: false, maxTokensField: "max_tokens"
    } } : {}),
    ...(AZURE_ADAPTIVE_MODELS.has(config.model) ? { compat: { forceAdaptiveThinking: true } } : {})
  };
  const provider = models.getProvider(AZURE_PROVIDER);
  const existing = provider.getModels().filter((entry) => entry.id !== model.id);
  models.setProvider({ ...provider, getModels: () => [...existing, model] });
  return { supported: true, provider: model.provider, model: model.id, api: model.api,
    source: "verified_official_contract", reasoning: model.reasoning, input: model.input,
    contextWindow: model.contextWindow, maxTokens: model.maxTokens, toolCall: contract.toolCall === true };
}

export function azureExecutionModel(model, config) {
  if (model.provider !== AZURE_PROVIDER || !model.baseUrl.includes("${AZURE_RESOURCE_NAME}")) return model;
  const resource = config.env?.AZURE_RESOURCE_NAME || config.env?.AZURE_OPENAI_RESOURCE_NAME;
  if (!resource || !/^[a-zA-Z0-9][a-zA-Z0-9-]*$/.test(resource)) {
    throw Object.assign(new Error("Azure resource name is missing or invalid"), { code: "azure_resource_name_required" });
  }
  if (entraOnly.has(model.id) && !config.env?.AZURE_AUTH_TOKEN) {
    throw Object.assign(new Error("This Azure model requires an Entra ID token (AZURE_AUTH_TOKEN)"), { code: "azure_entra_id_required" });
  }
  // Per-run copy: never persist a resource name or credential in the model registry.
  const baseUrl = model.baseUrl.replace("${AZURE_RESOURCE_NAME}", resource).replace(/\/+$/, "");
  // Anthropic's SDK appends /v1/messages itself (models.dev includes /v1).
  return { ...model, baseUrl: model.api === "anthropic-messages" ? baseUrl.replace(/\/v1\/?$/, "") : baseUrl };
}

export function azureStreamOptions(config) {
  if (config.provider === AZURE_PROVIDER && config.api === "azure-openai-responses") {
    const token = config.env?.AZURE_AUTH_TOKEN;
    return {
      ...(config.model === "gpt-chat-latest" ? { reasoning: undefined } : {}),
      ...(token ? { apiKey: token, headers: { ...config.headers, Authorization: `Bearer ${token}`, "api-key": null } } : {})
    };
  }
  return config.provider === AZURE_PROVIDER && mandatoryThinking.has(config.model)
    ? { reasoning: config.thinkingLevel || "high" } : {};
}
