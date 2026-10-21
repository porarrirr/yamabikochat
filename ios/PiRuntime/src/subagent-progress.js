const OUTPUT_LIMIT = 96 * 1024;
const LOG_LIMIT = 80;
const clipped = (value, limit) => {
  const bytes = Buffer.from(String(value ?? ""), "utf8");
  if (bytes.length <= limit) return bytes.toString("utf8");
  let start = bytes.length - limit;
  // Start on a code point, so a long Japanese/emoji output remains valid JSON
  // for Foundation's strict UTF-8 decoder on the native bridge.
  while ((bytes[start] & 0xc0) === 0x80) start++;
  return bytes.subarray(start).toString("utf8");
};

// These are user-facing execution records, separate from bounded diagnostic events.
// Snapshots make duplicate/coalesced updates idempotent on the native side.
export function createSubagentProgress({ id, agent, task, model, thinkingLevel, publish, now = Date.now }) {
  const state = {
    id, agent, task, provider: model.provider, model: model.id,
    effort: thinkingLevel || "off", status: "running", activity: "応答を待っています",
    startedAtMs: now(), updatedAtMs: now(), finishedAtMs: null,
    output: "", outputTruncated: false, events: [], eventsTruncated: false, usage: null, error: null
  };
  let timer;
  let disposed = false;
  const emit = () => { clearTimeout(timer); timer = undefined; if (!disposed) publish(structuredClone(state)); };
  const log = (kind, title, detail = "") => {
    state.events.push({ id: crypto.randomUUID(), kind, title, detail: clipped(detail, 4096), createdAtMs: now() });
    if (state.events.length > LOG_LIMIT) { state.events.shift(); state.eventsTruncated = true; }
  };
  log("started", "子セッションを開始");
  emit();
  return {
    state,
    task(text) { state.task = text; emit(); },
    accept(event) {
      if (state.status !== "running") return;
      state.updatedAtMs = now();
      if (event.type === "message_update") {
        const update = event.assistantMessageEvent;
        if (update?.type === "text_delta") {
          state.activity = "回答を作成中";
          const output = event.message?.provider === "apple-pcc"
            ? event.message.content?.filter(part => part.type === "text").map(part => part.text).join("\n") ?? ""
            : state.output + update.delta;
          state.outputTruncated ||= Buffer.byteLength(output, "utf8") > OUTPUT_LIMIT;
          state.output = clipped(output, OUTPUT_LIMIT);
        } else if (update?.type === "thinking_delta" || update?.type === "thinking_start") {
          state.activity = "思考中";
        } else return;
      } else if (event.type === "tool_execution_start") {
        state.activity = `${event.toolName} を実行中`;
        log("tool_start", event.toolName, JSON.stringify(event.args ?? {}));
      } else if (event.type === "tool_execution_end") {
        state.activity = event.isError ? `${event.toolName} が失敗` : `${event.toolName} が完了`;
        log(event.isError ? "tool_error" : "tool_end", state.activity,
          event.result?.content?.filter(p => p.type === "text").map(p => p.text).join("\n"));
      } else if (event.type === "message_end" && event.message?.role === "assistant") {
        log("answer", "応答", event.message.content?.filter(p => p.type === "text").map(p => p.text).join("\n"));
      } else return;
      // Avoid re-encoding the transcript for every token; terminal state is never delayed.
      if (!timer) timer = setTimeout(emit, 120);
    },
    finish(status, { error = null, usage = null } = {}) {
      if (state.status !== "running") return;
      state.status = status;
      state.error = error;
      state.usage = usage;
      state.finishedAtMs = state.updatedAtMs = now();
      state.activity = status === "completed" ? "完了" : status === "cancelled" ? "中断" : "失敗";
      log(status, state.activity, error);
      emit();
    },
    dispose() { clearTimeout(timer); disposed = true; }
  };
}
