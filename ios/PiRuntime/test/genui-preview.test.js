import test from 'node:test';
import assert from 'node:assert/strict';
import {genuiPreviewFromAgentEvent, createGenuiPreviewPublisher} from '../src/genui-preview.js';

test('forwards Pi repaired arguments without reparsing or executing them', () => {
  const argumentsValue = {title:'View',ui:{type:'col',children:[{type:'text',children:['partial']}]}};
  const partial={content:[{type:'toolCall',id:'call',name:'genui',arguments:argumentsValue}]};
  const value=genuiPreviewFromAgentEvent({type:'message_update',assistantMessageEvent:{type:'toolcall_delta',contentIndex:0,partial}});
  assert.equal(value.arguments,argumentsValue);
  assert.equal(value.toolCallId,'call');
});

test('ignores other tools and ordinary assistant text',()=>{
  const message={content:[{type:'toolCall',id:'call',name:'python_execute',arguments:{code:'pass'}}]};
  assert.equal(genuiPreviewFromAgentEvent({type:'message_update',message,assistantMessageEvent:{type:'toolcall_delta',contentIndex:0}}),null);
  assert.equal(genuiPreviewFromAgentEvent({type:'message_update',assistantMessageEvent:{type:'text_delta',delta:'text'}}),null);
});

test('final tool argument snapshot uses the same canonical call identity',()=>{
  const message={content:[{type:'toolCall',id:'canonical',name:'genui',arguments:{document:'{"title":"View"}'}}]};
  const value=genuiPreviewFromAgentEvent({type:'message_update',message,assistantMessageEvent:{type:'toolcall_end',contentIndex:0}});
  assert.equal(value.toolCallId,'canonical');
  assert.equal(value.arguments.document,'{"title":"View"}');
});

function previewEvent(id, title, type = 'toolcall_delta') {
  return {type: 'message_update', assistantMessageEvent: {type, contentIndex: 0,
    partial: {content: [{type: 'toolCall', id, name: 'genui', arguments: {title}}]}}};
}

test('coalesces before serialization and always delivers the canonical final arguments', () => {
  let time = 0;
  let timer;
  const sent = [];
  const publisher = createGenuiPreviewPublisher(value => sent.push(structuredClone(value)), {
    now: () => time, schedule: callback => { timer = callback; return 1; }, cancel: () => { timer = null; }
  });
  publisher.accept(previewEvent('a', 'first', 'toolcall_start'));
  for (let i = 1; i <= 9; i++) { time = i * 10; publisher.accept(previewEvent('a', String(i))); }
  assert.equal(sent.length, 1);
  time = 100;
  timer();
  assert.equal(sent.at(-1).arguments.title, '9');
  time = 110;
  publisher.accept(previewEvent('a', 'pending'));
  publisher.accept(previewEvent('a', 'final', 'toolcall_end'));
  assert.equal(sent.at(-1).arguments.title, 'final');
  assert.equal(timer, null);
  assert.equal(sent.length, 3);
});

test('flushes independent calls before tool execution and cancels pending work on disposal', () => {
  const sent = [];
  const timers = new Set();
  const publisher = createGenuiPreviewPublisher(value => sent.push(value), {
    now: () => 0, schedule: callback => { timers.add(callback); return callback; }, cancel: timer => timers.delete(timer)
  });
  publisher.accept(previewEvent('a', 'first'));
  publisher.accept(previewEvent('b', 'first'));
  publisher.accept(previewEvent('a', 'latest a'));
  publisher.accept(previewEvent('b', 'latest b'));
  publisher.flush('a');
  assert.equal(sent.at(-1).arguments.title, 'latest a');
  publisher.flush();
  assert.equal(sent.at(-1).arguments.title, 'latest b');
  publisher.accept(previewEvent('a', 'discarded'));
  const callback = [...timers][0];
  publisher.dispose();
  callback(); // Even an already dequeued timer cannot publish after cancellation.
  publisher.accept(previewEvent('a', 'also discarded'));
  assert.equal(sent.length, 4);
  assert.equal(timers.size, 0);
});
