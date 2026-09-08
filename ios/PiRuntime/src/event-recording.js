// Diagnostic events contain deltas and metadata; final messages live in state.
export function exportableAgentEvent(event, sanitize) {
  const { message, messages, assistantMessageEvent, ...metadata } = event;
  if (assistantMessageEvent) {
    const { partial, ...delta } = assistantMessageEvent;
    metadata.assistantMessageEvent = delta;
  }
  return sanitize(metadata);
}

export function createEventRecorder(sanitize, onLimit, maxBytes = 2 * 1024 * 1024) {
  const events = [];
  let bytes = 0;
  let dropped = 0;
  return {
    events,
    get dropped() { return dropped; },
    record(event) {
      const value = { seq: events.length + dropped, time: Date.now(), event: exportableAgentEvent(event, sanitize) };
      const size = Buffer.byteLength(JSON.stringify(value));
      if (bytes + size <= maxBytes) {
        events.push(value);
        bytes += size;
      } else {
        if (++dropped === 1) onLimit();
      }
    }
  };
}
