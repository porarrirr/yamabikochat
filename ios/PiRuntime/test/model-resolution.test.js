import assert from "node:assert/strict";
import { once } from "node:events";
import { spawn } from "node:child_process";
import net from "node:net";
import test from "node:test";

async function availablePort() {
  const server = net.createServer();
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const { port } = server.address();
  server.close();
  await once(server, "close");
  return port;
}

async function waitUntilReady(baseURL, token) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      const response = await fetch(`${baseURL}/health`, {
        headers: { authorization: `Bearer ${token}` }
      });
      if (response.ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error("Pi Runtime did not become ready");
}

async function resolveModels(baseURL, token, models) {
  const response = await fetch(`${baseURL}/v1/models/resolve`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ models })
  });
  assert.equal(response.status, 200);
  return response.json();
}

test("resolves verified OpenCode Go routes and returns typed contract conflicts", async (context) => {
  const port = await availablePort();
  const token = "model-resolution-test-token";
  const process = spawn(
    globalThis.process.execPath,
    [new URL("../bundle/main.js", import.meta.url).pathname, String(port), token],
    { stdio: ["ignore", "pipe", "pipe"] }
  );
  context.after(() => process.kill("SIGTERM"));
  const baseURL = `http://127.0.0.1:${port}`;
  await waitUntilReady(baseURL, token);

  const result = await resolveModels(baseURL, token, [
    {
      contractVersion: 2,
      provider: "opencode-go",
      model: "muse-spark-1.2-contributor",
      catalogContract: {
        npm: "@ai-sdk/openai",
        api: "https://opencode.ai/zen/go/v1",
        shape: "responses",
        provenance: "model",
        toolCall: false
      }
    },
    { contractVersion: 2, provider: "missing-provider", model: "model" },
    { contractVersion: 2, provider: "opencode-go", model: "missing-model" },
    {
      contractVersion: 2,
      provider: "opencode-go",
      model: "muse-spark-1.2-contributor",
      catalogContract: { shape: "completions", provenance: "model" }
    },
    {
      contractVersion: 2,
      provider: "opencode-go",
      model: "qwen3.7-max",
      catalogContract: { toolCall: true }
    },
    {
      contractVersion: 2,
      provider: "opencode-go",
      model: "qwen3.7-plus",
      catalogContract: {
        npm: "@ai-sdk/anthropic",
        api: "https://opencode.ai/zen/go/v1",
        shape: "messages",
        provenance: "model"
      }
    },
    {
      contractVersion: 2,
      provider: "opencode-go",
      model: "qwen3.8-max",
      catalogContract: { shape: "completions", provenance: "model" }
    },
    {
      contractVersion: 2,
      provider: "opencode-go",
      model: "qwen3.8-max",
      catalogContract: {
        npm: "@ai-sdk/anthropic",
        api: "https://example.invalid/v1",
        shape: "messages",
        provenance: "model"
      }
    },
    {
      contractVersion: 2,
      provider: "opencode-go",
      model: "qwen3.8-max",
      catalogContract: { shape: "unknown", provenance: "model" }
    },
    { contractVersion: 2, provider: "opencode-go", model: "minimax-m3" },
    { contractVersion: 2, provider: "opencode-go", model: "minimax-m2.5" },
    { contractVersion: 2, provider: "opencode-go", model: "glm-5.3" },
    { contractVersion: 2, provider: "opencode-go", model: "qwen3.6-plus" },
    { contractVersion: 2, provider: "opencode-go", model: "minimax-m2.7" },
    { contractVersion: 1, provider: "opencode-go", model: "muse-spark-1.2-contributor" }
  ]);

  assert.equal(result.contractVersion, 2);
  assert.deepEqual(result.models[0], {
    supported: true,
    provider: "opencode-go",
    model: "muse-spark-1.2-contributor",
    api: "openai-responses",
    source: "verified_official_contract",
    reasoning: true,
    input: ["text", "image"],
    contextWindow: 1048576,
    maxTokens: 131072,
    toolCall: false
  });
  assert.equal(result.models[1].reason, "pi_provider_missing");
  assert.equal(result.models[2].reason, "pi_model_missing");
  assert.equal(result.models[3].reason, "protocol_conflict");
  assert.equal(result.models[4].supported, true);
  assert.equal(result.models[4].api, "anthropic-messages");
  assert.equal(result.models[4].source, "verified_official_contract");
  assert.equal(result.models[5].supported, true);
  assert.equal(result.models[5].api, "anthropic-messages");
  assert.equal(result.models[6].reason, "protocol_conflict");
  assert.equal(result.models[7].reason, "endpoint_conflict");
  assert.equal(result.models[8].reason, "catalog_contract_ambiguous");
  assert.equal(result.models[9].api, "anthropic-messages");
  assert.equal(result.models[10].api, "anthropic-messages");
  assert.equal(result.models[11].api, "openai-completions");
  assert.equal(result.models[12].api, "anthropic-messages");
  assert.equal(result.models[13].api, "anthropic-messages");
  assert.equal(result.models[14].reason, "runtime_contract_mismatch");
});
