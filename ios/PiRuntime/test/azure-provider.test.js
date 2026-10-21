import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs";
import { builtinModels } from "@earendil-works/pi-ai/providers/all";
import { installAzureProvider, azureCatalogResolution, azureExecutionModel, azureStreamOptions, AZURE_PROVIDER } from "../src/azure-provider.js";
const fixture = JSON.parse(fs.readFileSync(new URL("fixtures/azure-models.json", import.meta.url)));
function configuration(id, provider = "azure") {
  const m = fixture[id];
  return { provider, model: id, env: { AZURE_RESOURCE_NAME: "my-resource", AZURE_OPENAI_API_KEY: "test-key" },
    catalogContract: { ...m.provider, provenance: "model", name: m.name, reasoning: m.reasoning,
      input: m.modalities.input, contextWindow: m.limit.context, maxTokens: m.limit.output, toolCall: m.tool_call } };
}
function registry() { const models = builtinModels(); installAzureProvider(models); return models; }

test("all Azure model contracts preserve metadata for catalog and Pi identities", () => {
  for (const provider of ["azure", AZURE_PROVIDER]) {
    const models = registry();
    for (const id of Object.keys(fixture)) {
      const c = configuration(id, provider), r = azureCatalogResolution(c, models);
      assert.equal(r.supported, true, id);
      assert.equal(r.api, fixture[id].provider.npm === "@ai-sdk/anthropic" ? "anthropic-messages" : "openai-completions");
      assert.equal(r.provider, AZURE_PROVIDER);
      assert.deepEqual(r.input, c.catalogContract.input);
      assert.equal(r.contextWindow, c.catalogContract.contextWindow);
      assert.equal(r.maxTokens, c.catalogContract.maxTokens);
      assert.equal(r.reasoning, c.catalogContract.reasoning);
      assert.equal(r.toolCall, c.catalogContract.toolCall === true);
      assert.equal(models.getModel(AZURE_PROVIDER, id).baseUrl, c.catalogContract.api);
    }
    assert.equal(models.getModel(AZURE_PROVIDER, "gpt-5.2").api, "azure-openai-responses");
  }
});

test("Azure fails closed for missing or conflicting per-model contracts", () => {
  const models = registry();
  for (const [edit, reason] of [
    [{ provenance: "provider" }, "catalog_contract_ambiguous"],
    [{ npm: "unknown" }, "catalog_contract_ambiguous"],
    [{ shape: "responses" }, "protocol_conflict"],
    [{ api: "https://api.anthropic.com" }, "endpoint_conflict"],
    [{ api: undefined }, "endpoint_conflict"],
    [{ maxTokens: undefined }, "catalog_contract_incomplete"],
    [{ input: [] }, "catalog_contract_incomplete"]
  ]) {
    const c = configuration("claude-fable-5"); Object.assign(c.catalogContract, edit);
    assert.equal(azureCatalogResolution(c, models).reason, reason);
    assert.equal(models.getModel(AZURE_PROVIDER, c.model), undefined);
  }
});

test("Azure execution uses per-run resource names and requires Entra for Mythos", () => {
  const models = registry(), c = configuration("claude-mythos-5");
  azureCatalogResolution(c, models);
  const m = models.getModel(AZURE_PROVIDER, c.model);
  assert.throws(() => azureExecutionModel(m, c), { code: "azure_entra_id_required" });
  c.env.AZURE_AUTH_TOKEN = "test-entra";
  const a = azureExecutionModel(m, c);
  const b = azureExecutionModel(m, { ...c, env: { ...c.env, AZURE_RESOURCE_NAME: "another" } });
  assert.equal(a.baseUrl, "https://my-resource.services.ai.azure.com/anthropic");
  assert.equal(b.baseUrl, "https://another.services.ai.azure.com/anthropic");
  assert.equal(m.baseUrl, fixture[c.model].provider.api);
  assert.throws(() => azureExecutionModel(m, { ...c, env: {} }), { code: "azure_resource_name_required" });
  assert.throws(() => azureExecutionModel(m, { ...c, env: { AZURE_RESOURCE_NAME: "other/host" } }), { code: "azure_resource_name_required" });
});

const context = { messages: [{ role: "user", content: "hello", timestamp: 1 }] };
function responseFor(api) {
  if (api === "anthropic-messages") return new Response([
    ['message_start', { type: 'message_start', message: { id: 'msg', type: 'message', role: 'assistant', model: 'test', content: [], usage: { input_tokens: 3, output_tokens: 0 } } }],
    ['content_block_start', { type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } }],
    ['content_block_delta', { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'hello' } }],
    ['content_block_stop', { type: 'content_block_stop', index: 0 }],
    ['message_delta', { type: 'message_delta', delta: { stop_reason: 'end_turn' }, usage: { output_tokens: 2 } }],
    ['message_stop', { type: 'message_stop' }]
  ].map(([event, data]) => `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`).join(''), { headers: { 'content-type': 'text/event-stream' } });
  return new Response(`data: ${JSON.stringify({ id: 'chat', choices: [{ index: 0, delta: { role: 'assistant', content: 'hello' }, finish_reason: null }] })}\n\ndata: ${JSON.stringify({ id: 'chat', choices: [{ index: 0, delta: {}, finish_reason: 'stop' }], usage: { prompt_tokens: 3, completion_tokens: 2, total_tokens: 5 } })}\n\ndata: [DONE]\n\n`, { headers: { 'content-type': 'text/event-stream' } });
}

test("standard Pi adapters send exact Azure paths, version, auth, model and preserve stream usage", async () => {
  for (const id of Object.keys(fixture)) {
    for (const tokenAuth of [false, true]) {
      if (id.includes('mythos') && !tokenAuth) continue;
      const models = registry(), c = configuration(id);
      if (tokenAuth) { c.env.AZURE_AUTH_TOKEN = 'test-entra'; delete c.env.AZURE_OPENAI_API_KEY; }
      const r = azureCatalogResolution(c, models), m = azureExecutionModel(models.getModel(AZURE_PROVIDER, id), c);
      let calls = 0;
      const result = await models.streamSimple(m, context, {
        env: c.env, ...azureStreamOptions({ ...c, provider: AZURE_PROVIDER }),
        fetch: async (url, init) => {
          calls++;
          const target = new URL(url), headers = new Headers(init.headers), body = JSON.parse(init.body);
          assert.equal(target.hostname, 'my-resource.services.ai.azure.com');
          assert.equal(target.pathname, r.api === 'anthropic-messages' ? '/anthropic/v1/messages' : '/models/chat/completions');
          assert.equal(body.model, id);
          assert.equal(body.stream, true);
          if (['claude-fable-5', 'claude-fable-5-1', 'claude-mythos-5'].includes(id)) assert.equal(body.thinking.type, 'adaptive');
          if (r.api === 'openai-completions') {
            assert.equal(body.store, undefined);
            assert.equal(body.stream_options, undefined);
            assert.equal(body.reasoning_effort, undefined);
          }
          if (tokenAuth) { assert.equal(headers.get('authorization'), 'Bearer test-entra'); assert.equal(headers.get('x-api-key'), null); }
          else assert.equal(headers.get(r.api === 'anthropic-messages' ? 'x-api-key' : 'api-key'), 'test-key');
          if (r.api === 'openai-completions') assert.equal(target.searchParams.get('api-version'), '2024-05-01-preview');
          return responseFor(r.api);
        }
      }).result();
      assert.equal(result.stopReason, 'stop', `${id}: ${result.errorMessage}`);
      assert.equal(result.content[0].text, 'hello');
      assert.equal(result.usage.input, 3);
      assert.equal(result.usage.output, 2);
      assert.equal(calls, 1);
    }
  }
});


test("Azure stream failures stop on the selected Pi protocol without fallback", async () => {
  for (const id of ["claude-haiku-4-5", "deepseek-v4-pro"]) {
    const models = registry(), c = configuration(id);
    azureCatalogResolution(c, models);
    const m = azureExecutionModel(models.getModel(AZURE_PROVIDER, id), c);
    let calls = 0;
    const result = await models.streamSimple(m, context, {
      env: c.env, maxRetries: 0,
      fetch: async () => {
        calls++;
        return new Response(JSON.stringify({ error: { type: "authentication_error", message: "test rejection" } }),
          { status: 401, headers: { "content-type": "application/json" } });
      }
    }).result();
    assert.equal(result.stopReason, "error");
    assert.equal(calls, 1);
  }
});

const responseContract = {
  npm: '@ai-sdk/azure', provenance: 'provider', name: 'GPT Chat Latest',
  reasoning: true, input: ['text', 'image', 'pdf'], contextWindow: 400000, maxTokens: 128000, toolCall: true
};
test('verified GPT Chat Latest uses the existing Pi Azure Responses adapter with fixed reasoning', async () => {
  for (const provider of ['azure', AZURE_PROVIDER]) {
    for (const tokenAuth of [false, true]) {
      const models = registry();
      const c = { provider, model: 'gpt-chat-latest', catalogContract: responseContract,
        env: { AZURE_OPENAI_RESOURCE_NAME: 'my-resource', AZURE_OPENAI_API_KEY: 'test-key', ...(tokenAuth ? { AZURE_AUTH_TOKEN: 'test-token' } : {}) } };
      const r = azureCatalogResolution(c, models);
      assert.equal(r.supported, true);
      assert.equal(r.api, 'azure-openai-responses');
      const m = models.getModel(AZURE_PROVIDER, c.model);
      let calls = 0;
      const result = await models.streamSimple(m, context, {
        env: c.env, ...azureStreamOptions({ ...c, provider: AZURE_PROVIDER, api: r.api, thinkingLevel: 'high' }),
        fetch: async (url, init) => {
          calls++;
          assert.equal(new URL(url).hostname, 'my-resource.openai.azure.com');
          assert.equal(new URL(url).pathname, '/openai/v1/responses');
          const headers = new Headers(init.headers), body = JSON.parse(init.body);
          assert.equal(body.model, 'gpt-chat-latest');
          assert.equal(body.reasoning, undefined);
          if (tokenAuth) {
            assert.equal(headers.get('authorization'), 'Bearer test-token');
            assert.equal(headers.get('api-key'), null);
          } else assert.equal(headers.get('api-key'), 'test-key');
          return new Response('event: response.completed\ndata: ' + JSON.stringify({ type: 'response.completed', response: {
            id: 'resp', status: 'completed', output: [], usage: { input_tokens: 3, output_tokens: 2, total_tokens: 5 }
          } }) + '\n\n', { headers: { 'content-type': 'text/event-stream' } });
        }
      }).result();
      assert.equal(result.stopReason, 'stop', result.errorMessage);
      assert.equal(calls, 1);
    }
  }
});


test("Azure embedding models stay visible with an operation-specific unsupported reason", () => {
  for (const provider of ["azure", AZURE_PROVIDER]) {
    for (const model of ["cohere-embed-v3-english", "cohere-embed-v3-multilingual", "cohere-embed-v-4-0", "cohere-embed-v4-0"]) {
      assert.equal(azureCatalogResolution({ provider, model }, registry()).reason, "model_operation_unsupported");
    }
  }
});
