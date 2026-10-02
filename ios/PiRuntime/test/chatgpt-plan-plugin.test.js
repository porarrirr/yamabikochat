import assert from "node:assert/strict";
import test from "node:test";
import { generateKeyPair, exportJWK, SignJWT } from "jose";
import { createModels, InMemoryCredentialStore } from "@earendil-works/pi-ai";
import { createChatGPTPlanPlugin, CHATGPT_PLAN_PROVIDER, chatGPTPlanPayload, chatGPTPlanCompleted, parseChatGPTCallback, startChatGPTCallback } from "../src/chatgpt-plan-plugin.js";

const issuer = "https://auth.openai.com";
const hostId = "urn:uuid:12345678-1234-4123-8123-123456789abc";
const clientId = "oaiapp_test_registration";
const { publicKey, privateKey } = await generateKeyPair("RS256");
const jwk = { ...await exportJWK(publicKey), alg: "RS256", kid: "test" };
const scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct";

async function harness(options = {}) {
  let authorization, pending, resolveCallback, refreshes = 0;
  const calls = [], registrations = [];
  const credentials = new InMemoryCredentialStore();
  const plugin = createChatGPTPlanPlugin({
    now: options.now ?? Date.now,
    callbackListener: async value => {
      pending = value;
      return { redirectURI: "http://127.0.0.1:45678/auth/callback", result: new Promise(resolve => { resolveCallback = resolve; }), close() {} };
    },
    fetch: async (url, init) => {
      calls.push({ url: String(url), init });
      if (String(url).endsWith("openid-configuration")) return Response.json({
        issuer, authorization_endpoint: `${issuer}/api/accounts/authorize`, token_endpoint: `${issuer}/api/accounts/oauth/token`,
        jwks_uri: `${issuer}/.well-known/jwks.json`, revocation_endpoint: `${issuer}/oauth/revoke`
      });
      if (String(url).endsWith("jwks.json")) return Response.json({ keys: [jwk] });
      if (String(url).endsWith("oauth/token")) {
        const body = init.body;
        const refresh = body.get("grant_type") === "refresh_token";
        if (refresh) refreshes++;
        const nonce = options.nonce ?? authorization.searchParams.get("nonce");
        const token = await new SignJWT({ nonce, email: "user@example.com" })
          .setProtectedHeader({ alg: "RS256", kid: "test" }).setIssuer(options.issuer ?? issuer)
          .setAudience(options.audience ?? clientId).setSubject(options.subject ?? "subject-1")
          .setIssuedAt().setExpirationTime(options.expiry ?? "1h").sign(privateKey);
        return Response.json({ access_token: refresh ? "rotated-access" : "access", refresh_token: refresh ? "rotated-refresh" : "refresh",
          earliest_refresh_at: refresh ? options.refreshEarliest : options.earliest, expires_in: 3600, token_type: "Bearer", scope: options.scopes ?? scopes, id_token: options.signature ? token.slice(0, -10) + "tampered00" : token });
      }
      if (String(url).endsWith("/v1/models")) return Response.json({ models: options.catalog ?? [
        { slug: "future-unverified-model", display_name: "Future Model", visibility: "list" },
        { slug: "gpt-6-sol", display_name: "Account Sol", visibility: "list" },
        { slug: "hidden", display_name: "Hidden", visibility: "hidden" }
      ] });
      if (String(url).endsWith("/oauth/revoke")) return new Response(null, { status: options.revocationStatus ?? 200 });
      throw new Error(`Unexpected endpoint ${url}`);
    }
  });
  const models = createModels({ credentials });
  models.setProvider(plugin.provider);
  const interaction = {
    signal: new AbortController().signal,
    prompt: async () => assert.fail("No manual-code fallback"),
    notify(event) {
      if (event.type !== "auth_url") return;
      authorization = new URL(event.url);
      const callback = new URL("http://127.0.0.1:45678/auth/callback");
      callback.search = new URLSearchParams({ code: "code", state: pending.state, client_id: options.callbackClient ?? clientId });
      resolveCallback(parseChatGPTCallback(callback, pending));
    }
  };
  return {
    plugin, models, credentials, calls, registrations,
    authorization: () => authorization,
    refreshes: () => refreshes,
    login: registration => plugin.withLoginContext({ hostId, registration, onRegistration: async value => { registrations.push(value); } },
      () => models.login(CHATGPT_PLAN_PROVIDER, "oauth", interaction))
  };
}

test("Pi provider uses SIWC registration, verified identity, granted scopes and public Responses metadata", async () => {
  const h = await harness();
  const credential = await h.login();
  assert.equal(credential.earliestRefreshAt, undefined);
  assert.equal(credential.expires, credential.accessExpiresAt - 180_000);
  assert.equal(credential.contract, "siwc-v1");
  assert.equal(credential.subject, "subject-1");
  assert.equal(credential.email, "user@example.com");
  assert.equal(credential.clientId, clientId);
  assert.equal(h.authorization().searchParams.get("client_id"), "dynamic_agent_client");
  assert.equal(h.authorization().searchParams.get("agent_name_hint"), "YamabikoChat");
  assert.equal(h.authorization().searchParams.get("ext_agent_host_id"), hostId);
  assert.equal(h.authorization().searchParams.get("resource"), "https://api.openai.com/v1");
  const exchange = h.calls.find(call => call.init.body?.get("grant_type") === "authorization_code").init.body;
  assert.equal(exchange.get("client_id"), clientId);
  assert.equal(exchange.get("redirect_uri"), h.authorization().searchParams.get("redirect_uri"));
  assert.equal(h.registrations[0].clientId, clientId);
  assert.equal(h.plugin.profile(credential).planUsageEnabled, true);
  const catalog = await h.plugin.catalog(credential, new AbortController().signal);
  assert.deepEqual(catalog.map(model => model.id), ["future-unverified-model", "gpt-6-sol"]);
  assert.equal(catalog[0].supported, false);
  assert.equal(catalog[0].reason, "pi_model_missing");
  assert.equal(catalog[1].supported, true);
  assert.equal(catalog[1].name, "Account Sol");
  const model = h.models.getModel(CHATGPT_PLAN_PROVIDER, "gpt-6-sol");
  assert.equal(model.api, "openai-responses");
  assert.equal(model.baseUrl, "https://api.openai.com/v1");
});

test("returning sign-in reuses registration and retains ID token as account hint", async () => {
  const h = await harness();
  const credential = await h.login();
  await h.login(credential);
  const params = h.authorization().searchParams;
  assert.equal(params.get("client_id"), clientId);
  assert.equal(params.get("agent_name_hint"), null);
  assert.equal(params.get("id_token_hint"), credential.idToken);
  assert.equal(params.get("ext_agent_host_id"), hostId);
});

for (const [name, options] of [
  ["nonce mismatch", { nonce: "wrong" }], ["issuer mismatch", { issuer: "https://evil.invalid" }],
  ["audience mismatch", { audience: "other-client" }], ["expired identity", { expiry: "-1h" }],
  ["invalid signature", { signature: true }]
]) test(`rejects ${name} without completing login`, async () => {
  const h = await harness(options);
  await assert.rejects(h.login());
  assert.equal(await h.credentials.read(CHATGPT_PLAN_PROVIDER), undefined);
});

test("identity-only grant never authorizes inference or model discovery", async () => {
  const h = await harness({ scopes: "openid email profile offline_access" });
  const credential = await h.login();
  assert.equal(h.plugin.profile(credential).planUsageEnabled, false);
  await assert.rejects(h.models.getAuth(CHATGPT_PLAN_PROVIDER), /プラン/);
  await assert.rejects(h.plugin.catalog(credential, new AbortController().signal), /プラン/);
  assert.equal(h.calls.some(call => call.url.endsWith("/v1/models")), false);
});

test("Pi serializes concurrent refreshes and uses the issued client with resource", async () => {
  const h = await harness();
  const credential = await h.login();
  await h.credentials.modify(CHATGPT_PLAN_PROVIDER, async () => ({ ...credential, expires: 0 }));
  const results = await Promise.all(Array.from({ length: 5 }, () => h.models.getAuth(CHATGPT_PLAN_PROVIDER)));
  assert.equal(h.refreshes(), 1);
  assert.ok(results.every(result => result.auth.apiKey === "rotated-access"));
  const body = h.calls.find(call => call.init.body?.get("grant_type") === "refresh_token").init.body;
  assert.equal(body.get("client_id"), clientId);
  assert.equal(body.get("resource"), "https://api.openai.com/v1");
  assert.equal(body.get("scope"), null);
  assert.equal((await h.credentials.read(CHATGPT_PLAN_PROVIDER)).refresh, "rotated-refresh");
});

test("revoke uses discovery endpoint, selected client ID and refresh token", async () => {
  const h = await harness();
  await h.plugin.revoke(await h.login(), new AbortController().signal);
  const body = h.calls.at(-1).init.body;
  assert.equal(body.get("client_id"), clientId);
  assert.equal(body.get("token_type_hint"), "refresh_token");
  assert.equal(body.get("token"), "refresh");
});

test("callback validates state before consent error and rejects client substitution", () => {
  const url = new URL("http://127.0.0.1:1455/auth/callback?state=wrong&error=access_denied");
  assert.throws(() => parseChatGPTCallback(url, { state: "expected" }), { code: "chatgpt_state_mismatch" });
  url.search = "state=expected&code=test&client_id=another";
  assert.throws(() => parseChatGPTCallback(url, { state: "expected", clientId }), { code: "chatgpt_client_mismatch" });
  url.search = "state=expected&code=test";
  assert.equal(parseChatGPTCallback(url, { state: "expected", clientId }).clientId, clientId);
  assert.throws(() => parseChatGPTCallback(url, { state: "expected" }));
});

test("loopback listener starts before authorization, ignores wrong state, and is cancelled cleanly", async () => {
  const controller = new AbortController();
  const listener = await startChatGPTCallback({ state: "expected" }, controller.signal);
  const result = listener.result;
  assert.match(listener.redirectURI, /^http:\/\/127\.0\.0\.1:\d+\/auth\/callback$/);
  assert.equal((await fetch(`${listener.redirectURI}?state=wrong&code=code&client_id=${clientId}`)).status, 400);
  assert.equal((await fetch(`${listener.redirectURI}?state=expected&code=code&client_id=${clientId}`)).status, 200);
  assert.equal((await result).clientId, clientId);
  listener.close();
  const second = await startChatGPTCallback({ state: "next" }, controller.signal);
  controller.abort(new Error("cancelled"));
  await assert.rejects(second.result, /cancelled/);
  second.close();
});

test("SIWC payload uses preview fields and groups local tools; hosted unsupported tools fail", () => {
  const payload = chatGPTPlanPayload({ input: [{ role: "system", content: "system" }], temperature: 0.2, max_output_tokens: 300,
    previous_response_id: "prior", store: true, stream: false,
    tools: [{ type: "function", name: "local", parameters: {} }, { type: "web_search" }] });
  assert.equal(payload.input[0].role, "developer");
  assert.equal(payload.store, false);
  assert.equal(payload.stream, true);
  assert.equal(payload.max_output_tokens, undefined);
  assert.equal(payload.temperature, undefined);
  assert.equal(payload.previous_response_id, undefined);
  assert.equal(payload.tools[1].type, "namespace");
  assert.equal(payload.tools[1].tools[0].name, "local");
  for (const type of ["tool_search", "mcp", "image_generation", "code_interpreter"]) {
    assert.throws(() => chatGPTPlanPayload({ input: [], tools: [{ type }] }), { code: "chatgpt_tool_unsupported" });
  }
});

for (const [name, terminal, expected] of [
  ["completed", { type: "response.completed", response: { id: "resp", status: "completed", output: [], usage: { input_tokens: 2, output_tokens: 1, total_tokens: 3 } } }, "stop"],
  ["usage failure after streaming", { type: "response.failed", response: { status: "failed", error: { code: "subscription_sharing_usage_limit_exceeded", message: "limit reached" } } }, "error"],
  ["interrupted stream", null, "error"],
  ["incomplete", { type: "response.incomplete", response: { status: "incomplete", incomplete_details: { reason: "content_filter" }, output: [] } }, "error"]
]) test(`standard Pi Responses adapter handles ${name} through the public endpoint`, async () => {
  const h = await harness();
  const credential = await h.login();
  await h.plugin.catalog(credential, new AbortController().signal);
  const model = h.models.getModel(CHATGPT_PLAN_PROVIDER, "gpt-6-sol");
  let requests = 0;
  const result = await h.models.complete(model, { messages: [{ role: "user", content: "hello", timestamp: Date.now() }] }, {
    maxRetries: 0,
    onPayload: chatGPTPlanPayload,
    fetch: async (url, init) => {
      requests++;
      assert.equal(String(url), "https://api.openai.com/v1/responses");
      assert.equal(new Headers(init.headers).get("authorization"), `Bearer ${credential.access}`);
      const payload = JSON.parse(init.body);
      assert.equal(payload.stream, true);
      assert.equal(payload.store, false);
      const events = [
        { type: "response.created", response: { id: "resp", status: "in_progress" } },
        ...(terminal ? [terminal] : [])
      ];
      return new Response(events.map(event => `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`).join(""), { headers: { "content-type": "text/event-stream" } });
    }
  });
  assert.equal(result.stopReason, expected);
  assert.equal(requests, 1);
  if (name === "usage failure after streaming") assert.match(result.errorMessage, /subscription_sharing_usage_limit_exceeded/);
});

for (const format of ["seconds", "date"]) test(`earliest refresh ${format} survives persistence and gates forced refresh`, async () => {
  let clock = Date.now();
  const start = clock;
  const earliestMs = Math.ceil((start + 59 * 60_000) / 1000) * 1000;
  const earliest = format === "seconds" ? earliestMs / 1000 : new Date(earliestMs).toISOString();
  const h = await harness({ now: () => clock, earliest, refreshEarliest: earliestMs / 1000 + 3600 });
  const credential = await h.login();
  assert.equal(credential.earliestRefreshAt, earliest);
  assert.equal(credential.accessExpiresAt, start + 3600_000);
  assert.equal(credential.expires, earliestMs);
  const saved = JSON.parse(JSON.stringify(credential));
  clock = earliestMs - 1;
  await h.credentials.modify(CHATGPT_PLAN_PROVIDER, async () => ({ ...saved, expires: 0 }));
  assert.equal((await h.models.getAuth(CHATGPT_PLAN_PROVIDER)).auth.apiKey, "access");
  assert.equal(h.refreshes(), 0);
  clock = earliestMs;
  await h.credentials.modify(CHATGPT_PLAN_PROVIDER, async current => ({ ...current, expires: 0 }));
  await h.models.getAuth(CHATGPT_PLAN_PROVIDER);
  assert.equal(h.refreshes(), 1);
  const rotated = await h.credentials.read(CHATGPT_PLAN_PROVIDER);
  assert.equal(rotated.refresh, "rotated-refresh");
  assert.equal(rotated.earliestRefreshAt, earliestMs / 1000 + 3600);
});

test("expired access never bypasses an earliest refresh time in the future", async () => {
  let clock = Date.now();
  const h = await harness({ now: () => clock, earliest: Math.ceil(clock / 1000) + 7200 });
  const credential = await h.login();
  clock = credential.accessExpiresAt;
  await h.credentials.modify(CHATGPT_PLAN_PROVIDER, async () => ({ ...credential, expires: 0 }));
  await assert.rejects(h.models.getAuth(CHATGPT_PLAN_PROVIDER), error => error.cause?.code === "chatgpt_refresh_not_yet_allowed");
  assert.equal(h.refreshes(), 0);
});

test("invalid earliest refresh time rejects credentials", async () => {
  const h = await harness({ earliest: "invalid" });
  await assert.rejects(h.login(), { code: "chatgpt_contract_invalid" });
});

const solCatalog = [{ slug: "gpt-6.1-sol", display_name: "GPT 6.1 Sol", visibility: "list" }];
const solContract = (overrides = {}) => ({
  provenance: "provider", npm: "@ai-sdk/openai", name: "GPT 6.1 Sol",
  reasoning: true, input: ["text", "image", "pdf"],
  contextWindow: 1_050_000, maxTokens: 128_000,
  reasoningEfforts: ["low", "medium", "high", "xhigh", "max"], toolCall: true,
  ...overrides
});

test("built-in slugs keep exact Pi metadata and ignore models.dev contracts", async () => {
  const h = await harness();
  const credential = await h.login();
  const catalog = await h.plugin.catalog(credential, new AbortController().signal, {
    "gpt-6-sol": { provenance: "model", npm: "@ai-sdk/anthropic", api: "https://evil.example/v1", shape: "messages", reasoning: false, input: ["text"], contextWindow: 1, maxTokens: 1 }
  });
  const entry = catalog.find(model => model.id === "gpt-6-sol");
  assert.equal(entry.supported, true);
  assert.equal(entry.source, "pi_builtin");
  assert.equal(h.plugin.modelSource("gpt-6-sol"), "pi_builtin");
  const model = h.models.getModel(CHATGPT_PLAN_PROVIDER, "gpt-6-sol");
  assert.equal(model.api, "openai-responses");
  assert.equal(model.baseUrl, "https://api.openai.com/v1");
});

test("account slug missing from Pi is enabled by a valid models.dev contract", async () => {
  const h = await harness({ catalog: solCatalog });
  const credential = await h.login();
  const catalog = await h.plugin.catalog(credential, new AbortController().signal, { "gpt-6.1-sol": solContract() });
  const entry = catalog.find(model => model.id === "gpt-6.1-sol");
  assert.equal(entry.supported, true);
  assert.equal(entry.reason, null);
  assert.equal(entry.source, "models_dev_contract");
  assert.deepEqual(entry.supportedThinkingLevels, ["low", "medium", "high", "xhigh", "max"]);
  assert.equal(h.plugin.modelSource("gpt-6.1-sol"), "models_dev_contract");
  const model = h.models.getModel(CHATGPT_PLAN_PROVIDER, "gpt-6.1-sol");
  assert.equal(model.name, "GPT 6.1 Sol");
  assert.equal(model.api, "openai-responses");
  assert.equal(model.provider, CHATGPT_PLAN_PROVIDER);
  assert.equal(model.baseUrl, "https://api.openai.com/v1");
  assert.equal(model.reasoning, true);
  assert.deepEqual(model.input, ["text", "image"]);
  assert.deepEqual(model.cost, { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 });
  assert.equal(model.contextWindow, 1_050_000);
  assert.equal(model.maxTokens, 128_000);
  assert.equal(model.thinkingLevelMap.off, null);
  assert.equal(model.thinkingLevelMap.max, "max");
});

test("a contract effort of none maps the off thinking level", async () => {
  const h = await harness({ catalog: solCatalog });
  const credential = await h.login();
  const catalog = await h.plugin.catalog(credential, new AbortController().signal, {
    "gpt-6.1-sol": solContract({ reasoningEfforts: ["none", "low", "medium"] })
  });
  const entry = catalog.find(model => model.id === "gpt-6.1-sol");
  assert.equal(entry.supported, true);
  assert.deepEqual(entry.supportedThinkingLevels, ["low", "medium"]);
  const model = h.models.getModel(CHATGPT_PLAN_PROVIDER, "gpt-6.1-sol");
  assert.equal(model.thinkingLevelMap.off, "none");
  assert.equal(model.thinkingLevelMap.high, null);
});

test("account slug without a contract stays disabled", async () => {
  const h = await harness({ catalog: solCatalog });
  const credential = await h.login();
  const catalog = await h.plugin.catalog(credential, new AbortController().signal);
  const entry = catalog.find(model => model.id === "gpt-6.1-sol");
  assert.equal(entry.supported, false);
  assert.equal(entry.reason, "pi_model_missing");
  assert.equal(entry.source, null);
  assert.equal(h.plugin.modelSource("gpt-6.1-sol"), null);
});

for (const [name, contract, reason] of [
  ["completions shape", solContract({ shape: "completions" }), "protocol_conflict"],
  ["a non-OpenAI npm package", solContract({ npm: "@ai-sdk/anthropic" }), "protocol_conflict"],
  ["shape and npm disagree", solContract({ shape: "responses", npm: "@ai-sdk/anthropic" }), "protocol_conflict"],
  ["a foreign api endpoint", solContract({ api: "https://example.invalid/v1" }), "endpoint_conflict"],
  ["reasoning without efforts", solContract({ reasoningEfforts: [] }), "catalog_contract_incomplete"],
  ["an unknown effort", solContract({ reasoningEfforts: ["low", "ultra"] }), "catalog_contract_incomplete"],
  ["missing token limits", solContract({ contextWindow: undefined, maxTokens: undefined }), "catalog_contract_incomplete"],
  ["an untrusted provenance", solContract({ provenance: "official_provider_catalog" }), "catalog_contract_incomplete"],
  ["a missing reasoning flag", solContract({ reasoning: undefined }), "catalog_contract_incomplete"],
  ["input without text", solContract({ input: ["image"] }), "catalog_contract_incomplete"]
]) test(`contract validation fails closed for ${name}`, async () => {
  const h = await harness({ catalog: solCatalog });
  const credential = await h.login();
  const catalog = await h.plugin.catalog(credential, new AbortController().signal, { "gpt-6.1-sol": contract });
  const entry = catalog.find(model => model.id === "gpt-6.1-sol");
  assert.equal(entry.supported, false);
  assert.equal(entry.reason, reason);
  assert.equal(entry.source, null);
  assert.equal(h.models.getModel(CHATGPT_PLAN_PROVIDER, "gpt-6.1-sol"), undefined);
  assert.equal(h.plugin.modelSource("gpt-6.1-sol"), null);
});

test("merged contracts persist across catalog calls until cleared", async () => {
  const h = await harness({ catalog: solCatalog });
  const credential = await h.login();
  await h.plugin.catalog(credential, new AbortController().signal, { "gpt-6.1-sol": solContract() });
  const second = await h.plugin.catalog(credential, new AbortController().signal);
  assert.equal(second.find(model => model.id === "gpt-6.1-sol").source, "models_dev_contract");
  h.plugin.clearCatalog();
  const third = await h.plugin.catalog(credential, new AbortController().signal);
  const entry = third.find(model => model.id === "gpt-6.1-sol");
  assert.equal(entry.supported, false);
  assert.equal(entry.reason, "pi_model_missing");
});

test("ChatGPT success requires Pi's completed provider status", () => {
  for (const stopReason of ["stop", "toolUse"]) assert.equal(chatGPTPlanCompleted({ rawStopReason: "completed", stopReason }), true);
  for (const rawStopReason of ["incomplete.max_output_tokens", "incomplete.content_filter", "in_progress", undefined]) {
    assert.equal(chatGPTPlanCompleted({ rawStopReason, stopReason: "length", content: [{ type: "text", text: "partial" }] }), false);
  }
});
