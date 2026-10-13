import test from 'node:test';
import assert from 'node:assert/strict';
import {genuiPreviewFromAgentEvent} from '../src/genui-preview.js';

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
