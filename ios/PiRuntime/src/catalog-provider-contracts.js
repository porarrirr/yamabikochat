// Verified provider-specific routes missing from Pi's generated catalog.
// Only existing Pi providers and standard Pi adapters are extended here.
// Sources and automated drift checks: scripts/check-catalog-provider-contracts.py.
import { createProvider } from "@earendil-works/pi-ai";
import * as completions from "@earendil-works/pi-ai/api/openai-completions";
import * as responses from "@earendil-works/pi-ai/api/openai-responses";
import * as messages from "@earendil-works/pi-ai/api/anthropic-messages";
import * as google from "@earendil-works/pi-ai/api/google-generative-ai";
import { withOpenCodeSessionHeader } from "@earendil-works/pi-ai/providers/opencode-headers";

const registryBaselines = new WeakMap();
const verifiedModels = new WeakSet();
export const verifiedCatalogModelSource = (model) => verifiedModels.has(model) ? "verified_official_contract" : null;

const openCodePackages = {
  "@ai-sdk/openai-compatible": "openai-completions",
  "@ai-sdk/openai": "openai-responses",
  "@ai-sdk/anthropic": "anthropic-messages",
  "@ai-sdk/google": "google-generative-ai"
};
const shapes = { responses: "openai-responses", completions: "openai-completions", messages: "anthropic-messages" };
const routes = {
  "opencode": { provider: "opencode", openCode: "https://opencode.ai/inference" },
  "opencode-go": { provider: "opencode-go", openCode: "https://opencode.ai/inference/go" },
  "minimax-cn": { provider: "minimax-cn", api: "anthropic-messages", npm: "@ai-sdk/anthropic", baseUrl: "https://api.minimax.cn/anthropic/v1" },
  "minimax-cn-coding-plan": { provider: "minimax-cn", api: "anthropic-messages", npm: "@ai-sdk/anthropic", baseUrl: "https://api.minimax.cn/anthropic/v1" },
  "zai": { provider: "zai", api: "openai-completions", npm: "@ai-sdk/openai-compatible", baseUrl: "https://api.z.ai/api/paas/v4" },
  "zai-coding-plan": { provider: "zai", api: "openai-completions", npm: "@ai-sdk/openai-compatible", baseUrl: "https://api.z.ai/api/coding/paas/v4" }
};

export const PROVIDER_ENV_ALIASES = {
  "azure": { AZURE_OPENAI_API_KEY: "AZURE_API_KEY", AZURE_OPENAI_RESOURCE_NAME: "AZURE_RESOURCE_NAME" },
  "alibaba-token-plan": { QWEN_TOKEN_PLAN_API_KEY: "ALIBABA_TOKEN_PLAN_API_KEY" },
  "alibaba-token-plan-cn": { QWEN_TOKEN_PLAN_CN_API_KEY: "ALIBABA_TOKEN_PLAN_API_KEY" },
  "minimax-cn": { MINIMAX_CN_API_KEY: "MINIMAX_API_KEY" },
  "minimax-cn-coding-plan": { MINIMAX_CN_API_KEY: "MINIMAX_API_KEY" },
  "zai": { ZAI_API_KEY: "ZHIPU_API_KEY" },
  "zai-coding-plan": { ZAI_API_KEY: "ZHIPU_API_KEY" },
  "zhipuai-coding-plan": { ZAI_CODING_CN_API_KEY: "ZHIPU_API_KEY" },
  "github-copilot": { COPILOT_GITHUB_TOKEN: "GITHUB_TOKEN" },
  "meta": { META_API_KEY: "META_MODEL_API_KEY" },
  "xiaomi-token-plan-ams": { XIAOMI_TOKEN_PLAN_AMS_API_KEY: "XIAOMI_API_KEY" },
  "xiaomi-token-plan-cn": { XIAOMI_TOKEN_PLAN_CN_API_KEY: "XIAOMI_API_KEY" },
  "xiaomi-token-plan-sgp": { XIAOMI_TOKEN_PLAN_SGP_API_KEY: "XIAOMI_API_KEY" },
  "cloudflare-ai-gateway": { CLOUDFLARE_API_KEY: "CLOUDFLARE_API_TOKEN" },
  "google-vertex": { GOOGLE_CLOUD_PROJECT: "GOOGLE_VERTEX_PROJECT", GOOGLE_CLOUD_LOCATION: "GOOGLE_VERTEX_LOCATION" }
};
export function catalogProviderEnvironment(provider, env) {
  const result = { ...(env || {}) };
  for (const [piName, catalogName] of Object.entries(PROVIDER_ENV_ALIASES[provider] || {})) {
    if (!result[piName] && result[catalogName]) result[piName] = result[catalogName];
  }
  return result;
}

export function installCatalogProviderAdapters(models) {
  const providerBaselines = new Map();
  registryBaselines.set(models, providerBaselines);
  // OpenCode uses Bearer auth across all four documented API families.
  const googleOptions = (options) => ({ ...options, headers: {
    ...(options?.apiKey ? { Authorization: `Bearer ${options.apiKey}` } : {}), ...options?.headers
  } });
  for (const id of new Set([...Object.values(routes).map(r => r.provider), "amazon-bedrock"])) {
    providerBaselines.set(id, models.getModels(id));
  }
  for (const id of ["opencode", "opencode-go", "amazon-bedrock"]) {
    const original = models.getProvider(id);
    if (!original) throw new Error(`Required Pi provider is missing: ${id}`);
    const adapters = {
      "openai-completions": completions, "openai-responses": responses,
      "anthropic-messages": {
        stream: (model, context, options) => messages.stream(model, context, { ...googleOptions(options), headers: { ...googleOptions(options).headers, "x-api-key": null } }),
        streamSimple: (model, context, options) => messages.streamSimple(model, context, { ...googleOptions(options), headers: { ...googleOptions(options).headers, "x-api-key": null } })
      },
      "google-generative-ai": {
        stream: (model, context, options) => google.stream(model, context, googleOptions(options)),
        streamSimple: (model, context, options) => google.streamSimple(model, context, googleOptions(options))
      }
    };
    const api = id.startsWith("opencode")
      ? Object.fromEntries(Object.entries(adapters).map(([kind, streams]) => [kind, withOpenCodeSessionHeader(streams)]))
      : adapters;
    const extended = createProvider({ id, name: original.name, auth: original.auth, models: original.getModels(), api });
    models.setProvider({ ...original,
      stream: (model, context, options) => model.api === "bedrock-converse-stream"
        ? original.stream(model, context, options) : extended.stream(model, context, options),
      streamSimple: (model, context, options) => model.api === "bedrock-converse-stream"
        ? original.streamSimple(model, context, options) : extended.streamSimple(model, context, options)
    });
  }
}

export function verifiedCatalogResolution(config, models) {
  const providerBaselines = registryBaselines.get(models);
  const contract = config.catalogContract;
  // Catalog probes must not change a later exact built-in request with the same ID.
  if (!contract?.npm && !contract?.api && !contract?.shape) {
    const builtin = providerBaselines?.get(config.provider)?.find(m => m.id === config.model);
    const provider = builtin && models.getProvider(config.provider);
    if (provider && models.getModel(config.provider, config.model) !== builtin) {
      const others = provider.getModels().filter(m => m.id !== builtin.id);
      models.setProvider({ ...provider, getModels: () => [...others, builtin] });
    }
  }
  if (!contract || !["model", "provider", "official_provider_catalog"].includes(contract.provenance)) return null;
  const rule = routes[config.provider];
  const ordinaryBedrock = config.provider === "amazon-bedrock" && contract.npm === "@ai-sdk/amazon-bedrock";
  const mantle = config.provider === "amazon-bedrock" && contract.npm === "@ai-sdk/amazon-bedrock/mantle";
  if (!rule && !mantle && !ordinaryBedrock) return null;
  // Incomplete configurations still use the existing typed resolver failures.
  if (!contract.name?.trim() || typeof contract.reasoning !== "boolean" || !contract.input?.includes("text") ||
      !Number.isSafeInteger(contract.contextWindow) || contract.contextWindow <= 0 ||
      !Number.isSafeInteger(contract.maxTokens) || contract.maxTokens <= 0) return null;
  const fail = (reason) => ({ supported: false, reason, provider: config.provider, model: config.model });
  let api, baseUrl = contract.api?.replace(/\/+$/, ""), providerId = rule?.provider || "amazon-bedrock";
  if (mantle) {
    api = shapes[contract.shape];
    if (!["openai-completions", "openai-responses"].includes(api)) return fail("catalog_contract_ambiguous");
    if (!["https://bedrock-mantle.${AWS_REGION}.api.aws/v1", "https://bedrock-mantle.${AWS_REGION}.api.aws/openai/v1"].includes(baseUrl)) return fail("endpoint_conflict");
  } else if (ordinaryBedrock) {
    if (models.getModel("amazon-bedrock", config.model)) return null;
    api = "bedrock-converse-stream";
    if (contract.api) return null;
    baseUrl = models.getModels("amazon-bedrock").find(m => m.api === api)?.baseUrl;
    if (!baseUrl) return fail("pi_protocol_missing");
  } else if (rule.openCode) {
    if (contract.provenance === "provider") return null;
    api = config.provider === "opencode" && config.model === "mistral-large-4" && contract.npm === "@ai-sdk/mistral"
      ? "openai-completions" : openCodePackages[contract.npm];
    if (!api) return null;
    const path = api === "anthropic-messages" ? "anthropic/v1" : api === "google-generative-ai" ? "google/v1beta" : "openai/v1";
    if (baseUrl !== `${rule.openCode}/${path}`) return null;
  } else {
    api = rule.api;
    if (contract.npm !== rule.npm || baseUrl !== rule.baseUrl) return null;
  }
  if (contract.shape && shapes[contract.shape] !== api) return fail("protocol_conflict");
  const provider = models.getProvider(providerId);
  if (!provider) return fail("pi_provider_missing");
  const original = providerBaselines?.get(providerId)?.find(m => m.id === config.model && m.api === api);
  // Preserve Pi's exact wire-compatibility fields, while catalog metadata wins.
  const model = { ...original, id: config.model, name: contract.name, provider: providerId, api,
    baseUrl: api === "anthropic-messages" ? baseUrl.replace(/\/v1$/, "") : baseUrl,
    reasoning: contract.reasoning, input: contract.input, contextWindow: contract.contextWindow,
    maxTokens: contract.maxTokens, cost: original?.cost || { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } };
  verifiedModels.add(model);
  const others = provider.getModels().filter(m => m.id !== model.id);
  models.setProvider({ ...provider, getModels: () => [...others, model] });
  return { supported: true, provider: providerId, model: model.id, api, source: "verified_official_contract",
    reasoning: model.reasoning, input: model.input, contextWindow: model.contextWindow, maxTokens: model.maxTokens,
    toolCall: contract.toolCall === true };
}

export function verifiedExecutionModel(model, config) {
  if (model.provider !== "amazon-bedrock" || !model.baseUrl?.includes("${AWS_REGION}")) return model;
  const region = config.env?.AWS_REGION;
  if (!region || !/^[a-z0-9-]+$/.test(region)) throw Object.assign(new Error("AWS_REGION is required"), { code: "aws_region_required" });
  if (!config.apiKey && !config.env?.AWS_BEARER_TOKEN_BEDROCK) {
    throw Object.assign(new Error("Pi's OpenAI adapter requires a Bedrock API key (AWS_BEARER_TOKEN_BEDROCK) for Mantle"), { code: "bedrock_mantle_bearer_token_required" });
  }
  return { ...model, baseUrl: model.baseUrl.replace("${AWS_REGION}", region) };
}
export function verifiedStreamOptions(config) {
  return config.provider === "amazon-bedrock" && ["openai-responses", "openai-completions"].includes(config.api)
    ? { apiKey: config.apiKey || config.env?.AWS_BEARER_TOKEN_BEDROCK } : {};
}
