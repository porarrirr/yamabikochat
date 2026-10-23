import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

test("bundled Pi redacts errors, aborts OAuth execution, and rejects stale signed-out credentials", { timeout: 30_000 }, async t => {
  const synthetic = "synthetic-unlabelled-provider-secret";
  const fixture = createServer(async (req, res) => {
    for await (const _ of req) {}
    res.writeHead(401, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: { message: `Provider rejected ${synthetic}`, type: "authentication_error" } }));
  });
  await new Promise(resolve => fixture.listen(0, "127.0.0.1", resolve));
  t.after(() => { fixture.closeAllConnections(); fixture.close(); });
  const portProbe = createServer();
  await new Promise(resolve => portProbe.listen(0, "127.0.0.1", resolve));
  const port = portProbe.address().port;
  await new Promise(resolve => portProbe.close(resolve));
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "yamabiko-security-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const mock = path.join(root, "transport.mjs");
  fs.writeFileSync(mock, `
    const original = globalThis.fetch;
    globalThis.fetch = async (url, options = {}) => {
      if (String(url).startsWith('http://127.0.0.1:')) return original(url, options);
      if (String(url).startsWith('https://cli-chat-proxy.grok.com/')) {
        return new Promise((resolve, reject) => {
          const fail = () => reject(new DOMException('aborted', 'AbortError'));
          if (options.signal?.aborted) fail();
          else options.signal?.addEventListener('abort', fail, { once: true });
        });
      }
      throw new Error('Unexpected external endpoint in offline security test');
    };
  `);
  const child = spawn(process.execPath, ["--import", mock, new URL("../bundle/main.js", import.meta.url).pathname, String(port), "security-loopback-test"], { stdio: ["ignore", "ignore", "pipe"] });
  t.after(() => child.kill());
  let stderr = "";
  child.stderr.on("data", value => stderr += value);
  const base = `http://127.0.0.1:${port}`;
  const headers = { authorization: "Bearer security-loopback-test", "content-type": "application/json" };
  const post = (route, value) => fetch(base + route, { method: "POST", headers, body: JSON.stringify(value) });
  for (let attempt = 0; ; attempt++) {
    try { if ((await fetch(base + "/health", { headers })).ok) break; } catch {}
    assert.ok(attempt < 200, stderr);
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  const request = { messages: [{ role: "user", content: "hello", attachments: [] }], tools: [], metadata: {} };
  const customEndpoint = { name: "Security", protocol: "openai-completions", modelId: "security-model", baseUrl: `http://127.0.0.1:${fixture.address().port}/v1`, contextWindow: 4096, maxTokens: 1024, reasoning: false, toolCall: false, vision: false, reasoningEffort: "off", maxTokensField: "max_tokens" };
  const diagnostic = await (await post("/v1/run", { runId: "secret-error", config: { contractVersion: 2, provider: "yamabiko-custom", model: "security-model", apiKey: synthetic, customEndpoint }, request })).text();
  assert.ok(diagnostic.includes('execution_snapshot'), diagnostic);
  assert.ok(!diagnostic.includes(synthetic), "No wire event, snapshot, or error may contain the credential");
  assert.ok(diagnostic.includes("[REDACTED]"));

  const credential = { type: "oauth", access: "synthetic-oauth-access", refresh: "synthetic-oauth-refresh", expires: Date.now() + 3_600_000 };
  assert.equal((await post("/v1/auth/resolve", { provider: "supergrok", credential })).status, 200);
  const envelope = { runId: "oauth-run", config: { contractVersion: 2, provider: "xai-oauth", model: "grok-4.5", apiKey: credential.access }, request };
  const response = await post("/v1/run", envelope);
  const reader = response.body.getReader();
  let events = "";
  for (let attempts = 0; !events.includes('"stage":"agent_start"'); attempts++) {
    assert.ok(attempts < 20, events);
    const chunk = await reader.read();
    assert.ok(!chunk.done, events);
    events += new TextDecoder().decode(chunk.value);
  }
  assert.equal((await post("/v1/auth/logout", { provider: "supergrok" })).status, 200);
  while (true) { const chunk = await reader.read(); if (chunk.done) break; events += new TextDecoder().decode(chunk.value); }
  assert.ok(!events.includes('"type":"completed"'), events);
  const staleRun = await (await post("/v1/run", { ...envelope, runId: "late-run" })).text();
  assert.match(staleRun, /OAUTH_SIGNED_OUT|oauth_signed_out/);
  const staleResolve = await post("/v1/auth/resolve", { provider: "supergrok", credential });
  assert.equal(staleResolve.status, 500);
});
