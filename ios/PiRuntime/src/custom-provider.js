import { createHash } from "node:crypto";
import { secureEndpoint } from "./credential-security.js";
import { createProvider } from "@earendil-works/pi-ai";
import { stream as completionsStream, streamSimple as completionsSimple } from "@earendil-works/pi-ai/api/openai-completions";
import { stream as responsesStream, streamSimple as responsesSimple } from "@earendil-works/pi-ai/api/openai-responses";
import { stream as anthropicStream, streamSimple as anthropicSimple } from "@earendil-works/pi-ai/api/anthropic-messages";
import { stream as geminiStream, streamSimple as geminiSimple } from "@earendil-works/pi-ai/api/google-generative-ai";

import { stream as mistralStream, streamSimple as mistralSimple } from "@earendil-works/pi-ai/api/mistral-conversations";

export const CUSTOM_PROVIDER = "yamabiko-custom";
const apis = {
  "openai-completions": { stream: completionsStream, streamSimple: completionsSimple },
  "openai-responses": { stream: responsesStream, streamSimple: responsesSimple },
  "anthropic-messages": { stream: anthropicStream, streamSimple: anthropicSimple },
  "google-generative-ai": { stream: geminiStream, streamSimple: geminiSimple },
  "mistral-conversations": { stream: mistralStream, streamSimple: mistralSimple }
};
const efforts = ["off", "minimal", "low", "medium", "high", "xhigh", "max"];

export function customProviderResolution(config, models) {
  const custom = config.customEndpoint;
  const failure = (reason) => ({ supported: false, reason, provider: config.provider, model: config.model });
  if (!custom || !apis[custom.protocol]) return failure("custom_protocol_required");
  let url;
  try { url = new URL(custom.baseUrl); } catch { return failure("custom_base_url_invalid"); }
  if (!secureEndpoint(url) || url.search || url.hash) return failure("custom_base_url_invalid");
  if (!custom.modelId?.trim() || custom.modelId !== config.model) return failure("custom_model_mismatch");
  if (![custom.contextWindow, custom.maxTokens].every((v) => Number.isSafeInteger(v) && v > 0) || custom.maxTokens > custom.contextWindow) return failure("custom_token_limits_invalid");
  if (typeof custom.reasoning !== "boolean" || typeof custom.toolCall !== "boolean" || typeof custom.vision !== "boolean") return failure("custom_capabilities_required");
  if (!efforts.includes(custom.reasoningEffort) || (!custom.reasoning && custom.reasoningEffort !== "off")) return failure("custom_reasoning_invalid");
  if (custom.thinkingBudget != null && (!Number.isSafeInteger(custom.thinkingBudget) || custom.thinkingBudget < 1024 || custom.thinkingBudget >= custom.maxTokens || custom.protocol !== "anthropic-messages" || !custom.reasoning || custom.reasoningEffort === "off")) return failure("custom_thinking_budget_invalid");
  if (custom.temperature != null && (!Number.isFinite(custom.temperature) || custom.temperature < 0 || custom.temperature > 2)) return failure("custom_temperature_invalid");
  if (!["max_tokens", "max_completion_tokens"].includes(custom.maxTokensField)) return failure("custom_max_tokens_field_invalid");
  // Configuration-specific identities prevent simultaneous runs or settings edits
  // from replacing another run's endpoint, model capabilities, or wire protocol.
  const provider = `yamabiko-custom-${createHash("sha256").update(JSON.stringify(custom)).digest("hex")}`;
  const compat = custom.protocol === "openai-completions" ? {
    maxTokensField: custom.maxTokensField,
    supportsStore: custom.supportsStore,
    supportsDeveloperRole: custom.supportsDeveloperRole,
    supportsReasoningEffort: custom.reasoning,
    supportsUsageInStreaming: custom.supportsUsageInStreaming
  } : custom.protocol === "openai-responses" ? { supportsDeveloperRole: custom.supportsDeveloperRole } : undefined;
  const model = {
    id: custom.modelId, name: custom.name || custom.modelId, provider,
    api: custom.protocol, baseUrl: custom.baseUrl,
    reasoning: custom.reasoning, input: custom.vision ? ["text", "image"] : ["text"],
    contextWindow: custom.contextWindow, maxTokens: custom.maxTokens,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    thinkingLevelMap: custom.reasoning ? { xhigh: "xhigh", max: "max" } : undefined,
    compat
  };
  if (!models.getProvider(provider)) models.setProvider(createProvider({
    id: provider, name: custom.name || "Custom endpoint", models: [model],
    auth: { apiKey: { name: "Custom endpoint API key", resolve: async () => ({ auth: {} }) } },
    api: { [model.api]: apis[model.api] }
  }));
  return { supported: true, provider, model: model.id, api: model.api, source: "user_configured", reasoning: model.reasoning, input: model.input, contextWindow: model.contextWindow, maxTokens: model.maxTokens, toolCall: custom.toolCall };
}

export function customStreamOptions(config) {
  if ((config.catalogProvider || config.provider) !== CUSTOM_PROVIDER) return {};
  const custom = config.customEndpoint;
  return {
    maxTokens: custom.maxTokens,
    ...(custom.temperature != null ? { temperature: custom.temperature } : {}),
    ...(custom.thinkingBudget != null ? { thinkingBudgets: { [custom.reasoningEffort]: custom.thinkingBudget } } : {})
  };
}
