import assert from "node:assert/strict";
import test from "node:test";
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai";
import { compactContext } from "../src/compaction.js";
import { CUSTOM_PROVIDER } from "../src/custom-provider.js";
import { createServer } from "node:http";
import { once } from "node:events";
import { spawn } from "node:child_process";

const model = { id: "test", provider: "test", api: "openai-responses", contextWindow: 128000, maxTokens: 8192 };
const usage = { input: 100, output: 20, totalTokens: 120, cacheRead: 0, cacheWrite: 0, cost: { total: 0 } };
const messages = [{ role: "user", content: [{ type: "text", text: "Remember the project constraints" }], timestamp: 1 }];

for (const provider of ["openai-codex", "openai-chatgpt", "anthropic", "google"]) {
  test(`Pi compaction preserves ${provider} identity and produces replayable context`, async () => {
    let calls = 0;
    const result = await compactContext({ messages, model: { ...model, provider }, config: {},
      streamFn(selected, context, options) {
        calls++;
        assert.equal(selected.provider, provider);
        assert.match(JSON.stringify(context.messages), /Remember the project constraints/);
        assert.equal(context.tools?.length || 0, 0);
        assert.equal(options.cacheRetention, "none");
        const stream = createAssistantMessageEventStream();
        stream.push({ type: "done", reason: "stop", message: {
          role: "assistant", content: [{ type: "text", text: "Preserve project constraints." }],
          ...model, usage, stopReason: "stop", timestamp: 2
        } });
        stream.end();
        return stream;
      }
    });
    assert.equal(calls, 1);
    // ProviderResponse's synthesized Swift decoder requires this even for summaries.
    assert.deepEqual(result.toolCalls, []);
    assert.equal(result.providerTranscript[0].role, "user");
    assert.match(result.providerTranscript[0].content, /<summary>\nPreserve project constraints/);
    assert.equal(result.usage.inputTokens, 100);
    assert.ok(result.usage.contextTokens > 0);
  });
}

for (const stopReason of ["length", "error", "aborted"]) {
  test(`does not save partial ${stopReason} summaries or retry`, async () => {
    let calls = 0;
    await assert.rejects(compactContext({ messages, model, config: {}, streamFn() {
      calls++;
      const stream = createAssistantMessageEventStream();
      stream.push({ type: "done", reason: stopReason, message: {
        role: "assistant", content: [{ type: "text", text: "Partial summary" }],
        ...model, usage, stopReason, errorMessage: stopReason === "error" ? "terminated" : undefined, timestamp: 2
      } });
      stream.end();
      return stream;
    } }));
    assert.equal(calls, 1);
  });
}

test("bundled runtime compacts through the configured Pi adapter without generating a chat reply", { timeout: 20000 }, async t => {
  const requests = [];
  const upstream = createServer(async (req, res) => {
    let body = "";
    for await (const chunk of req) body += chunk;
    requests.push(JSON.parse(body));
    res.writeHead(200, { "content-type": "text/event-stream" });
    res.end('data: {"choices":[{"index":0,"delta":{"content":"Keep the project constraints."},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n');
  }).listen(0, "127.0.0.1");
  await once(upstream, "listening");
  t.after(() => upstream.close());
  const reservation = createServer().listen(0, "127.0.0.1");
  await once(reservation, "listening");
  const port = reservation.address().port;
  reservation.close();
  await once(reservation, "close");
  const child = spawn(process.execPath, [new URL("../bundle/main.js", import.meta.url).pathname, String(port), "compaction-test"], { stdio: "ignore" });
  t.after(async () => {
    if (child.exitCode === null) { child.kill(); await once(child, "exit"); }
  });
  const base = `http://127.0.0.1:${port}`;
  const headers = { authorization: "Bearer compaction-test", "content-type": "application/json" };
  for (let i = 0; ; i++) {
    try { if ((await fetch(`${base}/health`, { headers })).ok) break; } catch {}
    assert.ok(i < 100, "runtime should start");
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  const response = await fetch(`${base}/v1/run`, {
    method: "POST", headers, body: JSON.stringify({ runId: "compact", config: {
      provider: CUSTOM_PROVIDER, model: "custom-model", apiKey: "test", contractVersion: 2,
      customEndpoint: { name: "Test", protocol: "openai-completions", modelId: "custom-model",
        baseUrl: `http://127.0.0.1:${upstream.address().port}/v1`, contextWindow: 128000, maxTokens: 4096,
        reasoning: false, reasoningEffort: "off", toolCall: true, vision: false, maxTokensField: "max_tokens" }
    }, request: { messages: [{ role: "user", content: "Remember the project constraints", attachments: [] }],
      tools: [], metadata: { contextOperation: "compact" } }
    })
  });
  const output = await response.text();
  const events = output.trim().split("\n").map(JSON.parse);
  const completion = events.find(event => event.type === "completed");
  assert.ok(completion, output);
  assert.deepEqual(completion.response.toolCalls, []);
  assert.equal(requests.length, 1);
  assert.match(JSON.stringify(requests[0].messages), /<conversation>/);
  assert.equal(events.some(event => event.type === "text_delta"), false);
  assert.match(completion.response.providerTranscript[0].content, /Keep the project constraints/);
});
