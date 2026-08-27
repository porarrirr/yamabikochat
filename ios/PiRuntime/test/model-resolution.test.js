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

  const providerIdentityCases = [
    ["alibaba-token-plan", "qwen3.7-max", "qwen-token-plan", "openai-completions", { api: "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1", npm: "@ai-sdk/openai-compatible" }],
    ["alibaba-token-plan-cn", "qwen3.7-max", "qwen-token-plan-cn", "openai-completions", { api: "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1", npm: "@ai-sdk/openai-compatible" }],
    ["azure", "gpt-5.2", "azure-openai-responses", "azure-openai-responses", { providerName: "Azure", npm: "@ai-sdk/azure" }],
    ["fireworks-ai", "accounts/fireworks/models/deepseek-v4-pro", "fireworks", "anthropic-messages", { providerName: "Fireworks AI", api: "https://api.fireworks.ai/inference/v1/", npm: "@ai-sdk/openai-compatible" }],
    ["google-vertex", "gemini-3.1-pro-preview", "google-vertex", "google-vertex", { providerName: "Vertex", npm: "@ai-sdk/google-vertex" }],
    ["kimi-for-coding", "k3", "kimi-coding", "anthropic-messages", { providerName: "Kimi For Coding", api: "https://api.kimi.com/coding/v1", npm: "@ai-sdk/anthropic" }],
    ["minimax-coding-plan", "MiniMax-M2.7", "minimax", "anthropic-messages", { providerName: "MiniMax Token Plan (minimax.io)", api: "https://api.minimax.io/anthropic/v1", npm: "@ai-sdk/anthropic" }],
    ["minimax-cn-coding-plan", "MiniMax-M2.7", "minimax-cn", "anthropic-messages", { providerName: "MiniMax Token Plan (minimaxi.com)", api: "https://api.minimaxi.com/anthropic/v1", npm: "@ai-sdk/anthropic" }],
    ["togetherai", "deepseek-ai/DeepSeek-V4-Pro", "together", "openai-completions", { providerName: "Together AI", npm: "@ai-sdk/togetherai" }],
    ["vercel", "alibaba/qwen-3-14b", "vercel-ai-gateway", "anthropic-messages", { providerName: "Vercel AI Gateway", npm: "@ai-sdk/gateway" }],
    ["zai-coding-plan", "glm-5.3", "zai", "openai-completions", { providerName: "Z.AI Coding Plan", api: "https://api.z.ai/api/coding/paas/v4", npm: "@ai-sdk/openai-compatible" }],
    ["zhipuai-coding-plan", "glm-5.3", "zai-coding-cn", "openai-completions", { providerName: "Zhipu AI Coding Plan", api: "https://open.bigmodel.cn/api/coding/paas/v4", npm: "@ai-sdk/openai-compatible" }],
    ["future-together-provider-id", "deepseek-ai/DeepSeek-V4-Pro", "together", "openai-completions", { providerName: "Together AI", npm: "@ai-sdk/togetherai" }],
    ["future-zhipu-provider-id", "glm-5.3", "zai-coding-cn", "openai-completions", { providerName: "Future Zhipu Service", api: "https://open.bigmodel.cn/api/coding/paas/v4", npm: "@ai-sdk/openai-compatible" }]
  ];

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
    { contractVersion: 2, provider: "opencode-go", model: "deepseek-v4-flash-vision-exp" },
    { contractVersion: 2, provider: "opencode-go", model: "glm-5.3-flash" },
    { contractVersion: 1, provider: "opencode-go", model: "muse-spark-1.2-contributor" },
    {
      contractVersion: 2,
      provider: "opencode",
      model: "nemotron-3.5-lightning-free",
      catalogContract: {
        npm: "@ai-sdk/openai-compatible",
        api: "https://opencode.ai/zen/v1",
        provenance: "provider",
        name: "Nemotron 3.5 Lightning Free",
        reasoning: true,
        input: ["text"],
        contextWindow: 262144,
        maxTokens: 262144,
        toolCall: true
      }
    },
    {
      contractVersion: 2,
      provider: "opencode",
      model: "muse-spark-1.2-contributor-free",
      catalogContract: {
        npm: "@ai-sdk/openai",
        api: "https://opencode.ai/zen/v1",
        provenance: "model",
        name: "Muse Spark 1.2 Free",
        reasoning: true,
        input: ["text", "image", "video", "pdf", "audio"],
        contextWindow: 1048576,
        maxTokens: 131072,
        toolCall: true
      }
    },
    {
      contractVersion: 2,
      provider: "openrouter",
      model: "stealth/ox-alpha",
      catalogContract: {
        npm: "@openrouter/ai-sdk-provider",
        api: "https://openrouter.ai/api/v1",
        provenance: "official_provider_catalog",
        name: "Ox Alpha",
        reasoning: true,
        input: ["text", "image", "video"],
        contextWindow: 1048576,
        maxTokens: 131072,
        toolCall: true
      }
    },
    {
      contractVersion: 2,
      provider: "opencode",
      model: "incomplete-new-model",
      catalogContract: {
        npm: "@ai-sdk/openai-compatible",
        api: "https://opencode.ai/zen/v1",
        provenance: "provider"
      }
    },
    {
      contractVersion: 2,
      provider: "opencode",
      model: "conflicting-new-model",
      catalogContract: {
        npm: "@ai-sdk/openai-compatible",
        api: "https://opencode.ai/zen/v1",
        shape: "responses",
        provenance: "model",
        name: "Conflicting New Model",
        reasoning: false,
        input: ["text"],
        contextWindow: 100000,
        maxTokens: 10000
      }
    },
    { contractVersion: 2, provider: "opencode", model: "conflicting-new-model" },
    {
      contractVersion: 2,
      provider: "opencode-go",
      model: "qwen3.7-max",
      catalogContract: {
        npm: "@ai-sdk/openai-compatible",
        api: "https://opencode.ai/zen/go/v1",
        provenance: "provider",
        toolCall: true
      }
    },
    {
      contractVersion: 2,
      provider: "azure",
      model: "gpt-5.2",
      catalogContract: { npm: "@ai-sdk/azure", provenance: "provider", toolCall: true }
    },
    {
      contractVersion: 2,
      provider: "google-vertex",
      model: "gemini-3.1-pro-preview",
      catalogContract: { npm: "@ai-sdk/google-vertex", provenance: "provider", toolCall: true }
    },
    {
      contractVersion: 2,
      provider: "togetherai",
      model: "deepseek-ai/DeepSeek-V4-Pro",
      catalogContract: { npm: "@ai-sdk/togetherai", provenance: "provider", toolCall: true }
    },
    {
      contractVersion: 2,
      provider: "fireworks-ai",
      model: "accounts/fireworks/models/deepseek-v4-pro",
      catalogContract: {
        npm: "@ai-sdk/openai-compatible",
        api: "https://api.fireworks.ai/inference/v1/",
        provenance: "provider",
        toolCall: true
      }
    },
    {
      contractVersion: 2,
      provider: "zai-coding-plan",
      model: "glm-5.3",
      catalogContract: {
        npm: "@ai-sdk/openai-compatible",
        api: "https://api.z.ai/api/coding/paas/v4",
        provenance: "provider",
        toolCall: true
      }
    },
    {
      contractVersion: 2,
      provider: "zai",
      model: "glm-5.3",
      catalogContract: {
        npm: "@ai-sdk/openai-compatible",
        api: "https://api.z.ai/api/paas/v4",
        provenance: "provider",
        toolCall: true
      }
    },
    {
      contractVersion: 2,
      provider: "google-vertex",
      model: "claude-opus-4-7@default",
      catalogContract: {
        npm: "@ai-sdk/google-vertex/anthropic",
        provenance: "model",
        toolCall: true
      }
    },
    {
      contractVersion: 2,
      provider: "togetherai",
      model: "deepcogito/cogito-v2-1-671b",
      catalogContract: {
        npm: "@ai-sdk/togetherai",
        provenance: "provider",
        name: "Cogito v2.1 671B",
        reasoning: true,
        input: ["text"],
        contextWindow: 163840,
        maxTokens: 163840,
        toolCall: false
      }
    },
    ...providerIdentityCases.map(([provider, model, , , contract]) => ({
      contractVersion: 2,
      provider,
      model,
      catalogContract: { ...contract, provenance: "provider" }
    })),
    {
      contractVersion: 2,
      provider: "alibaba-coding-plan",
      model: "qwen3.7-max",
      catalogContract: {
        providerName: "Alibaba Coding Plan",
        npm: "@ai-sdk/openai-compatible",
        api: "https://coding-intl.dashscope.aliyuncs.com/v1",
        provenance: "provider"
      }
    },
    {
      contractVersion: 2,
      provider: "alibaba-coding-plan-cn",
      model: "qwen3.7-max",
      catalogContract: {
        providerName: "Alibaba Coding Plan (China)",
        npm: "@ai-sdk/openai-compatible",
        api: "https://coding.dashscope.aliyuncs.com/v1",
        provenance: "provider"
      }
    },
    {
      contractVersion: 2,
      provider: "ambiguous-qwen-plan",
      model: "qwen3.7-max",
      catalogContract: {
        providerName: "Ambiguous Qwen Plan",
        npm: "@ai-sdk/openai-compatible",
        api: "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1",
        provenance: "provider"
      }
    }
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
  assert.equal(result.models[14].api, "openai-completions");
  assert.deepEqual(result.models[14].input, ["text", "image"]);
  assert.equal(result.models[14].maxTokens, 384000);
  assert.equal(result.models[15].api, "openai-completions");
  assert.deepEqual(result.models[15].input, ["text", "image", "video", "pdf"]);
  assert.equal(result.models[15].maxTokens, 131072);
  assert.equal(result.models[16].reason, "runtime_contract_mismatch");
  assert.deepEqual(result.models[17], {
    supported: true,
    provider: "opencode",
    model: "nemotron-3.5-lightning-free",
    api: "openai-completions",
    source: "pi_builtin",
    reasoning: true,
    input: ["text"],
    contextWindow: 262144,
    maxTokens: 262144,
    toolCall: true
  });
  assert.equal(result.models[18].supported, true);
  assert.equal(result.models[18].api, "openai-responses");
  assert.equal(result.models[18].source, "model");
  assert.equal(result.models[19].supported, true);
  assert.equal(result.models[19].api, "openai-completions");
  assert.equal(result.models[19].source, "official_provider_catalog");
  assert.equal(result.models[20].reason, "catalog_contract_incomplete");
  assert.equal(result.models[21].reason, "protocol_conflict");
  assert.equal(result.models[22].reason, "pi_model_missing");
  assert.equal(result.models[23].supported, true);
  assert.equal(result.models[23].api, "anthropic-messages");
  assert.equal(result.models[24].provider, "azure-openai-responses");
  assert.equal(result.models[24].api, "azure-openai-responses");
  assert.equal(result.models[25].provider, "google-vertex");
  assert.equal(result.models[25].api, "google-vertex");
  assert.equal(result.models[26].provider, "together");
  assert.equal(result.models[26].api, "openai-completions");
  assert.equal(result.models[27].provider, "fireworks");
  assert.equal(result.models[27].api, "anthropic-messages");
  assert.equal(result.models[28].provider, "zai");
  assert.equal(result.models[28].api, "openai-completions");
  assert.equal(result.models[29].reason, "endpoint_conflict");
  assert.equal(result.models[30].reason, "catalog_contract_ambiguous");
  assert.equal(result.models[31].supported, true);
  assert.equal(result.models[31].provider, "together");
  assert.equal(result.models[31].api, "openai-completions");
  assert.equal(result.models[31].source, "provider");
  assert.deepEqual(
    result.models.slice(32, 32 + providerIdentityCases.length).map((resolution) => [
      resolution.supported,
      resolution.provider,
      resolution.api
    ]),
    providerIdentityCases.map(([, , provider, api]) => [true, provider, api])
  );
  assert.equal(result.models[32 + providerIdentityCases.length].reason, "pi_provider_missing");
  assert.equal(result.models[33 + providerIdentityCases.length].reason, "pi_provider_missing");
  assert.equal(result.models[34 + providerIdentityCases.length].reason, "pi_provider_ambiguous");
});
