import assert from "node:assert/strict";
import test from "node:test";
import { createEventRecorder, exportableAgentEvent } from "../src/event-recording.js";

const sanitize = (value) => JSON.parse(JSON.stringify(value));

test("removes cumulative snapshots before deep serialization", () => {
  const cumulative = { toJSON() { throw new Error("Cumulative message was serialized"); } };
  const event = exportableAgentEvent({ type: "message_update", message: cumulative,
    assistantMessageEvent: { type: "text_delta", delta: "answer", partial: cumulative } }, sanitize);
  assert.deepEqual(event, { type: "message_update", assistantMessageEvent: { type: "text_delta", delta: "answer" } });
});

test("recorded event bytes grow linearly and are bounded", () => {
  const size = (count) => {
    const recorder = createEventRecorder(sanitize, () => assert.fail("Unexpected truncation"));
    for (let i = 0; i < count; i++) recorder.record({ type: "message_update", assistantMessageEvent: {
      type: "thinking_delta", delta: "abcdefgh", partial: { content: "abcdefgh".repeat(i) }
    } });
    return JSON.stringify(recorder.events).length;
  };
  assert.ok(size(2000) / size(1000) < 2.1);
  let limits = 0;
  const recorder = createEventRecorder(sanitize, () => limits++, 1024);
  for (let i = 0; i < 1000; i++) recorder.record({ type: "tool_execution_update", delta: "x".repeat(100) });
  assert.ok(JSON.stringify(recorder.events).length < 1100);
  assert.ok(recorder.dropped > 0);
  assert.equal(limits, 1);
});
