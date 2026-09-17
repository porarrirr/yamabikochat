import { AsyncLocalStorage } from 'node:async_hooks';
import { createProvider, createAssistantMessageEventStream } from '@earendil-works/pi-ai';

export const PCC_PROVIDER = 'apple-pcc';
export const PCC_MODEL = 'PrivateCloudComputeLanguageModel';
const nativeScope = new AsyncLocalStorage();
const pending = new Map();
export const withPCCBridge = (bridge, action) => nativeScope.run(bridge, action);

export function receivePCCEvent(event) {
  const entry = pending.get(event.requestId);
  if (!entry || entry.runId !== event.runId) return false;
  entry.deliver(event);
  return true;
}

export function pccResolution(config, models) {
  const unavailable = (reason) => ({ supported: false, reason, provider: PCC_PROVIDER, model: config.model });
  if (config.catalogContract != null) return unavailable('pcc_catalog_contract_unsupported');
  if (config.model !== PCC_MODEL) return unavailable('pcc_model_unsupported');
  const capability = config.nativePCC;
  if (![1, 2].includes(capability?.version)) return unavailable('pcc_native_bridge_unavailable');
  if (!capability.available) return unavailable(capability.reason || 'pcc_unavailable');
  if (!Number.isSafeInteger(capability.contextSize) || capability.contextSize <= 0) return unavailable('pcc_context_unavailable');
  const model = {
    id: PCC_MODEL, name: 'Apple Intelligence — Private Cloud Compute',
    provider: PCC_PROVIDER, api: 'apple-foundation-models-pcc', baseUrl: null,
    reasoning: true, input: ['text', 'image'],
    // Apple allows an uncapped response to occupy the remaining context window.
    contextWindow: capability.contextSize, maxTokens: capability.contextSize,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    thinkingLevelMap: { low: 'light', medium: 'moderate', high: 'deep', off: null, minimal: null, xhigh: null, max: null }
  };
  models.setProvider(createProvider({
    id: PCC_PROVIDER, name: model.name,
    auth: { apiKey: { name: 'Apple Intelligence', resolve: async () => ({ auth: {} }) } },
    models: [model], api: { stream: streamPCC, streamSimple: streamPCC }
  }));
  return { supported: true, provider: PCC_PROVIDER, model: PCC_MODEL, api: model.api,
    source: `apple_sdk_native_contract_v${capability.version}`, reasoning: true, input: model.input,
    contextWindow: model.contextWindow, maxTokens: model.maxTokens, toolCall: capability.version === 2 };
}

export function unknownUsage() {
  return { input: null, output: null, cacheRead: null, cacheWrite: null, reasoning: null,
    totalTokens: null, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
}

export function appleUsage(value) {
  for (const field of ['inputTokens', 'cachedInputTokens', 'outputTokens', 'reasoningTokens']) {
    if (!Number.isSafeInteger(value?.[field]) || value[field] < 0) throw new Error('pcc_invalid_usage');
  }
  if (value.cachedInputTokens > value.inputTokens || value.reasoningTokens > value.outputTokens) throw new Error('pcc_invalid_usage');
  return { ...unknownUsage(), input: value.inputTokens - value.cachedInputTokens,
    cacheRead: value.cachedInputTokens, output: value.outputTokens, reasoning: value.reasoningTokens,
    totalTokens: value.inputTokens + value.outputTokens };
}

function streamPCC(model, context, options = {}) {
  const stream = createAssistantMessageEventStream();
  const bridge = nativeScope.getStore();
  const output = { role: 'assistant', api: model.api, provider: model.provider, model: model.id,
    content: [], usage: unknownUsage(), stopReason: 'pending', timestamp: Date.now() };
  const requestId = crypto.randomUUID();
  let finished = false;
  let timer;
  const nativeCalls = new Map();
  const partialSnapshot = () => structuredClone(output);
  function finish(error) {
    if (finished) return;
    finished = true;
    clearTimeout(timer);
    options.signal?.removeEventListener('abort', abort);
    pending.delete(requestId);
    if (error) {
      output.stopReason = options.signal?.aborted ? 'aborted' : 'error';
      output.errorMessage = error.message;
      output.errorCode = error.code || 'pcc_native_failure';
      stream.push({ type: 'error', reason: output.stopReason, error: output });
    } else {
      if (output.content.length) stream.push({ type: 'text_end', contentIndex: 0, content: output.content[0].text, partial: partialSnapshot() });
      output.stopReason = 'unknown';
      stream.push({ type: 'done', reason: 'unknown', message: output });
    }
    stream.end();
  }
  function abort() {
    bridge?.send({ type: 'pcc_cancel', runId: bridge.runId, requestId });
    finish(Object.assign(new Error('PCC request cancelled'), { code: 'pcc_cancelled' }));
  }
  stream.push({ type: 'start', partial: partialSnapshot() });
  queueMicrotask(async () => {
    try {
      if (!bridge) throw new Error('pcc_native_bridge_unavailable');
      if (options.signal?.aborted) { abort(); return; }
      const reasoningLevel = {
        low: 'light', medium: 'moderate', high: 'deep',
        light: 'light', moderate: 'moderate', deep: 'deep'
      }[options.reasoning ?? 'medium'];
      if (!reasoningLevel) throw new Error('pcc_reasoning_unsupported');
      // PCC's user-authorized SDK loop executes tools natively. Never place
      // these completed calls in Pi content (the Agent would execute them again).
      if (options.maxTokens != null && (!Number.isSafeInteger(options.maxTokens) || options.maxTokens <= 0)) throw new Error('pcc_invalid_output_limit');
      const payload = { context, reasoningLevel, contextSize: model.contextWindow };
      if (options.maxTokens != null) payload.maximumResponseTokens = options.maxTokens;
      const prepared = await options.onPayload?.(payload, model) ?? payload;
      if (options.signal?.aborted) { abort(); return; }
      pending.set(requestId, { runId: bridge.runId, deliver(event) {
        try {
          if (event.type === 'error') {
            finish(Object.assign(new Error(event.message || 'PCC failed'), { code: event.errorCode }));
          } else if (event.type === 'tool_start') {
            const call = event.toolCall;
            if (!call || typeof call.id !== 'string' || !call.id || typeof call.argumentsJSON !== 'string' ||
                nativeCalls.has(call.id) || !(context.tools || []).some(tool => tool.name === call.name)) {
              throw new Error('pcc_invalid_tool_call');
            }
            const args = JSON.parse(call.argumentsJSON);
            if (!args || typeof args !== 'object' || Array.isArray(args)) throw new Error('pcc_invalid_tool_arguments');
            nativeCalls.set(call.id, { call, completed: false });
            output.pccToolCalls = [...nativeCalls.values()].map(entry => entry.call);
            bridge.send({ type: 'tool_start', runId: bridge.runId, toolCallId: call.id, name: call.name, timeMs: Date.now() });
          } else if (event.type === 'tool_end') {
            const entry = nativeCalls.get(event.toolCall?.id);
            if (!entry || entry.completed || entry.call.name !== event.toolCall.name ||
                event.toolResult?.callId !== entry.call.id || event.toolResult?.name !== entry.call.name) {
              throw new Error('pcc_invalid_tool_result');
            }
            entry.completed = true;
            output.pccToolResults = [...(output.pccToolResults || []), event.toolResult];
            bridge.send({ type: 'tool_end', runId: bridge.runId, toolCallId: entry.call.id, name: entry.call.name,
              succeeded: !event.toolResult.isError, timeMs: Date.now() });
          } else if (event.type === 'snapshot'  || event.type === 'completed') {
            if (typeof event.text !== 'string') throw new Error('pcc_invalid_snapshot');
            const previous = output.content[0]?.text || '';
            output.usage = appleUsage(event.usage);
            if (!output.content.length) {
              output.content.push({ type: 'text', text: '' });
              stream.push({ type: 'text_start', contentIndex: 0, partial: partialSnapshot() });
            }
            // Foundation Models streams cumulative snapshots, not immutable token
            // deltas. A later snapshot may revise an earlier span. Keep Pi's
            // partial message authoritative and let the native bridge forward the
            // complete replacement snapshot to consumers.
            const delta = event.text.startsWith(previous) ? event.text.slice(previous.length) : '';
            output.content[0].text = event.text;
            if (event.text !== previous) stream.push({ type: 'text_delta', contentIndex: 0, delta, partial: partialSnapshot() });
            if (event.type === 'completed') {
              if ([...nativeCalls.values()].some(entry => !entry.completed)) throw new Error('pcc_tool_result_missing');
              if (typeof event.sessionReused === 'boolean') output.pccSessionReused = event.sessionReused;
              if (typeof event.contextCompacted === 'boolean') output.pccContextCompacted = event.contextCompacted;
              if (event.transcript != null) {
                if (typeof event.transcript !== 'string') throw new Error('pcc_invalid_transcript');
                JSON.parse(event.transcript);
                output.pccTranscript = event.transcript;
              }
              if (nativeCalls.size && !output.pccTranscript) throw new Error('pcc_tool_history_missing');
              finish();
            }
          } else throw new Error('pcc_invalid_event');
        } catch (error) {
          bridge.send({ type: 'pcc_cancel', runId: bridge.runId, requestId });
          finish(error);
        }
      } });
      options.signal?.addEventListener('abort', abort, { once: true });
      timer = setTimeout(() => {
        bridge.send({ type: 'pcc_cancel', runId: bridge.runId, requestId });
        finish(Object.assign(new Error('PCC request timed out'), { code: 'pcc_timeout' }));
      }, options.timeoutMs > 0 ? options.timeoutMs : 300000);
      timer.unref?.();
      bridge.send({ type: 'pcc_request', runId: bridge.runId, requestId, pcc: prepared });
    } catch (error) { finish(error); }
  });
  return stream;
}
