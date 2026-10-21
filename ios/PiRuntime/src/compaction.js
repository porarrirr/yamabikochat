import { generateSummaryWithUsage, convertToLlm } from "@earendil-works/pi-coding-agent";
import { estimateContextTokens } from "../node_modules/@earendil-works/pi-coding-agent/dist/core/compaction/compaction.js";
import { providerUsage } from "./usage-contract.js";

// Pi owns the summary prompt, validation, conversion, and context estimation.
// There is no alternate provider/endpoint/model retry for a failed compaction.
export async function compactContext({ messages, model, config, streamFn, signal }) {
  if (!messages.length) throw new Error("There is no conversation to compact");
  const checkedStream = async (...args) => {
    const stream = await streamFn(...args);
    return { result: async () => {
      const message = await stream.result();
      if (message.stopReason !== "stop") {
        throw new Error(message.errorMessage || `Pi compaction did not finish: ${message.stopReason}`);
      }
      return message;
    } };
  };
  const { text, usage } = await generateSummaryWithUsage(
    messages, model, Math.min(16384, model.contextWindow), config.apiKey,
    undefined, signal, undefined, undefined, config.thinkingLevel, checkedStream,
    config.env, { enabled: false, maxRetries: 0, baseDelayMs: 0 }
  );
  signal?.throwIfAborted();
  const compacted = convertToLlm([{
    role: "compactionSummary", summary: text,
    tokensBefore: estimateContextTokens(messages).tokens, timestamp: Date.now()
  }]);
  return {
    text,
    usage: {
      ...providerUsage(usage),
      contextTokens: estimateContextTokens(compacted).tokens,
      contextWindow: model.contextWindow
    },
    providerTranscript: compacted.map(message => ({
      role: "user",
      content: message.content.filter(part => part.type === "text").map(part => part.text).join("\n"),
      attachments: []
    }))
  };
}
