import { dirname } from "node:path";

// Pi 1.0 removed the public formatSkillInvocation helper. The user authorized
// this prompt-formatting-only compatibility exception on 2026-10-04.
// Matches Pi's skill block for the absolute POSIX paths used on iOS/Android:
// https://github.com/earendil-works/pi/blob/v1.0.2/packages/coding-agent/src/core/agent-session.ts
function formatSkillInvocation({ name, filePath, content }) {
  return `<skill name="${name}" location="${filePath}">\nReferences are relative to ${dirname(filePath)}.\n\n${content}\n</skill>`;
}

/**
 * Convert an explicit native skill selection into Pi's standard skill
 * invocation prompt. The native request carries the already trusted SKILL.md
 * content because the embedded Node runtime does not own skill installation.
 */
export function applyExplicitSkillInvocations(request) {
  const context = request?.skillContext;
  const names = context?.explicitlyRequestedNames || [];
  if (!names.length) return request;

  const instructions = context.explicitInstructions || [];
  const filePaths = context.skillFilePaths || [];
  const messageIndices = context.explicitMessageIndices || [];
  if (instructions.length !== names.length
      || filePaths.length !== names.length
      || messageIndices.length !== names.length) {
    throw new Error("Pi skill invocation context is incomplete");
  }

  const messages = [...(request.messages || [])];
  const promptsByMessage = new Map();
  names.forEach((name, index) => {
    const messageIndex = messageIndices[index];
    const message = messages[messageIndex];
    if (!Number.isInteger(messageIndex) || message?.role !== "user") {
      throw new Error("Pi skill invocation references an invalid user message");
    }
    const prompt = formatSkillInvocation({
      name,
      content: instructions[index],
      filePath: filePaths[index]
    });
    promptsByMessage.set(messageIndex, [...(promptsByMessage.get(messageIndex) || []), prompt]);
  });

  for (const [messageIndex, skillPrompts] of promptsByMessage) {
    messages[messageIndex] = {
      ...messages[messageIndex],
      content: [...skillPrompts, messages[messageIndex].content || ""].join("\n\n")
    };
  }
  return { ...request, messages };
}
