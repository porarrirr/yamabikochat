import test from "node:test";
import assert from "node:assert/strict";
import { createModels } from "@earendil-works/pi-ai";
import { customProviderResolution, customStreamOptions, CUSTOM_PROVIDER } from "../src/custom-provider.js";
import { installSarashinaProvider, sarashinaResolution, sarashinaModels } from "../src/sarashina-provider.js";
const endpoint = (protocol = "openai-completions") => ({ name: "Test", protocol, modelId: "custom-model", baseUrl: "https://custom.example/v1", contextWindow: 128000, maxTokens: 4096, reasoning: true, toolCall: true, vision: false, reasoningEffort: "high", maxTokensField: "max_tokens", supportsStore: false, supportsDeveloperRole: false, supportsUsageInStreaming: false, temperature: 0.3 });
const configFor = (customEndpoint) => ({ provider: CUSTOM_PROVIDER, model: customEndpoint.modelId, customEndpoint, thinkingLevel: customEndpoint.reasoningEffort });
const sse = (data) => new Response(data, { headers: { "content-type": "text/event-stream" } });
const chatSSE = 'data: {"choices":[{"index":0,"delta":{"content":"hello"},"finish_reason":"stop"}]}\n\ndata: {"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":1,"total_tokens":6}}\n\ndata: [DONE]\n\n';
const anthropicSSE = 'event: message_start\ndata: {"type":"message_start","message":{"id":"msg_test","type":"message","role":"assistant","content":[],"model":"custom-model","usage":{"input_tokens":5,"output_tokens":0}}}\n\nevent: content_block_start\ndata: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\nevent: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hello"}}\n\nevent: content_block_stop\ndata: {"type":"content_block_stop","index":0}\n\nevent: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":1}}\n\nevent: message_stop\ndata: {"type":"message_stop"}\n\n';
const responsesSSE = 'data: {"type":"response.output_item.added","output_index":0,"item":{"id":"msg_test","type":"message","role":"assistant","content":[]}}\n\ndata: {"type":"response.content_part.added","item_id":"msg_test","output_index":0,"content_index":0,"part":{"type":"output_text","text":""}}\n\ndata: {"type":"response.output_text.delta","item_id":"msg_test","output_index":0,"content_index":0,"delta":"hello"}\n\ndata: {"type":"response.completed","response":{"id":"resp_test","status":"completed","output":[],"usage":{"input_tokens":5,"output_tokens":1,"total_tokens":6}}}\n\n';
for (const protocol of ["anthropic-messages", "openai-completions", "openai-responses"]) test(`custom endpoint uses Pi ${protocol} serializer and parser`, async () => {
  const models = createModels(), custom = endpoint(protocol);
  if (protocol === "anthropic-messages") custom.thinkingBudget = 2048;
  const config = configFor(custom), resolution = customProviderResolution(config, models);
  assert.equal(resolution.supported, true); assert.equal(resolution.api, protocol);
  const model = models.getModel(resolution.provider, resolution.model);
  let body, url;
  const fetch = async (input, options) => { url = String(input); body = JSON.parse(options.body); return sse(protocol === "anthropic-messages" ? anthropicSSE : protocol === "openai-responses" ? responsesSSE : chatSSE); };
  const result = await models.streamSimple(model, { messages: [{ role: "user", content: "Hi", timestamp: 1 }] }, {
    apiKey: "test-key", fetch, reasoning: "high", ...customStreamOptions({ ...config, catalogProvider: CUSTOM_PROVIDER, provider: resolution.provider })
  }).result();
  assert.equal(result.stopReason, "stop", result.errorMessage); assert.equal(result.content.find((part) => part.type === "text")?.text, "hello");
  assert.equal(body.model, "custom-model");
  if (protocol !== "anthropic-messages") assert.equal(body.temperature, 0.3);
  else assert.equal(body.temperature, undefined);
  if (protocol === "openai-completions") {
    assert.equal(url, "https://custom.example/v1/chat/completions"); assert.equal(body.max_tokens, 4096); assert.equal(body.reasoning_effort, "high"); assert.equal(body.store, undefined); assert.equal(body.stream_options, undefined);
  } else if (protocol === "openai-responses") {
    assert.equal(url, "https://custom.example/v1/responses"); assert.equal(body.max_output_tokens, 4096); assert.equal(body.reasoning.effort, "high");
  } else assert.equal(body.thinking.budget_tokens, 2048);
});
test("custom settings reject incomplete, invalid and mismatched configurations without fallback", () => {
  const models = createModels();
  for (const [change, reason] of [[{ protocol: "" }, "custom_protocol_required"], [{ protocol: "guess" }, "custom_protocol_required"], [{ baseUrl: "file:///tmp/model" }, "custom_base_url_invalid"], [{ baseUrl: "https://user:pass@example.com" }, "custom_base_url_invalid"], [{ maxTokens: 0 }, "custom_token_limits_invalid"], [{ maxTokens: 200000 }, "custom_token_limits_invalid"], [{ reasoning: false }, "custom_reasoning_invalid"], [{ temperature: 3 }, "custom_temperature_invalid"], [{ thinkingBudget: 1024 }, "custom_thinking_budget_invalid"]]) assert.equal(customProviderResolution(configFor({ ...endpoint(), ...change }), models).reason, reason);
  assert.equal(customProviderResolution({ ...configFor(endpoint()), model: "other" }, models).reason, "custom_model_mismatch");
  assert.equal(models.getProviders().length, 0);
});
test("changing endpoint cannot replace an active custom model; extended efforts remain explicit", () => {
  const models = createModels();
  const first = customProviderResolution(configFor(endpoint()), models), second = customProviderResolution(configFor({ ...endpoint(), baseUrl: "https://other.example/v1" }), models);
  assert.notEqual(first.provider, second.provider); assert.equal(models.getModel(first.provider, first.model).baseUrl, "https://custom.example/v1");
  for (const effort of ["xhigh", "max"]) { const result = customProviderResolution(configFor({ ...endpoint(), reasoningEffort: effort }), models); assert.equal(models.getModel(result.provider, result.model).thinkingLevelMap[effort], effort); }
});
for (const { id, contextWindow, toolCall } of sarashinaModels) test(`official Sarashina contract and payload: ${id}`, async () => {
  const models = createModels(); installSarashinaProvider(models);
  for (const catalogContract of [undefined, { npm: "@ai-sdk/openai-compatible", api: "https://api.sarashina.ai/v1", shape: "chat-completions", toolCall }]) {
    const resolution = sarashinaResolution({ provider: "sarashina", model: id, catalogContract }, models);
    assert.equal(resolution.supported, true); assert.equal(resolution.contextWindow, contextWindow); assert.equal(resolution.maxTokens, 8000); assert.equal(resolution.toolCall, toolCall); assert.equal(resolution.reasoning, false);
  }
  let payload;
  const result = await models.streamSimple(models.getModel("sarashina", id), { systemPrompt: "System", messages: [{ role: "user", content: "Hi", timestamp: 1 }] }, { apiKey: "test", fetch: async (url, options) => { assert.equal(String(url), "https://api.sarashina.ai/v1/chat/completions"); payload = JSON.parse(options.body); return sse(chatSSE); } }).result();
  assert.equal(result.stopReason, "stop", result.errorMessage); assert.equal(result.usage.input, 5); assert.equal(payload.max_completion_tokens, 8000);
  for (const field of ["store", "stream_options", "reasoning_effort", "prompt_cache_key"]) assert.equal(payload[field], undefined);
  assert.equal(payload.messages[0].role, "system");
});
test("Sarashina rejects unknown models, protocol and endpoint overrides", () => {
  const models = createModels(); installSarashinaProvider(models);
  assert.equal(sarashinaResolution({ provider: "sarashina", model: "unknown" }, models).reason, "pi_model_missing");
  for (const [catalogContract, reason] of [[{ shape: "responses" }, "protocol_conflict"], [{ api: "https://other.example/v1" }, "endpoint_conflict"], [{ npm: "unknown" }, "catalog_contract_ambiguous"], [{ reasoning: true }, "catalog_contract_conflict"], [{ maxTokens: 99999 }, "catalog_contract_conflict"]]) assert.equal(sarashinaResolution({ provider: "sarashina", model: "sarashina3-mini", catalogContract }, models).reason, reason);
});
