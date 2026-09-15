import assert from 'node:assert/strict';
import test from 'node:test';
import { Agent } from '@earendil-works/pi-agent-core';
import { createModels, calculateCost } from '@earendil-works/pi-ai';
import { PCC_PROVIDER, PCC_MODEL, pccResolution, withPCCBridge, receivePCCEvent, appleUsage, unknownUsage } from '../src/pcc-provider.js';
import { providerUsage, aggregateUsage } from '../src/usage-contract.js';

const config = { provider: PCC_PROVIDER, model: PCC_MODEL, nativePCC: { version: 1, available: true, contextSize: 32768 } };
const usage = { inputTokens: 20, cachedInputTokens: 5, outputTokens: 8, reasoningTokens: 3 };
function setup() {
  const models = createModels();
  assert.equal(pccResolution(config, models).supported, true);
  return { models, model: models.getModel(PCC_PROVIDER, PCC_MODEL) };
}

test('PCC requires a native capability on every resolution, including after registration', () => {
  const { models } = setup();
  assert.equal(pccResolution({ ...config, nativePCC: undefined }, models).reason, 'pcc_native_bridge_unavailable');
  assert.equal(pccResolution({ ...config, catalogContract: { provenance: 'model' } }, models).reason, 'pcc_catalog_contract_unsupported');
  assert.equal(pccResolution({ ...config, model: 'guessed-model' }, models).reason, 'pcc_model_unsupported');
  assert.equal(pccResolution({ ...config, nativePCC: { version: 1, available: false, reason: 'pcc_os_unsupported' } }, models).reason, 'pcc_os_unsupported');
  assert.equal(pccResolution({ ...config, nativePCC: { version: 1, available: true } }, models).reason, 'pcc_context_unavailable');
});

test('PCC runs through Pi Agent and preserves unknown termination and unreported usage', async () => {
  const { models, model } = setup();
  const events = [];
  let requests = 0;
  const image = { type: 'image', data: 'aGVsbG8=', mimeType: 'image/png' };
  const messages = [{ role: 'user', content: [{ type: 'text', text: 'Describe' }, image], timestamp: 1 }];
  const agent = new Agent({ initialState: { model, messages, tools: [], thinkingLevel: 'medium' }, streamFn: models.streamSimple.bind(models) });
  agent.subscribe(e => events.push(e));
  await withPCCBridge({ runId: 'run-1', send(event) {
    assert.equal(event.type, 'pcc_request');
    requests++;
    assert.equal(event.pcc.reasoningLevel, 'moderate');
    assert.deepEqual(event.pcc.context.messages[0].content[1], image);
    assert.equal(receivePCCEvent({ ...event, runId: 'wrong-run', type: 'completed', text: 'bad', usage }), false);
    assert.equal(receivePCCEvent({ ...event, type: 'snapshot', text: 'A', usage }), true);
    assert.equal(receivePCCEvent({ ...event, type: 'completed', text: 'A cat', usage }), true);
    assert.equal(receivePCCEvent({ ...event, type: 'completed', text: 'duplicate', usage }), false);
  } }, () => agent.continue());
  const message = agent.state.messages.at(-1);
  assert.equal(requests, 1);
  assert.equal(message.stopReason, 'unknown');
  assert.equal(message.usage.cacheWrite, null);
  assert.equal(message.usage.input, 15);
  assert.equal(message.usage.totalTokens, 28);
  assert.equal(events.filter(e => e.type === 'agent_end').length, 1);
  const restored = JSON.parse(JSON.stringify(message));
  assert.equal(restored.stopReason, 'unknown');
  assert.equal(providerUsage(restored.usage).cacheCreationInputTokens, null);
  assert.equal(aggregateUsage([message, message]).cacheCreationInputTokens, null);
  assert.equal(aggregateUsage([message, message]).totalTokens, 56);
  assert.equal(calculateCost(model, message.usage).total, 0);
});

test('partial/unknown usage cannot turn into a known monetary cost', () => {
  const { model } = setup();
  const result = unknownUsage();
  assert.equal(calculateCost({ ...model, cost: { input: 1, output: 1, cacheRead: 1, cacheWrite: 1 } }, result).total, null);
  assert.equal(providerUsage(result).inputTokens, null);
  assert.throws(() => appleUsage({ ...usage, cachedInputTokens: 100 }), /invalid_usage/);
});

test('native quota errors are terminal and keep their code', async () => {
  const { models, model } = setup();
  const result = await withPCCBridge({ runId: 'quota', send(event) {
    receivePCCEvent({ ...event, type: 'error', errorCode: 'pcc_quota_limit_reached', message: 'Limit reached' });
  } }, () => models.streamSimple(model, { messages: [] }, { reasoning: 'medium' }).result());
  assert.equal(result.stopReason, 'error');
  assert.equal(result.errorCode, 'pcc_quota_limit_reached');
  assert.equal(result.usage.totalTokens, null);
});

test('abort cancels the native request and rejects late completion', async () => {
  const { models, model } = setup();
  const controller = new AbortController();
  let request;
  const events = [];
  const result = await withPCCBridge({ runId: 'abort', send(event) {
    events.push(event);
    if (event.type === 'pcc_request') { request = event; queueMicrotask(() => controller.abort()); }
  } }, () => models.streamSimple(model, { messages: [] }, { reasoning: 'medium', signal: controller.signal }).result());
  assert.equal(result.stopReason, 'aborted');
  assert.equal(events.at(-1).type, 'pcc_cancel');
  assert.equal(receivePCCEvent({ ...request, type: 'completed', text: 'late', usage }), false);
});

test('invalid snapshots cancel native generation instead of duplicating text', async () => {
  const { models, model } = setup();
  const events = [];
  const result = await withPCCBridge({ runId: 'invalid', send(event) {
    events.push(event);
    if (event.type !== 'pcc_request') return;
    receivePCCEvent({ ...event, type: 'snapshot', text: 'old', usage });
    receivePCCEvent({ ...event, type: 'snapshot', text: 'new', usage });
  } }, () => models.streamSimple(model, { messages: [] }, { reasoning: 'medium' }).result());
  assert.equal(result.stopReason, 'error');
  assert.equal(events.at(-1).type, 'pcc_cancel');
});

test('PCC v2 exposes tools only for the verified native identity', () => {
  const { models } = setup();
  const native = { ...config, nativePCC: { ...config.nativePCC, version: 2 } };
  assert.equal(pccResolution(native, models).toolCall, true);
  assert.equal(pccResolution(config, models).toolCall, false);
  assert.equal(pccResolution({ ...native, model: 'SystemLanguageModel' }, models).supported, false);
  assert.equal(pccResolution({ ...native, catalogContract: {} }, models).supported, false);
});

test('Apple-managed tool loop preserves native history and never re-executes tools in Pi', async () => {
  const { models, model } = setup();
  let piExecutions = 0;
  const nativeEvents = [];
  const tools = ['web_search', 'python_execute'].map(name => ({
    name, label: name, description: name, parameters: { type: 'object', properties: {} },
    execute: async () => { piExecutions++; return { content: [] }; }
  }));
  const agent = new Agent({ initialState: { model, messages: [{ role: 'user', content: 'Search then calculate', timestamp: 1 }], tools }, streamFn: models.streamSimple.bind(models) });
  let requests = 0;
  await withPCCBridge({ runId: 'native-tools', send(event) {
    nativeEvents.push(event);
    if (event.type !== 'pcc_request') return;
    requests++;
    assert.deepEqual(event.pcc.context.tools.map(tool => tool.name), tools.map(tool => tool.name));
    for (const [index, tool] of tools.entries()) {
      const call = { id: `call-${index}`, name: tool.name, argumentsJSON: '{}' };
      assert.equal(receivePCCEvent({ ...event, type: 'tool_start', toolCall: call }), true);
      assert.equal(receivePCCEvent({ ...event, type: 'tool_end', toolCall: call,
        toolResult: { callId: call.id, name: call.name, content: '42', isError: false } }), true);
    }
    receivePCCEvent({ ...event, type: 'completed', text: 'The result is 42', usage, transcript: '{"entries":[]}' });
  } }, () => agent.continue());
  const output = JSON.parse(JSON.stringify(agent.state.messages.at(-1)));
  assert.equal(requests, 1);
  assert.equal(piExecutions, 0);
  assert.equal(output.stopReason, 'unknown');
  assert.equal(output.pccToolCalls.length, 2);
  assert.equal(output.pccToolResults.length, 2);
  assert.equal(output.pccTranscript, '{"entries":[]}');
  assert.equal(output.content.some(block => block.type === 'toolCall'), false);
  assert.equal(output.usage.totalTokens, 28);
  assert.equal(nativeEvents.filter(event => event.type === 'tool_start').length, 2);
  assert.equal(nativeEvents.filter(event => event.type === 'tool_end').length, 2);
  await withPCCBridge({ runId: 'follow-up', send(event) {
    assert.equal(event.pcc.context.messages[0].pccTranscript, output.pccTranscript);
    receivePCCEvent({ ...event, type: 'completed', text: 'Still 42', usage });
  } }, () => models.streamSimple(model, { messages: [output, { role: 'user', content: 'Repeat' }] }, { reasoning: 'medium' }).result());
});

test('PCC rejects unauthorized, duplicate, incomplete and unpaired native tool events', async () => {
  const { models, model } = setup();
  const call = { id: 'call', name: 'web_search', argumentsJSON: '{}' };
  for (const mode of ['unauthorized', 'duplicate', 'unpaired', 'pending', 'missing-history']) {
    const emitted = [];
    const output = await withPCCBridge({ runId: mode, send(event) {
      emitted.push(event);
      if (event.type !== 'pcc_request') return;
      if (mode === 'unpaired') {
        receivePCCEvent({ ...event, type: 'tool_end', toolCall: call });
        return;
      }
      receivePCCEvent({ ...event, type: 'tool_start', toolCall: { ...call, name: mode === 'unauthorized' ? 'unknown' : call.name } });
      if (mode === 'duplicate') receivePCCEvent({ ...event, type: 'tool_start', toolCall: call });
      if (mode === 'missing-history') receivePCCEvent({ ...event, type: 'tool_end', toolCall: call,
        toolResult: { callId: call.id, name: call.name, content: 'done', isError: false } });
      receivePCCEvent({ ...event, type: 'completed', text: 'done', usage });
    } }, () => models.streamSimple(model, { messages: [], tools: [{ name: 'web_search' }] }, { reasoning: 'medium' }).result());
    assert.equal(output.stopReason, 'error', mode);
    assert.equal(emitted.filter(event => event.type === 'pcc_request').length, 1, mode);
    assert.equal(emitted.at(-1).type, 'pcc_cancel', mode);
  }
});

test('cancellation during native tool execution rejects late tool results', async () => {
  const { models, model } = setup();
  const controller = new AbortController();
  let request;
  const call = { id: 'call', name: 'web_search', argumentsJSON: '{}' };
  const output = await withPCCBridge({ runId: 'cancel-tool', send(event) {
    if (event.type !== 'pcc_request') return;
    request = event;
    receivePCCEvent({ ...event, type: 'tool_start', toolCall: call });
    controller.abort();
  } }, () => models.streamSimple(model, { messages: [], tools: [{ name: 'web_search' }] }, { reasoning: 'medium', signal: controller.signal }).result());
  assert.equal(output.stopReason, 'aborted');
  assert.equal(receivePCCEvent({ ...request, type: 'tool_end', toolCall: call }), false);
});
