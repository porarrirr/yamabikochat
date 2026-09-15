import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import net from 'node:net';
import test from 'node:test';
import { PCC_MODEL } from '../src/pcc-provider.js';

test('authenticated PCC bridge resolves and streams through the bundled Pi agent', async t => {
  const listener = net.createServer().listen(0, '127.0.0.1');
  await once(listener, 'listening');
  const port = listener.address().port;
  listener.close(); await once(listener, 'close');
  const token = 'pcc-test-token';
  const process = spawn(globalThis.process.execPath, [new URL('../bundle/main.js', import.meta.url).pathname, String(port), token], { stdio: ['ignore', 'pipe', 'pipe'] });
  t.after(() => process.kill());
  const base = `http://127.0.0.1:${port}`;
  const headers = { authorization: `Bearer ${token}`, 'content-type': 'application/json' };
  for (let i = 0; i < 200; i++) {
    try { if ((await fetch(`${base}/health`, { headers })).ok) break; } catch {}
    await new Promise(r => setTimeout(r, 25));
  }
  const post = (path, body, auth = headers) => fetch(`${base}${path}`, { method: 'POST', headers: auth, body: JSON.stringify(body) });
  assert.equal((await post('/v1/pcc-event', {}, {})).status, 401);
  const config = { contractVersion: 2, provider: 'apple-pcc', model: PCC_MODEL, thinkingLevel: 'high', nativePCC: { version: 1, available: true, contextSize: 32768 } };
  const result = await (await post('/v1/models/resolve', { models: [config, { ...config, nativePCC: undefined }, { ...config, nativePCC: { version: 1, available: false, reason: 'pcc_quota_limit_reached' } }] })).json();
  assert.equal(result.models[0].toolCall, false);
  assert.deepEqual(result.models[0].input, ['text', 'image']);
  assert.equal(result.models[1].supported, false);
  assert.equal(result.models[2].reason, 'pcc_quota_limit_reached');

  async function run(runId, nativeError, useTools = false, previous = null) {
    const response = await post('/v1/run', { runId, config: { ...config, nativePCC: { ...config.nativePCC, version: 2 } },
      request: { messages: [...(previous ? [previous] : []), { role: 'user', content: 'Hello', attachments: [] }],
        tools: useTools ? [{ type: 'function', payload: { name: 'web_search', description: 'Search', parameters: '{"type":"object","properties":{}}' } }] : [], metadata: {} } });
    const events = [];
    let text = '';
    for await (const bytes of response.body) {
      text += Buffer.from(bytes).toString('utf8');
      let index;
      while ((index = text.indexOf('\n')) >= 0) {
        const line = text.slice(0, index); text = text.slice(index + 1);
        if (!line) continue;
        const event = JSON.parse(line); events.push(event);
        assert.notEqual(event.type, 'tool_request', 'Pi must not execute an Apple-managed call');
        if (event.type === 'pcc_request') {
          assert.equal(event.pcc.reasoningLevel, 'deep');
          if (previous) assert.equal(event.pcc.context.messages[0].pccTranscript, previous.piMessage.pccTranscript);
          if (useTools) {
            assert.equal(event.pcc.context.tools[0].name, 'web_search');
            const toolCall = { id: 'native-call', name: 'web_search', argumentsJSON: '{}' };
            assert.equal((await post('/v1/pcc-event', { type: 'tool_start', runId, requestId: event.requestId, toolCall })).status, 200);
            assert.equal((await post('/v1/pcc-event', { type: 'tool_end', runId, requestId: event.requestId, toolCall,
              toolResult: { callId: toolCall.id, name: toolCall.name, content: 'found', isError: false } })).status, 200);
          }
          const body = nativeError
            ? { type: 'error', message: 'Daily limit reached', errorCode: 'pcc_quota_limit_reached' }
            : { type: 'completed', text: 'Hello from PCC', ...(useTools ? { transcript: '{"entries":[]}' } : {}), usage: { inputTokens: 4, cachedInputTokens: 0, outputTokens: 5, reasoningTokens: 1 } };
          assert.equal((await post('/v1/pcc-event', { ...body, runId: 'wrong', requestId: event.requestId })).status, 404);
          assert.equal((await post('/v1/pcc-event', { ...body, runId, requestId: event.requestId })).status, 200);
        }
      }
    }
    return events;
  }
  const events = await run('success', false);
  const completion = events.find(e => e.type === 'completed');
  assert.ok(completion, JSON.stringify(events));
  assert.equal(completion.response.text, 'Hello from PCC');
  assert.equal(completion.response.usage.cacheCreationInputTokens, null);
  assert.equal(completion.response.piExecution.state.messages.at(-1).stopReason, 'unknown');
  const nativeEvents = await run('native-tools', false, true);
  const nativeResponse = nativeEvents.find(event => event.type === 'completed')?.response;
  assert.ok(nativeResponse, JSON.stringify(nativeEvents));
  assert.equal(nativeResponse.toolCalls[0].name, 'web_search');
  assert.equal(nativeResponse.usage.contextTokens, null);
  assert.equal(nativeResponse.usage.contextWindow, 32768);
  assert.equal(nativeResponse.usage.totalTokens, 9);
  assert.equal(nativeEvents.filter(event => event.type === 'tool_start').length, 1);
  assert.equal(nativeEvents.filter(event => event.type === 'tool_end').length, 1);
  assert.equal(nativeResponse.providerTranscript[0].piMessage.pccTranscript, '{"entries":[]}');
  const followup = await run('native-followup', false, false, nativeResponse.providerTranscript[0]);
  assert.ok(followup.some(event => event.type === 'completed'));
  const errors = await run('quota', true);
  assert.equal(errors.filter(e => e.type === 'pcc_request').length, 1);
  assert.equal(errors.at(-1).errorCode, 'PCC_QUOTA_LIMIT_REACHED');
});
