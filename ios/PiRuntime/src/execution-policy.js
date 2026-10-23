// Host permissions apply before any extension, child credential, or local tool is used.
export function enforceExecutionPolicy(request, config) {
  const policy = request.executionPolicy;
  if (policy !== undefined && policy !== null && (
    typeof policy !== "object" || typeof policy.allowsClientTools !== "boolean" ||
    typeof policy.allowsSubagents !== "boolean"
  )) throw Object.assign(new Error("Invalid execution policy"), { code: "execution_policy_invalid" });
  const toolsAllowed = policy?.allowsClientTools !== false && request.metadata?.supportsClientTools !== "false";
  const subagentsAllowed = toolsAllowed && policy?.allowsSubagents !== false && request.metadata?.subagentsEnabled !== "false";
  return {
    request: toolsAllowed ? request : { ...request, tools: [], skillContext: null },
    config: subagentsAllowed ? config : { ...config, subagents: undefined }
  };
}
