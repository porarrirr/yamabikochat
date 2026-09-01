import { formatSkillInvocation } from "@earendil-works/pi-agent-core";

/**
 * Convert an explicit native skill selection into Pi Agent Core's built-in skill
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

  const catalog = new Map((context.catalog || []).map((entry) => [entry.name, entry]));
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
      description: catalog.get(name)?.description || "Explicitly selected skill",
      content: instructions[index],
      filePath: filePaths[index],
      disableModelInvocation: false
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
