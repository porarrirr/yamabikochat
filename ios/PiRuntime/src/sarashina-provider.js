// Official contract: https://docs.sarashina.ai/api-reference/chat-completions
// Model limits: https://docs.sarashina.ai/models
// Drift check: scripts/check-sarashina-contract.py
import { createProvider, envApiKeyAuth } from "@earendil-works/pi-ai";
import { stream, streamSimple } from "@earendil-works/pi-ai/api/openai-completions";
export const sarashinaModels = [
  { id: "sarashina3-mini", contextWindow: 128000, toolCall: true },
  { id: "sarashina3-nano", contextWindow: 128000, toolCall: true },
  { id: "sarashina3-guard", contextWindow: 64000, toolCall: false }
];
export function installSarashinaProvider(models) {
  models.setProvider(createProvider({
    id: "sarashina", name: "Sarashina",
    auth: { apiKey: envApiKeyAuth("Sarashina API key", ["SARASHINA_API_KEY"]) },
    models: sarashinaModels.map(({ id, contextWindow }) => ({
      id, name: id, provider: "sarashina", api: "openai-completions",
      baseUrl: "https://api.sarashina.ai/v1", reasoning: false, input: ["text"],
      contextWindow, maxTokens: 8000,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      compat: { supportsStore: false, supportsDeveloperRole: false, supportsReasoningEffort: false,
        supportsUsageInStreaming: false, supportsStrictMode: false, maxTokensField: "max_completion_tokens" }
    })),
    api: { "openai-completions": { stream, streamSimple } }
  }));
}
export function sarashinaResolution(config, models) {
  const model = models.getModel("sarashina", config.model);
  const failure = (reason) => ({ supported: false, reason, provider: config.provider, model: config.model });
  if (!model) return failure("pi_model_missing");
  const contract = config.catalogContract;
  if (contract?.npm && !["@ai-sdk/openai", "@ai-sdk/openai-compatible"].includes(contract.npm)) return failure("catalog_contract_ambiguous");
  if (contract?.shape && !["chat", "chat-completions", "chat_completions"].includes(contract.shape)) return failure("protocol_conflict");
  if (contract?.api && ![model.baseUrl, `${model.baseUrl}/chat/completions`].includes(contract.api.replace(/\/+$/, ""))) return failure("endpoint_conflict");
  if (contract && ((contract.reasoning != null && contract.reasoning !== model.reasoning) ||
      (contract.input != null && JSON.stringify(contract.input) !== JSON.stringify(model.input)) ||
      (contract.contextWindow != null && contract.contextWindow !== model.contextWindow) ||
      (contract.maxTokens != null && contract.maxTokens !== model.maxTokens))) return failure("catalog_contract_conflict");
  if (config.thinkingLevel && config.thinkingLevel !== "off") return failure("sarashina_reasoning_unsupported");
  return { supported: true, provider: model.provider, model: model.id, api: model.api, source: "verified_official_contract",
    reasoning: false, input: model.input, contextWindow: model.contextWindow, maxTokens: model.maxTokens,
    toolCall: sarashinaModels.find((entry) => entry.id === model.id).toolCall && (contract ? contract.toolCall === true : true) };
}
