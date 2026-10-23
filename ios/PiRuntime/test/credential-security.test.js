import assert from "node:assert/strict";
import { createServer } from "node:http";
import test from "node:test";
import { createModels } from "@earendil-works/pi-ai";
import { credentialFetch, CredentialRedactor, diagnosticRedactor, withCredentialSecurity } from "../src/credential-security.js";
import { customProviderResolution, CUSTOM_PROVIDER } from "../src/custom-provider.js";

const custom = protocol => ({ name: "Security", protocol, modelId: "security-model", baseUrl: "https://provider.example/v1", contextWindow: 4096, maxTokens: 1024, reasoning: false, toolCall: false, vision: false, reasoningEffort: "off", maxTokensField: "max_tokens" });

for (const protocol of ["openai-completions", "openai-responses", "anthropic-messages", "google-generative-ai", "mistral-conversations"]) {
  test(`${protocol} rejects external HTTP and permits only explicit loopback HTTP`, () => {
    for (const baseUrl of ["http://provider.example/v1", "http://192.168.1.2/v1", "http://127.0.0.1.attacker.example/v1", "http://user:pass@localhost/v1"]) {
      const endpoint = { ...custom(protocol), baseUrl };
      assert.equal(customProviderResolution({ provider: CUSTOM_PROVIDER, model: endpoint.modelId, customEndpoint: endpoint }, createModels()).supported, false);
    }
    for (const baseUrl of ["https://provider.example/v1", "http://127.0.0.1:1234/v1", "http://localhost:1234/v1", "http://[::1]:1234/v1"]) {
      const endpoint = { ...custom(protocol), baseUrl };
      assert.equal(customProviderResolution({ provider: CUSTOM_PROVIDER, model: endpoint.modelId, customEndpoint: endpoint }, createModels()).supported, true);
    }
  });
}

test("credential transport never forwards a secret or body to a redirect target", async t => {
  let forwarded = 0;
  const target = createServer((_req, res) => { forwarded++; res.end("unexpected"); });
  await new Promise(resolve => target.listen(0, "127.0.0.1", resolve));
  const source = createServer((_req, res) => { res.writeHead(307, { location: `http://127.0.0.1:${target.address().port}/capture` }); res.end(); });
  await new Promise(resolve => source.listen(0, "127.0.0.1", resolve));
  t.after(() => { source.closeAllConnections(); source.close(); target.closeAllConnections(); target.close(); });
  const fetch = credentialFetch(globalThis.fetch);
  await assert.rejects(fetch(`http://127.0.0.1:${source.address().port}/model`, { method: "POST", headers: { "x-goog-api-key": "synthetic-review-secret" }, body: "private conversation" }));
  assert.equal(forwarded, 0);
  let requests = 0;
  await assert.rejects(credentialFetch(async () => { requests++; })("http://external.example/v1"), /HTTPS/);
  assert.equal(requests, 0);
});

test("all credential forms are removed from nested snapshots and free-text errors", () => {
  const redactor = new CredentialRedactor();
  const secret = "synthetic-secret-with-no-key-prefix";
  redactor.observe({ config: { apiKey: secret, env: { AWS_SECRET_ACCESS_KEY: "aws-synthetic" } }, credential: { access: "oauth-access", refresh: "oauth-refresh", idToken: "oauth-id-token" } });
  const snapshot = redactor.value({ state: { errorMessage: `Provider rejected ${secret}` }, failure: { message: "oauth-refresh and aws-synthetic" }, nested: { authorization_token: "mcp-token", refresh_token: "refresh-value", idToken: "identity-value" } });
  const text = JSON.stringify(snapshot);
  for (const value of [secret, "oauth-refresh", "aws-synthetic", "mcp-token", "refresh-value", "identity-value"]) assert.ok(!text.includes(value), value);
  assert.ok(!redactor.text('{"api_key":"quoted-secret", "refresh_token": "with spaces"}').includes("quoted-secret"));
});

test("simultaneous provider requests keep credential redaction scoped to their owner", async () => {
  await Promise.all(["first-secret", "second-secret"].map(secret => withCredentialSecurity(async () => {
    diagnosticRedactor().observe({ apiKey: secret });
    await new Promise(resolve => setTimeout(resolve, 10));
    assert.equal(diagnosticRedactor().text(secret), "[REDACTED]");
    const other = secret === "first-secret" ? "second-secret" : "first-secret";
    assert.equal(diagnosticRedactor().text(other), other);
  })));
});
