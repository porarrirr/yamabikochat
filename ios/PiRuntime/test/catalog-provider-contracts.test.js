import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs";
import { builtinModels } from "@earendil-works/pi-ai/providers/all";
import { installCatalogProviderAdapters, verifiedCatalogResolution, verifiedExecutionModel,
  verifiedStreamOptions, catalogProviderEnvironment, PROVIDER_ENV_ALIASES } from "../src/catalog-provider-contracts.js";
const fixtures = JSON.parse(fs.readFileSync(new URL("fixtures/verified-provider-models.json", import.meta.url)));
function registry() { const models = builtinModels(); installCatalogProviderAdapters(models); return models; }

test("verified catalog routes preserve model metadata and exact native built-ins across probes", () => {
  const models = registry();
  const originals = new Map(models.getProviders().map(p => [p.id, p.getModels()]));
  for (const { config, expected } of fixtures) {
    const r = verifiedCatalogResolution(config, models);
    assert.equal(r?.supported, true, JSON.stringify(config));
    assert.equal(r.provider, expected.provider);
    assert.equal(r.api, expected.api);
    const m = models.getModel(r.provider, config.model), c = config.catalogContract;
    assert.equal(m.id, config.model);
    assert.equal(m.contextWindow, c.contextWindow);
    assert.equal(m.maxTokens, c.maxTokens);
    assert.equal(m.reasoning, c.reasoning);
    assert.deepEqual(m.input, c.input);
    assert.equal(r.toolCall, c.toolCall === true);
    assert.equal(m.baseUrl, r.api === "anthropic-messages" ? c.api.replace(/\/v1$/, "") : c.api);
  }
  for (const [provider, originalsForProvider] of originals) {
    for (const m of originalsForProvider) {
      verifiedCatalogResolution({ provider, model: m.id }, models);
      assert.deepEqual(models.getModel(provider, m.id), m, `${provider}/${m.id}`);
    }
  }
});

test("catalog credential aliases authenticate the exact Pi provider and stay provider-scoped", async () => {
  const providers = {
    "azure": "azure-openai-responses", "alibaba-token-plan": "qwen-token-plan", "alibaba-token-plan-cn": "qwen-token-plan-cn",
    "minimax-cn": "minimax-cn", "minimax-cn-coding-plan": "minimax-cn", "zai": "zai", "zai-coding-plan": "zai",
    "zhipuai-coding-plan": "zai-coding-cn", "meta": "meta", "github-copilot": "github-copilot",
    "xiaomi-token-plan-ams": "xiaomi-token-plan-ams", "xiaomi-token-plan-cn": "xiaomi-token-plan-cn",
    "xiaomi-token-plan-sgp": "xiaomi-token-plan-sgp", "cloudflare-ai-gateway": "cloudflare-ai-gateway"
  };
  for (const [catalog, aliases] of Object.entries(PROVIDER_ENV_ALIASES)) {
    const source = Object.fromEntries(Object.values(aliases).map(k => [k, "test-value"]));
    const result = catalogProviderEnvironment(catalog, source);
    for (const [piName, catalogName] of Object.entries(aliases)) {
      assert.equal(result[piName], source[catalogName]);
      assert.equal(source[piName], undefined);
      assert.equal(catalogProviderEnvironment(catalog, { ...source, [piName]: "explicit" })[piName], "explicit");
      assert.equal(catalogProviderEnvironment("unrelated", source)[piName], undefined);
    }
    if (providers[catalog]) {
      const auth = await builtinModels().getAuth(providers[catalog], { env: {
        ...result, CLOUDFLARE_ACCOUNT_ID: "account", CLOUDFLARE_GATEWAY_ID: "gateway"
      } });
      if (catalog === "cloudflare-ai-gateway") assert.equal(auth.auth.headers["cf-aig-authorization"], "Bearer test-value");
      else assert.equal(auth.auth.apiKey, "test-value", catalog);
    }
  }
});

test("verified providers keep each protocol, endpoint, model ID and auth on stream failure", async () => {
  const originalFetch = globalThis.fetch;
  try {
    for (const { config, expected } of fixtures) {
      const models = registry();
      const c = { ...config, apiKey: "test-key", env: { AWS_REGION: "us-east-2", AWS_BEARER_TOKEN_BEDROCK: "test-key" } };
      const r = verifiedCatalogResolution(c, models);
      const m = verifiedExecutionModel(models.getModel(r.provider, c.model), c);
      let calls = 0;
      const fetcher = async (input, init) => {
        calls++;
        const request = new Request(input, init), url = new URL(request.url), body = await request.json();
        const baseUrl = c.catalogContract.api.replace("${AWS_REGION}", "us-east-2");
        assert.equal(url.origin, new URL(baseUrl).origin);
        const suffix = expected.api === "openai-completions" ? "/chat/completions"
          : expected.api === "openai-responses" ? "/responses"
          : expected.api === "anthropic-messages" ? "/messages" : `/models/${c.model}:streamGenerateContent`;
        assert.equal(url.pathname, `${baseUrl}${suffix}`.replace(url.origin, ""));
        if (expected.api !== "google-generative-ai") assert.equal(body.model, c.model);
        else assert.ok(body.contents);
        if (c.provider.startsWith("opencode") || c.provider === "amazon-bedrock") assert.equal(request.headers.get("authorization"), "Bearer test-key");
        if (c.provider.startsWith("opencode")) assert.equal(request.headers.get("x-opencode-session"), "conversation-id");
        return new Response(JSON.stringify({ error: { message: "test stop" } }), { status: 400, headers: { "content-type": "application/json" } });
      };
      globalThis.fetch = fetcher;
      const result = await models.streamSimple(m, { messages: [{ role: "user", content: "hello", timestamp: 1 }] }, {
        apiKey: c.apiKey, env: c.env, fetch: fetcher, maxRetries: 0, sessionId: "conversation-id",
        ...verifiedStreamOptions({ ...c, provider: r.provider, api: r.api })
      }).result();
      assert.equal(result.stopReason, "error");
      assert.equal(calls, 1, `${c.provider}/${c.model}: ${result.errorMessage}`);
    }
  } finally { globalThis.fetch = originalFetch; }
});

test("Bedrock Mantle requires its own explicit region and bearer token", () => {
  const f = fixtures.find(f => f.config.provider === "amazon-bedrock");
  const models = registry(), c = f.config;
  const r = verifiedCatalogResolution(c, models), m = models.getModel(r.provider, c.model);
  assert.throws(() => verifiedExecutionModel(m, c), { code: "aws_region_required" });
  assert.throws(() => verifiedExecutionModel(m, { ...c, env: { AWS_REGION: "us-east-1" } }), { code: "bedrock_mantle_bearer_token_required" });
  assert.equal(m.baseUrl, c.catalogContract.api);
});
