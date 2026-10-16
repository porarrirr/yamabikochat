// Read Pi's already-parsed tool arguments; this never executes a tool or resolves a model.
export function genuiPreviewFromAgentEvent(event) {
  const update = event?.assistantMessageEvent;
  if (event?.type !== 'message_update' || !['toolcall_start', 'toolcall_delta', 'toolcall_end'].includes(update?.type)) return null;
  const block = (update.partial ?? event.message)?.content?.[update.contentIndex];
  if (block?.type !== 'toolCall' || block.name !== 'genui' || typeof block.id !== 'string') return null;
  if (!block.arguments || typeof block.arguments !== 'object' || Array.isArray(block.arguments)) return null;
  return {type: 'genui_preview', toolCallId: block.id, name: block.name, arguments: block.arguments};
}

// Coalesce presentation snapshots before JSON serialization and the native
// bridge. Pi still receives every delta and exclusively owns tool execution.
export function createGenuiPreviewPublisher(send, {
  intervalMs = 100,
  now = () => performance.now(),
  schedule = (callback, delay) => setTimeout(callback, delay),
  cancel = (timer) => clearTimeout(timer)
} = {}) {
  const pending = new Map();
  const lastSent = new Map();
  let timer = null;
  let disposed = false;
  function emit(id, preview) {
    pending.delete(id);
    lastSent.set(id, now());
    send(preview);
  }
  function flush(id) {
    if (disposed) return;
    if (id !== undefined) {
      if (pending.has(id)) emit(id, pending.get(id));
    } else {
      for (const [key, preview] of pending) emit(key, preview);
    }
    if (!pending.size && timer !== null) { cancel(timer); timer = null; }
  }
  return {
    accept(event) {
      if (disposed) return;
      const preview = genuiPreviewFromAgentEvent(event);
      if (!preview) return;
      const id = preview.toolCallId;
      if (event.assistantMessageEvent.type === 'toolcall_end') {
        emit(id, preview);
        lastSent.delete(id);
        if (!pending.size && timer !== null) { cancel(timer); timer = null; }
      } else if (!lastSent.has(id) || now() - lastSent.get(id) >= intervalMs) {
        emit(id, preview);
      } else {
        pending.set(id, preview);
        if (timer === null) timer = schedule(() => { timer = null; flush(); }, Math.max(0, intervalMs - (now() - lastSent.get(id))));
      }
    },
    flush,
    dispose() {
      disposed = true;
      if (timer !== null) cancel(timer);
      timer = null;
      pending.clear();
      lastSent.clear();
    }
  };
}
