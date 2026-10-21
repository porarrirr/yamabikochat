import assert from "node:assert/strict";
import test from "node:test";
import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createSubagentProgress } from "../src/subagent-progress.js";
import { selectSubagentModel, mobileModelRuntime } from "../src/subagents.js";
import { builtinModels } from "@earendil-works/pi-ai/providers/all";
import { getSupportedThinkingLevels } from "@earendil-works/pi-ai";

test("child inheritance and effort validation preserve every Pi built-in identity and protocol", () => {
  const catalog = builtinModels();
  const protocols = new Set();
  let checked = 0;
  for (const model of catalog.getModels()) {
    const effort = getSupportedThinkingLevels(model)[0];
    if (!effort) continue;
    const parent = { id: "inherit", name: "parent", model, config: { provider: model.provider, model: model.id, thinkingLevel: effort, apiKey: "scoped-secret" } };
    const inherited = selectSubagentModel(undefined, [parent], parent);
    assert.equal(inherited.model, model);
    assert.equal(inherited.config.thinkingLevel, effort);
    let dispatched;
    const runtime = mobileModelRuntime([parent], entry => (actual, context, options) => { dispatched = { entry, actual, context, options }; return "Pi stream"; }, async () => undefined, id => catalog.getProvider(id));
    assert.equal(runtime.streamSimple(model, { messages: [] }, { reasoning: effort }), "Pi stream");
    assert.equal(dispatched.actual, model);
    assert.equal(runtime.getPhysicalModel(model.provider, model.id), model);
    assert.equal(dispatched.entry.config.apiKey, "scoped-secret");
    assert.equal(dispatched.options.reasoning, effort);
    const unsupported = ["off", "minimal", "low", "medium", "high", "xhigh", "max"].find(level => !getSupportedThinkingLevels(model).includes(level));
    if (unsupported) assert.throws(() => selectSubagentModel(`${model.provider}/${model.id}:${unsupported}`, [parent], parent), { code: "subagent_effort_unsupported" });
    protocols.add(model.api);
    checked++;
  }
  assert.ok(checked > 1000);
  for (const api of ["anthropic-messages", "openai-completions", "openai-responses", "google-generative-ai", "mistral-conversations"]) assert.ok(protocols.has(api), api);
});

test("subagent progress snapshots retain actions and bounded output, and settle once", () => {
  const updates = [];
  let now = 100;
  const progress = createSubagentProgress({ id: "child", agent: "worker", task: "Investigate", model: { provider: "provider", id: "model" }, publish: value => updates.push(value), now: () => ++now });
  progress.accept({ type: "tool_execution_start", toolName: "fetch_url", args: { url: "https://example.org" } });
  progress.accept({ type: "tool_execution_end", toolName: "fetch_url", result: { content: [{ type: "text", text: "Evidence" }] } });
  progress.accept({ type: "message_update", assistantMessageEvent: { type: "text_delta", delta: "x".repeat(100_000) } });
  progress.finish("completed");
  progress.finish("failed");
  const result = updates.at(-1);
  assert.equal(result.status, "completed");
  assert.equal(result.output.length, 96 * 1024);
  assert.equal(result.outputTruncated, true);
  assert.ok(result.events.some(event => event.detail.includes("Evidence")));
  assert.ok(result.finishedAtMs > result.startedAtMs);
  assert.equal(updates[0].events.length, 1, "snapshots do not share mutable arrays");
  progress.dispose();
  const unicode = createSubagentProgress({ id: "unicode", agent: "worker", task: "日本語", model: { provider: "p", id: "m" }, publish: () => {} });
  unicode.accept({ type: "message_update", assistantMessageEvent: { type: "text_delta", delta: "結果😀".repeat(20_000) } });
  unicode.finish("completed");
  assert.ok(Buffer.byteLength(unicode.state.output, "utf8") <= 96 * 1024);
  assert.ok(!unicode.state.output.includes("\ufffd"));
  assert.ok(unicode.state.output.codePointAt(0) < 0xdc00 || unicode.state.output.codePointAt(0) > 0xdfff);
  unicode.dispose();
});

test("bundled pi-subagents executes three real Pi child sessions and reports their contents", { timeout: 30000 }, async t => {
  let active = 0;
  let peak = 0;
  const requests = [];
  const provider = http.createServer(async (req, res) => {
    let input = "";
    for await (const chunk of req) input += chunk;
    const body = JSON.parse(input);
    requests.push({ ...body, url: req.url, authorization: req.headers.authorization || req.headers["x-api-key"] || req.headers["x-goog-api-key"] });
    const last = body.messages?.at(-1) || body.input?.at(-1) || body.contents?.at(-1);
    const isParent = body.messages?.some(message => JSON.stringify(message.content).includes("launch-mobile-"));
    const isResult = last.role === "tool";
    if (!isParent && JSON.stringify(body).includes("force-child-error")) {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: { message: "child provider rejected the request" } }));
      return;
    }
    res.writeHead(200, { "Content-Type": "text/event-stream" });
    const chunk = (delta, finish_reason = null) => res.write(`data: ${JSON.stringify({ id: `test-${requests.length}`, object: "chat.completion.chunk", model: body.model, choices: [{ index: 0, delta, finish_reason }] })}\n\n`);
    if (isParent && !isResult) {
      const prompt = JSON.stringify(body.messages);
      const params = prompt.includes("launch-mobile-profiles")
        ? { tasks: [0, 1, 2, 3, 4].map(index => ({ agent: `mobile-wire-${index}`, task: `Report profile-${index}` })) }
        : prompt.includes("launch-mobile-default") ? { agent: "delegate", task: "Report the default model" }
        : prompt.includes("launch-mobile-inherit") ? { agent: "delegate", task: "Report the inherited model", model: "inherit" }
        : prompt.includes("launch-mobile-error") ? { agent: "delegate", task: "force-child-error" }
        : prompt.includes("launch-mobile-native") ? { agent: "delegate", task: "use-mobile-probe" }
        : { tasks: [1, 2, 3].map(index => ({ agent: "delegate", task: `Report mobile-child-${index}` })) };
      chunk({ role: "assistant", tool_calls: [{ index: 0, id: "delegate-three", type: "function", function: { name: "subagent", arguments: JSON.stringify({ ...params, async: false }) } }] });
      chunk({}, "tool_calls");
    } else if (isParent) {
      chunk({ role: "assistant", content: "All three children finished." });
      chunk({}, "stop");
    } else if (JSON.stringify(body).includes("use-mobile-probe") && last.role !== "tool") {
      chunk({ role: "assistant", tool_calls: [{ index: 0, id: "probe-call", type: "function", function: { name: "mobile_probe", arguments: '{"query":"Inspect evidence"}' } }] });
      chunk({}, "tool_calls");
    } else {
      active++;
      peak = Math.max(peak, active);
      await new Promise(resolve => setTimeout(resolve, 100));
      const text = `Child result: ${JSON.stringify(last.content || last.parts)}`;
      const event = value => res.write(`data: ${JSON.stringify(value)}\n\n`);
      if (req.url.includes("/responses")) {
        event({ type: "response.output_item.added", output_index: 0, item: { id: "msg", type: "message", role: "assistant", content: [] } });
        event({ type: "response.content_part.added", output_index: 0, content_index: 0, part: { type: "output_text", text: "" } });
        event({ type: "response.output_text.delta", output_index: 0, content_index: 0, delta: text });
        event({ type: "response.completed", response: { id: "resp", status: "completed", output: [], usage: { input_tokens: 5, output_tokens: 1, total_tokens: 6 } } });
      } else if (req.url.includes("/messages")) {
        for (const value of [
          { type: "message_start", message: { id: "msg", type: "message", role: "assistant", model: body.model, content: [], usage: { input_tokens: 5, output_tokens: 0 } } },
          { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } },
          { type: "content_block_delta", index: 0, delta: { type: "text_delta", text } },
          { type: "content_block_stop", index: 0 },
          { type: "message_delta", delta: { stop_reason: "end_turn" }, usage: { output_tokens: 1 } },
          { type: "message_stop" }
        ]) res.write(`event: ${value.type}\ndata: ${JSON.stringify(value)}\n\n`);
      } else if (req.url.includes(":streamGenerateContent")) {
        event({ candidates: [{ content: { role: "model", parts: [{ text }] }, finishReason: "STOP" }], usageMetadata: { promptTokenCount: 5, candidatesTokenCount: 1, totalTokenCount: 6 } });
      } else {
        chunk({ role: "assistant", content: text });
        chunk({}, "stop");
      }
      active--;
    }
    res.end(!req.url.includes(":streamGenerateContent") && !req.url.includes("/messages") && !req.url.includes("/responses") ? "data: [DONE]\n\n" : "");
  }).listen(0, "127.0.0.1");
  await once(provider, "listening");
  t.after(() => provider.close());
  const portServer = http.createServer().listen(0, "127.0.0.1");
  await once(portServer, "listening");
  const port = portServer.address().port;
  portServer.close(); await once(portServer, "close");
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "yamabiko-subagents-test-"));
  fs.copyFileSync(new URL("../bundle/main.js", import.meta.url), path.join(root, "main.mjs"));
  fs.cpSync(new URL("../bundle/PiAssets", import.meta.url), path.join(root, "PiAssets"), { recursive: true });
  const sandbox = path.join(root, "ios-sandbox.mjs");
  fs.writeFileSync(sandbox, `
    import { ChildProcess } from "node:child_process";
    import fs from "node:fs";
    ChildProcess.prototype.spawn = function () {
      fs.appendFileSync(${JSON.stringify(path.join(root, "spawn-attempts.log"))}, "spawn attempted\\n");
      throw Object.assign(new Error("spawn EPERM"), { code: "EPERM" });
    };
  `);
  const child = spawn(process.execPath, ["--import", sandbox, path.join(root, "main.mjs"), String(port), "subagent-test"], { cwd: root, stdio: ["ignore", "pipe", "pipe"] });
  let logs = "";
  child.stderr.on("data", chunk => { logs += chunk; });
  t.after(async () => { if (child.exitCode === null) { child.kill(); await once(child, "exit"); } fs.rmSync(root, { recursive: true, force: true }); });
  const base = `http://127.0.0.1:${port}`;
  const headers = { authorization: "Bearer subagent-test", "content-type": "application/json" };
  for (let attempt = 0; ; attempt++) {
    try { if ((await fetch(`${base}/health`, { headers })).ok) break; } catch {}
    assert.ok(attempt < 100, logs);
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  const config = {
      contractVersion: 2, provider: "yamabiko-custom", model: "mobile-test", apiKey: "test-key", thinkingLevel: "off",
      customEndpoint: { name: "test", baseUrl: `http://127.0.0.1:${provider.address().port}/v1`, protocol: "openai-completions", modelId: "mobile-test", contextWindow: 8192, maxTokens: 1024, reasoningEffort: "off", maxTokensField: "max_completion_tokens", supportsUsageInStreaming: false, reasoning: false, toolCall: true, vision: false },
      subagents: { enabled: true, models: [] }
  };
  const submit = (prompt, configuration = config, tools = [], runId = crypto.randomUUID(), systemPrompt) => fetch(`${base}/v1/run`, { method: "POST", headers, body: JSON.stringify({
    runId, config: configuration,
    request: { messages: [{ role: "user", content: prompt, attachments: [] }], tools, metadata: {}, systemPrompt }
  }) });
  const response = await submit("launch-mobile-children");
  const body = await response.text();
  const events = body.trim().split("\n").map(JSON.parse);
  const completed = events.find(event => event.type === "completed");
  assert.ok(completed, body + "\n" + logs);
  assert.equal(completed.response.text, "All three children finished.", body + "\n" + logs);
  const children = completed.response.subagents;
  assert.equal(children.length, 3, body + "\n" + logs);
  assert.ok(children.every(child => child.status === "completed"), JSON.stringify(children));
  assert.ok(children.every(child => child.output.includes("mobile-child-")));
  assert.ok(children.every(child => child.model === "mobile-test" && child.provider.startsWith("yamabiko-custom-") && child.effort === "off"));
  assert.ok(peak >= 2, "children should execute concurrently");
  assert.equal(requests.length, 5, "one parent tool turn, three child turns, one parent final turn");
  assert.ok(!JSON.stringify(requests[0].messages).includes("You are an expert coding assistant operating inside pi"), "the SDK must not replace an empty mobile chat prompt with its desktop persona");
  assert.ok(events.some(event => event.type === "subagent_update" && event.subagent.status === "running"));
  assert.ok(!body.includes("test-key"), "credentials must not enter persisted progress");

  const profiles = ["openai-completions", "openai-responses", "anthropic-messages", "google-generative-ai", "mistral-conversations"].map((protocol, index) => ({
    id: `wire-${index}`, name: protocol,
    configuration: { ...config, model: `wire-${index}`, apiKey: `profile-secret-${index}`, thinkingLevel: "high", subagents: undefined,
      customEndpoint: { ...config.customEndpoint, modelId: `wire-${index}`, protocol, reasoning: true, reasoningEffort: "high", maxTokens: 4096,
        ...(protocol === "anthropic-messages" ? { thinkingBudget: 2048 } : {}) } }
  }));
  const configured = { ...config, subagents: { enabled: true, models: profiles } };
  const profileBody = await (await submit("launch-mobile-profiles", configured)).text();
  const profileResult = profileBody.trim().split("\n").map(JSON.parse).find(event => event.type === "completed");
  assert.ok(profileResult, profileBody + logs);
  assert.equal(profileResult.response.subagents.length, 5, profileBody);
  for (let index = 0; index < 5; index++) {
    const run = profileResult.response.subagents.find(run => run.model === `wire-${index}`);
    assert.equal(run?.status, "completed", profileBody);
    assert.equal(run.effort, "high");
    const captured = requests.find(request => request.model === `wire-${index}` || request.url.includes(`/wire-${index}:`));
    assert.ok(captured, JSON.stringify(requests));
    assert.ok(captured.authorization.endsWith(`profile-secret-${index}`), JSON.stringify(captured));
  }
  assert.ok(!profileBody.includes("profile-secret"));

  const defaultConfig = { ...configured, subagents: { ...configured.subagents, defaultModelID: "wire-3" } };
  for (const [prompt, expectedModel, effort] of [["launch-mobile-default", "wire-3", "high"], ["launch-mobile-inherit", "mobile-test", "off"]]) {
    const resultBody = await (await submit(prompt, defaultConfig)).text();
    const result = resultBody.trim().split("\n").map(JSON.parse).find(event => event.type === "completed");
    assert.equal(result?.response.subagents.length, 1, resultBody);
    assert.equal(result.response.subagents[0].model, expectedModel);
    assert.equal(result.response.subagents[0].effort, effort);
  }
  const unavailableBody = await (await submit("launch-mobile-default", { ...configured, subagents: { ...configured.subagents, defaultModelID: "retired" } })).text();
  assert.ok(unavailableBody.includes("subagent_default_model_unavailable"), unavailableBody);
  assert.equal(unavailableBody.trim().split("\n").map(JSON.parse).filter(event => event.type === "subagent_update").length, 0);
  const beforeFailure = requests.length;
  const failureBody = await (await submit("launch-mobile-error")).text();
  const failed = failureBody.trim().split("\n").map(JSON.parse).find(event => event.type === "completed");
  assert.equal(failed?.response.subagents[0].status, "failed", failureBody);
  assert.equal(requests.length - beforeFailure, 3, "provider failure must not select another endpoint or retry");

  const nativeResponse = await submit("launch-mobile-native", config, [{ type: "function", payload: {
    name: "mobile_probe", description: "Inspect native evidence", parameters: '{"type":"object","properties":{"query":{"type":"string"}}}'
  } }]);
  let buffer = "";
  const nativeEvents = [];
  for await (const bytes of nativeResponse.body) {
    buffer += new TextDecoder().decode(bytes);
    while (buffer.includes("\n")) {
      const index = buffer.indexOf("\n");
      const event = JSON.parse(buffer.slice(0, index));
      buffer = buffer.slice(index + 1);
      nativeEvents.push(event);
      if (event.type === "tool_request") {
        assert.ok(event.subagentId);
        assert.ok(event.toolCallId.startsWith(event.subagentId + ":"));
        const reply = await fetch(`${base}/v1/tool-result`, { method: "POST", headers, body: JSON.stringify({ requestId: event.requestId, content: "native-evidence", isError: false }) });
        assert.equal(reply.status, 200);
      }
    }
  }
  const nativeResult = nativeEvents.find(event => event.type === "completed");
  const nativeChild = nativeResult?.response.subagents[0];
  assert.equal(nativeChild?.status, "completed", JSON.stringify(nativeEvents));
  assert.ok(nativeChild.events.some(event => event.kind === "tool_start" && event.detail.includes("Inspect evidence")));
  assert.ok(nativeChild.events.some(event => event.kind === "tool_end" && event.detail.includes("native-evidence")));
  assert.ok(nativeChild.output.includes("native-evidence"));
  assert.ok(!nativeResult.response.providerTranscript.some(message => message.toolName === "mobile_probe"), "child tool transcript must not enter parent context");

  const textOnlyConfig = { ...config, subagents: { enabled: true, defaultModelID: "wire-0", models: [{
    ...profiles[0], configuration: { ...profiles[0].configuration, customEndpoint: { ...profiles[0].configuration.customEndpoint, toolCall: false } }
  }] } };
  const textOnlyBody = await (await submit("launch-mobile-default", textOnlyConfig, [{ type: "function", payload: {
    name: "mobile_probe", description: "Inspect evidence", parameters: '{"type":"object","properties":{}}'
  } }])).text();
  const textOnly = textOnlyBody.trim().split("\n").map(JSON.parse).find(event => event.type === "completed");
  assert.equal(textOnly?.response.subagents[0]?.status, "completed", textOnlyBody);
  const textOnlyWire = requests.filter(request => request.model === "wire-0").at(-1);
  assert.ok(!textOnlyWire.tools?.length, "catalog tool_call:false must suppress native and extension tools");

  const concurrentBodies = await Promise.all([
    submit("launch-mobile-default", { ...configured, subagents: { ...configured.subagents, defaultModelID: "wire-0" } }).then(response => response.text()),
    submit("launch-mobile-children", defaultConfig).then(response => response.text())
  ]);
  for (const [index, resultBody] of concurrentBodies.entries()) {
    const result = resultBody.trim().split("\n").map(JSON.parse).find(event => event.type === "completed");
    assert.equal(result?.response.subagents.length, index === 0 ? 1 : 3, resultBody);
    assert.ok(result.response.subagents.every(run => run.status === "completed" && run.model === (index === 0 ? "wire-0" : "wire-3")), resultBody);
  }

  const cancelResponse = await submit("launch-mobile-native", config, [{ type: "function", payload: {
    name: "mobile_probe", description: "Inspect evidence", parameters: '{"type":"object","properties":{}}'
  } }], "cancel-parent");
  let cancelBuffer = "";
  const cancelEvents = [];
  let requestedAbort = false;
  for await (const bytes of cancelResponse.body) {
    cancelBuffer += new TextDecoder().decode(bytes);
    while (cancelBuffer.includes("\n")) {
      const index = cancelBuffer.indexOf("\n");
      const event = JSON.parse(cancelBuffer.slice(0, index));
      cancelBuffer = cancelBuffer.slice(index + 1);
      cancelEvents.push(event);
      if (event.type === "tool_request" && !requestedAbort) {
        requestedAbort = true;
        const aborted = await fetch(`${base}/v1/abort`, { method: "POST", headers, body: JSON.stringify({ runId: "cancel-parent" }) });
        assert.equal(aborted.status, 200);
      }
    }
  }
  assert.ok(requestedAbort);
  assert.ok(cancelEvents.some(event => event.type === "subagent_update" && event.subagent.status === "cancelled"), JSON.stringify(cancelEvents));
  const health = await (await fetch(`${base}/health`, { headers })).json();
  // Health's extended counters are emitted when lifecycle logging is configured;
  // a late tool response is always rejected once its owning child was cancelled.
  const nativeRequest = cancelEvents.find(event => event.type === "tool_request");
  const lateReply = await fetch(`${base}/v1/tool-result`, { method: "POST", headers, body: JSON.stringify({ requestId: nativeRequest.requestId, content: "late" }) });
  assert.equal(lateReply.status, 404, JSON.stringify(health));
  const customStart = requests.length;
  await (await submit("launch-mobile-inherit", config, [], crypto.randomUUID(), "Keep this mobile conversation persona unchanged.")).text();
  assert.ok(JSON.stringify(requests[customStart].messages).includes("Keep this mobile conversation persona unchanged."));
  assert.ok(!JSON.stringify(requests[customStart].messages).includes("You are an expert coding assistant operating inside pi"));
  assert.equal(fs.existsSync(path.join(root, "spawn-attempts.log")), false,
    "Mobile parent and child sessions must not attempt desktop subprocess discovery");
});
