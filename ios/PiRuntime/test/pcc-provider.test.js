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
