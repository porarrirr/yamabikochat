// Read Pi's already-parsed tool arguments; this never executes a tool or resolves a model.
export function genuiPreviewFromAgentEvent(event) {
  const update = event?.assistantMessageEvent;
  if (event?.type !== 'message_update' || !['toolcall_start', 'toolcall_delta', 'toolcall_end'].includes(update?.type)) return null;
  const block = (update.partial ?? event.message)?.content?.[update.contentIndex];
  if (block?.type !== 'toolCall' || block.name !== 'genui' || typeof block.id !== 'string') return null;
  if (!block.arguments || typeof block.arguments !== 'object' || Array.isArray(block.arguments)) return null;
  return {type: 'genui_preview', toolCallId: block.id, name: block.name, arguments: block.arguments};
}
