import assert from "node:assert/strict";
import { once } from "node:events";
import { spawn } from "node:child_process";
import http from "node:http";
import net from "node:net";
import readline from "node:readline";
import test from "node:test";
import { createRuntimeListener } from "../src/runtime-lifecycle.js";

async function availablePort() {
  const socket = net.createServer().listen(0, "127.0.0.1");
  await once(socket, "listening");
  const port = socket.address().port;
  socket.close();
  await once(socket, "close");
  return port;
}

function get(port) {
  return new Promise((resolve, reject) => {
    http.get({ host: "127.0.0.1", port, agent: false }, (res) => {
      let text = "";
      res.on("data", (chunk) => { text += chunk; });
      res.on("end", () => resolve(text));
    }).on("error", reject);
  });
}

test("reopens the same port without interrupting an accepted stream", async (t) => {
  const port = await availablePort();
  const servers = [];
  let streamingResponse;
  const transition = createRuntimeListener({
    port, log() {},
    createServer() {
      const server = http.createServer((req, res) => {
        if (req.url === "/stream") { streamingResponse = res; res.write("first"); }
        else res.end("healthy");
      });
      servers.push(server);
      return server;
    }
  });
  t.after(() => { for (const server of servers) { server.closeAllConnections(); server.close(); } });
  transition("resume");
  await once(servers.at(-1), "listening");
  const request = http.get({ host: "127.0.0.1", port, path: "/stream", agent: false });
  const [response] = await once(request, "response");
  let content = "";
  response.on("data", (chunk) => { content += chunk; });
  const ended = once(response, "end");
  const draining = transition("pause");
  assert.equal(await get(port), "healthy"); // Tool results can arrive during the background allowance.
  transition("resume");
  await draining; // A quick return must cancel the pending pause, not close the live listener.
  transition("pause");
  transition("suspend"); // iOS expires that allowance even if a stream is still active.
  await assert.rejects(get(port), { code: "ECONNREFUSED" });
  transition("resume");
  await once(servers.at(-1), "listening");
  assert.equal(await get(port), "healthy");
  streamingResponse.end("last");
  await ended;
  assert.equal(content, "firstlast");
  const finalRequest = http.get({ host: "127.0.0.1", port, path: "/stream", agent: false });
  const [finalResponse] = await once(finalRequest, "response");
  finalResponse.resume();
  const paused = transition("pause");
  streamingResponse.end("finished");
  await paused; // Normal completion closes the listener without waiting for expiration.
  await assert.rejects(get(port), { code: "ECONNREFUSED" });
  for (let i = 0; i < 20; i++) {
    transition("pause");
    transition("pause");
    transition("resume");
    transition("pause"); // Also cover a queued listen which has not completed.
    transition("resume");
    transition("resume");
    await once(servers.at(-1), "listening");
    assert.equal(await get(port), "healthy");
  }
});

test("native pipe drives bundled runtime through repeated suspension with unchanged runtime identity", async (t) => {
  const port = await availablePort();
  const child = spawn(process.execPath,
    [new URL("../bundle/main.js", import.meta.url).pathname, String(port), "lifecycle-test", "", "3", "4"],
    { stdio: ["ignore", "ignore", "pipe", "pipe", "pipe"] });
  let errors = "";
  child.stderr.on("data", (chunk) => { errors += chunk; });
  t.after(() => child.kill());
  const acknowledgements = readline.createInterface({ input: child.stdio[4] });
  let generation = 0;
  async function command(state) {
    const ack = once(acknowledgements, "line", { signal: AbortSignal.timeout(5000) });
    child.stdio[3].write(`${state}:${++generation}\n`);
    assert.deepEqual(await ack, [String(generation)], errors);
  }
  const pid = child.pid;
  await command("pause"); // Initial background startup must not open a listener.
  await assert.rejects(get(port), { code: "ECONNREFUSED" });
  for (let i = 0; i < 10; i++) {
    await command("resume");
    const response = await fetch(`http://127.0.0.1:${port}/health`, {
      headers: { authorization: "Bearer lifecycle-test", connection: "close" }
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).contractVersion, 2);
    assert.equal(child.pid, pid);
    assert.equal(child.exitCode, null, errors);
    await command("pause");
    await assert.rejects(get(port), { code: "ECONNREFUSED" });
  }
});
