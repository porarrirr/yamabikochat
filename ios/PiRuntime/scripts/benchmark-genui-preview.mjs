import { performance } from 'node:perf_hooks';
import { createGenuiPreviewPublisher, genuiPreviewFromAgentEvent } from '../src/genui-preview.js';

// Fixed 8s tool-argument replay at 50 deltas/s. Timing below is CPU wall
// time, not simulated generation latency. No model, tool, or credentials.
const code = "const h=DIL.h;return h('col',{}," + Array.from({length: 100}, (_, i) =>
  `h('text',{},'項目${i}: 計算結果を表示します。'),`).join('') + ");";
const frames = Array.from({length: 400}, (_, i) => ({type: 'message_update',
  assistantMessageEvent: {type: i === 399 ? 'toolcall_end' : 'toolcall_delta', contentIndex: 0,
    partial: {content: [{type: 'toolCall', id: 'benchmark', name: 'genui',
      arguments: {title: '分析結果', code: code.slice(0, Math.ceil(code.length * (i + 1) / 400))}}]}}}));

function run(coalesce) {
  let time = 0, bytes = 0, snapshots = 0, final;
  const send = value => {
    const wire = JSON.stringify(value);
    bytes += Buffer.byteLength(wire);
    snapshots++;
    final = JSON.parse(wire);
  };
  const publisher = createGenuiPreviewPublisher(send, {now: () => time, schedule: () => 1, cancel: () => {}});
  const start = performance.now();
  for (const event of frames) {
    if (coalesce) publisher.accept(event);
    else send(genuiPreviewFromAgentEvent(event));
    time += 20;
  }
  publisher.flush();
  publisher.dispose();
  const ms = performance.now() - start;
  if (final.arguments.code !== code) throw new Error('Final canonical document was lost');
  return {ms, bytes, snapshots};
}
for (let i = 0; i < 10; i++) { run(false); run(true); }
const before = [], after = [];
for (let i = 0; i < 30; i++) { before.push(run(false)); after.push(run(true)); }
const median = values => values.slice().sort((a,b) => a-b)[Math.floor(values.length / 2)];
const summarize = values => ({medianMs: median(values.map(v => v.ms)), bytes: values[0].bytes, snapshots: values[0].snapshots});
console.log(JSON.stringify({workload: '400 GenUI argument deltas, 50/s, serialize + decode',
  before: summarize(before), after: summarize(after),
  reductionPercent: 100 * (1 - median(after.map(v => v.ms)) / median(before.map(v => v.ms)))}, null, 2));
