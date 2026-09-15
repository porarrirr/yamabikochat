// Explicit null means the provider did not report the value, not zero usage.
export function providerUsage(value) {
  if (!value) return null;
  return {
    inputTokens: value.input === null ? null : (value.input || 0),
    outputTokens: value.output === null ? null : (value.output || 0),
    totalTokens: value.totalTokens === null ? null : (value.totalTokens || 0),
    reasoningTokens: value.reasoning,
    cachedInputTokens: value.cacheRead === null ? null : (value.cacheRead || 0),
    cacheCreationInputTokens: value.cacheWrite === null ? null : (value.cacheWrite || 0)
  };
}
export function aggregateUsage(messages) {
  const fields = { inputTokens: 'input', outputTokens: 'output', totalTokens: 'totalTokens',
    reasoningTokens: 'reasoning', cachedInputTokens: 'cacheRead', cacheCreationInputTokens: 'cacheWrite' };
  return Object.fromEntries(Object.entries(fields).map(([target, source]) => [target,
    messages.some(m => m.usage?.[source] === null) ? null : messages.reduce((s, m) => s + (m.usage?.[source] || 0), 0)]));
}
