import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import vm from "node:vm";
import http from "node:http";
import net from "node:net";
import { once } from "node:events";
import { spawn } from "node:child_process";
import { transformMessages } from "../node_modules/@earendil-works/pi-ai/dist/api/transform-messages.js";

const source = fs.readFileSync(new URL("../src/main.js", import.meta.url), "utf8");
function sourceFunction(name, dependencies = {}) {
  const start = source.indexOf(`function ${name}(`);
  const end = source.indexOf("\nfunction ", start + 1);
  return vm.runInNewContext(`(${source.slice(start, end)})`, dependencies);
}

test("native assistant provenance and signatures survive the bridge round trip", () => {
  const transcript = sourceFunction("replayableProviderTranscript");
  const messagesFrom = sourceFunction("messagesFrom", { usage: (value) => value, contentFor: () => [] });
  const assistant = { role: "assistant", api: "openai-responses", provider: "openai", model: "gpt-4.1", content: [
    { type: "thinking", thinking: "private", thinkingSignature: "signature" },
    { type: "toolCall", id: "call_review|fc_review", name: "python_execute", arguments: {} }
  ], usage: {}, stopReason: "toolUse", timestamp: 1 };
  const tool = { role: "toolResult", toolCallId: "call_review|fc_review", toolName: "python_execute", content: [{ type: "text", text: "ok" }], timestamp: 2 };
  const target = { api: "anthropic-messages", provider: "anthropic", id: "claude", input: ["text", "image"] };
  const replayed = messagesFrom({ messages: JSON.parse(JSON.stringify(transcript([assistant, tool]))) }, target);
  assert.deepEqual(replayed[0], assistant);
  let normalizations = 0;
  const transformed = transformMessages(replayed, target, (id) => { normalizations++; return id.replaceAll("|", "_"); });
  assert.equal(normalizations, 1);
  const call = transformed[0].content.find((part) => part.type === "toolCall");
  assert.equal(call.id, transformed[1].toolCallId);
  assert.equal(call.id, "call_review_fc_review");
  transformMessages(replayed, { ...target, api: assistant.api, provider: assistant.provider, id: assistant.model }, () => assert.fail("Same-model history should preserve IDs"));
});

test("bundled Pi aborts the run and tool wait when the response disconnects", { timeout: 20000 }, async (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "yamabiko-disconnect-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const mock = path.join(root, "mock.mjs");
  fs.writeFileSync(mock, `
    const original = globalThis.fetch;
    globalThis.fetch = async (url, options) => {
      if (!String(url).includes("openrouter.ai")) return original(url, options);
      const chunks = [
        { id: "test", object: "chat.completion.chunk", created: 1, model: "openai/gpt-4o-mini", choices: [{ index: 0, delta: { role: "assistant", tool_calls: [{ index: 0, id: "call_review", type: "function", function: { name: "python_execute", arguments: "{}" } }] }, finish_reason: null }] },
        { id: "test", object: "chat.completion.chunk", created: 1, model: "openai/gpt-4o-mini", choices: [{ index: 0, delta: {}, finish_reason: "tool_calls" }], usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } }
      ];
      return new Response(chunks.map(x => "data: " + JSON.stringify(x) + "\\n\\n").join("") + "data: [DONE]\\n\\n", { headers: { "content-type": "text/event-stream" } });
    };
  `);
  const server = net.createServer().listen(0, "127.0.0.1");
  await once(server, "listening");
  const port = server.address().port;
  server.close();
  await once(server, "close");
  const child = spawn(process.execPath, ["--import", mock, new URL("../bundle/main.js", import.meta.url).pathname, String(port), "review", path.join(root, "runtime.log")], { stdio: ["ignore", "ignore", "pipe"] });
  t.after(() => child.kill());
  let errors = "";
  child.stderr.on("data", x => errors += x);
  const base = `http://127.0.0.1:${port}`;
  const health = async () => (await fetch(`${base}/health`, { headers: { authorization: "Bearer review" } })).json();
  for (let i = 0; ; i++) {
    try { await health(); break; } catch { assert.ok(i < 100, errors); await new Promise(r => setTimeout(r, 25)); }
  }
  const envelope = { runId: "disconnect", config: { contractVersion: 2, provider: "openrouter", model: "openai/gpt-4o-mini", apiKey: "test" }, request: { messages: [{ role: "user", content: "use the tool", attachments: [] }], tools: [{ type: "function", payload: { name: "python_execute", description: "test tool", parameters: '{"type":"object","properties":{}}' } }], metadata: {} } };
  await new Promise((resolve, reject) => {
    const request = http.request(`${base}/v1/run`, { method: "POST", headers: { authorization: "Bearer review", "content-type": "application/json" } }, response => {
      let received = "";
      response.on("data", chunk => {
        received += chunk;
        if (received.includes('"type":"tool_request"')) { response.destroy(); resolve(); }
      });
      response.on("end", () => reject(new Error(`No tool request: ${received}`)));
    });
    request.on("error", reject);
    request.end(JSON.stringify(envelope));
  });
  for (let i = 0; ; i++) {
    const state = await health();
    if (state.activeRuns === 0 && state.pendingTools === 0) break;
    assert.ok(i < 100, JSON.stringify(state));
    await new Promise(r => setTimeout(r, 25));
  }
});
