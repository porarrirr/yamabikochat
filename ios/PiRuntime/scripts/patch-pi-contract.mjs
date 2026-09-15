// Audited local contract extension for Pi 0.84.2. Fails closed on upstream drift.
// This is applied by npm ci (postinstall), never by editing an installed bundle.
import fs from 'node:fs';
const root = new URL('../node_modules/@earendil-works/', import.meta.url);
for (const name of ['pi-ai', 'pi-agent-core']) {
  const pkg = JSON.parse(fs.readFileSync(new URL(`${name}/package.json`, root)));
  if (pkg.version !== '0.84.2') throw new Error(`Review PCC contract patch for ${name} ${pkg.version}`);
}
function patch(path, before, after) {
  const file = new URL(path, root);
  const source = fs.readFileSync(file, 'utf8');
  if (source.includes(after)) return;
  if (source.split(before).length !== 2) throw new Error(`Pi contract drift: ${path}`);
  fs.writeFileSync(file, source.replace(before, after));
}
const types = 'pi-ai/dist/types.d.ts';
patch(types, '    errorMessage?: string;\n    rawStopReason?: string;', '    errorMessage?: string;\n    /** Typed native provider failure, preserved through the bridge. */\n    errorCode?: string;\n    rawStopReason?: string;');
const source = fs.readFileSync(new URL(types, root), 'utf8');
const usage = source.slice(source.indexOf('export interface Usage {'), source.indexOf('export type StopReason'));
if (!usage.includes('number | null')) patch(types, usage, usage.replaceAll(': number;', ': number | null;'));
patch(types, '"pending" | "stop" | "length"', '"pending" | "unknown" | "stop" | "length"');
patch(types, 'Extract<StopReason, "stop" | "length" | "toolUse" | "deferred">', 'Extract<StopReason, "unknown" | "stop" | "length" | "toolUse" | "deferred">');
patch(types, '    baseUrl: string;\n    reasoning: boolean;', '    /** null for native APIs with no wire endpoint. */\n    baseUrl: string | null;\n    reasoning: boolean;');
patch('pi-ai/dist/models.js', 'export function calculateCost(model, usage) {', `export function calculateCost(model, usage) {
    // PCC contract: unknown usage must not become zero through JS arithmetic.
    if ([usage.input, usage.output, usage.cacheRead, usage.cacheWrite].some(v => v === null)) {
        const knownFree = !model.cost.tiers?.length && [model.cost.input, model.cost.output, model.cost.cacheRead, model.cost.cacheWrite].every(v => v === 0);
        usage.cost = Object.fromEntries(["input", "output", "cacheRead", "cacheWrite", "total"].map(k => [k, knownFree ? 0 : null]));
        return usage.cost;
    }`);
patch('pi-ai/dist/utils/estimate.js', '    return usage.totalTokens || usage.input + usage.output + usage.cacheRead + usage.cacheWrite;', `    if (usage.totalTokens != null) return usage.totalTokens;
    const counts = [usage.input, usage.output, usage.cacheRead, usage.cacheWrite];
    return counts.every(v => v != null) ? counts.reduce((a, b) => a + b, 0) : NaN;`);
// Unknown termination cannot establish that tool arguments are complete.
patch('pi-agent-core/dist/agent-loop.js', 'const executedToolBatch = message.stopReason === "length"', 'const executedToolBatch = (message.stopReason === "length" || message.stopReason === "unknown")');
patch('pi-agent-core/dist/agent-loop.js', 'await failToolCallsFromTruncatedMessage(toolCalls, emit)', 'await failToolCallsFromTruncatedMessage(toolCalls, emit, message.stopReason)');
patch('pi-agent-core/dist/agent-loop.js', 'async function failToolCallsFromTruncatedMessage(toolCalls, emit) {', 'async function failToolCallsFromTruncatedMessage(toolCalls, emit, reason) {');
patch('pi-agent-core/dist/agent-loop.js', 'result: createErrorToolResult(`Tool call "${toolCall.name}" was not executed: the response hit the output token limit, so its arguments may be truncated. Re-issue the tool call with complete arguments.`),', 'result: createErrorToolResult(reason === "unknown" ? `Tool call "${toolCall.name}" was not executed: the provider did not report a termination reason, so argument completeness is unknown.` : `Tool call "${toolCall.name}" was not executed: the response hit the output token limit, so its arguments may be truncated. Re-issue the tool call with complete arguments.`),');
patch('pi-agent-core/dist/agent-loop.js', '    return { messages, terminate: false };\n}\n/**\n * Execute tool calls', '    return { messages, terminate: reason === "unknown" };\n}\n/**\n * Execute tool calls');
