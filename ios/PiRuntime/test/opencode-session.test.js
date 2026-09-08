import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import net from "node:net";
import { once } from "node:events";
import { spawn } from "node:child_process";

// Observe the HTTP requests built by the bundled Pi adapters without external traffic.
test("OpenCode Go sends stable session headers through all Pi adapters", { timeout: 20000 }, async (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "yamabiko-opencode-"));
  const capture = path.join(root, "requests.jsonl");
  const mock = path.join(root, "mock.mjs");
  fs.writeFileSync(mock, `
    import fs from 'node:fs';
    globalThis.fetch = async (input, options) => {
      const request = new Request(input, options);
      fs.appendFileSync(${JSON.stringify(capture)}, JSON.stringify({
        url: request.url, headers: Object.fromEntries(request.headers)
      }) + '\\n');
      return new Response(JSON.stringify({ error: { message: 'test stop' } }), {
        status: 400, headers: { 'content-type': 'application/json' }
      });
    };
  `);
  const server = net.createServer().listen(0, "127.0.0.1");
  await once(server, "listening");
  const port = server.address().port;
  server.close();
  await once(server, "close");
  const child = spawn(process.execPath, ["--import", mock, new URL("../bundle/main.js", import.meta.url).pathname, String(port), "session-test"], { stdio: "ignore" });
  t.after(async () => {
    child.kill();
    await once(child, "exit");
    fs.rmSync(root, { recursive: true, force: true });
  });
  const base = `http://127.0.0.1:${port}`;
  const headers = { authorization: "Bearer session-test", "content-type": "application/json" };
  for (let i = 0; ; i++) {
    try { if ((await fetch(`${base}/health`, { headers })).ok) break; } catch {}
    assert.ok(i < 100, "runtime should start");
    await new Promise(r => setTimeout(r, 25));
  }
  let expectedCount = 0;
  for (const [model, endpoint] of [["kimi-k3", "/chat/completions"], ["minimax-m3", "/messages"], ["gpt-5.6-luna", "/responses"]]) {
    // Both native and models.dev identities resolve through this provider.
    for (const catalog of [false, true]) {
      for (const session of ["conversation-one", "conversation-one", "conversation-two"]) {
        const response = await fetch(`${base}/v1/run`, {
          method: "POST", headers,
          body: JSON.stringify({
            runId: `test-${expectedCount}`,
            config: { contractVersion: 2, provider: "opencode-go", model, apiKey: "test",
              ...(catalog ? { catalogContract: { providerName: "OpenCode Go" } } : {}) },
            request: { messages: [{ role: "user", content: "hello", attachments: [] }], tools: [], metadata: { promptCacheKey: session } }
          })
        });
        const output = await response.text();
        assert.equal(response.status, 200, output);
        const requests = fs.readFileSync(capture, "utf8").trim().split("\n").map(JSON.parse);
        assert.equal(requests.length, ++expectedCount, output);
        const request = requests.at(-1);
        assert.ok(request.url.endsWith(endpoint), request.url);
        assert.equal(request.headers["x-opencode-session"], session);
        assert.equal(request.headers["user-agent"], "YamabikoChat/1.0");
      }
    }
  }
});
