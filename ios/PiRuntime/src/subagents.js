import { mobileAgentDir } from "./subagent-environment.js";
import fs from "node:fs";
import path from "node:path";
import { AsyncLocalStorage } from "node:async_hooks";
import { Agent } from "@earendil-works/pi-agent-core";
import { getSupportedThinkingLevels } from "@earendil-works/pi-ai";
import { AgentSession, DefaultResourceLoader, SessionManager, SettingsManager, convertToLlm, initTheme } from "@earendil-works/pi-coding-agent";
import registerSubagents from "pi-subagents";
import { registerAgent } from "pi-subagents/agents";
// Pinned integration seam: upstream exposes this factory internally, not in its
// package exports. Only the mobile host changes; Pi owns sessions and execution.
import { setChildSessionFactory } from "../node_modules/pi-subagents/src/runs/shared/child-session.js";
import { createSubagentProgress } from "./subagent-progress.js";
import { aggregateUsage } from "./usage-contract.js";

const owners = new AsyncLocalStorage();
const EFFORTS = new Set(["off", "minimal", "low", "medium", "high", "xhigh", "max"]);
const failure = (code, message = code) => Object.assign(new Error(message), { code });
const identity = model => `${model.provider}/${model.id}`;
const errorResult = error => ({ content: [{ type: "text", text: `${error.code || "subagent_error"}: ${error.message}` }], details: { error: error.code || "subagent_error" }, isError: true });

export function selectSubagentModel(reference, entries, parent, defaultID) {
  let value = reference || defaultID || identity(parent.model);
  let effort;
  const colon = value.lastIndexOf(":");
  if (colon >= 0 && EFFORTS.has(value.slice(colon + 1))) {
    effort = value.slice(colon + 1);
    value = value.slice(0, colon);
  }
  const matches = value === "inherit" ? [parent] : entries.filter(entry =>
    entry.id === value || entry.name === value || identity(entry.model) === value || entry.model.id === value);
  const exact = entries.find(entry => entry.id === value) || entries.find(entry => identity(entry.model) === value);
  const entry = exact || (matches.length === 1 ? matches[0] : undefined);
  if (!entry) throw failure("subagent_model_unavailable", `Subagent model is not configured or is ambiguous: ${value}. Choose a configured model profile or inherit.`);
  const thinkingLevel = effort ?? entry.config.thinkingLevel ?? "off";
  if (!getSupportedThinkingLevels(entry.model).includes(thinkingLevel)) {
    throw failure("subagent_effort_unsupported", `${identity(entry.model)} does not support ${thinkingLevel}`);
  }
  return { ...entry, config: { ...entry.config, thinkingLevel } };
}

// Scoped to one parent. No filesystem credential store, global env mutation,
// protocol inference, retry, provider substitution, or synthetic model metadata.
export function mobileModelRuntime(entries, streams, getAuth, getProvider) {
  const models = [...new Map(entries.map(entry => [identity(entry.model), entry.model])).values()];
  const requireEntry = model => {
    const entry = entries.find(entry => identity(entry.model) === identity(model));
    if (!entry) throw failure("subagent_model_unavailable", `Unregistered child model: ${identity(model)}`);
    return entry;
  };
  return {
    getModels: provider => models.filter(model => !provider || model.provider === provider),
    getAllModels: provider => models.filter(model => !provider || model.provider === provider),
    getModel: (provider, id) => models.find(model => model.provider === provider && model.id === id),
    getPhysicalModel: (provider, id) => models.find(model => model.provider === provider && model.id === id),
    getAvailableSnapshot: () => models,
    getAvailable: async () => models,
    getError: () => undefined,
    hasConfiguredAuth: provider => models.some(model => model.provider === provider),
    checkAuth: async provider => models.some(model => model.provider === provider) ? { status: "configured" } : undefined,
    isUsingOAuth: () => false,
    isUsingSubscription: () => false,
    getAuth: async (model, options) => {
      const selected = typeof model === "string" ? models.find(item => item.provider === model) : model;
      if (!selected) return undefined;
      return getAuth(requireEntry(selected), options);
    },
    getProvider,
    getProviders: () => [...new Set(models.map(model => model.provider))].map(getProvider),
    getRegisteredProviderIds: () => [...new Set(models.map(model => model.provider))],
    getRegisteredNativeProvider: getProvider,
    getRegisteredProviderConfig: () => undefined,
    getCompatibilityRequestConfig: () => ({ headers: {} }),
    refresh: async () => ({ errors: [] }),
    streamSimple: (model, context, options) => streams(requireEntry(model))(model, context, options),
    completeSimple: async (model, context, options) => streams(requireEntry(model))(model, context, options).result(),
    resolveModel: async model => ({ model: requireEntry(model).model })
  };
}

async function sessionHost({ agent, modelRuntime, cwd, systemPrompt, tools, hooks = [], sessionManager, allowExtensionTools = true }) {
  const settingsManager = SettingsManager.inMemory({
    compaction: { enabled: false }, retry: { enabled: false, provider: { maxRetries: 0 } },
    images: { autoResize: false }, cacheWarming: "off"
  });
  const resourceLoader = new DefaultResourceLoader({
    cwd, agentDir: mobileAgentDir, settingsManager,
    noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true,
    systemPrompt, extensionFactories: hooks
  });
  await resourceLoader.reload();
  const errors = resourceLoader.getExtensions().errors;
  if (errors.length) throw failure("subagent_extension_load_failed", errors.map(error => error.error).join("; "));
  const session = new AgentSession({
    agent, modelRuntime, cwd, settingsManager, resourceLoader, sessionManager,
    baseToolsOverride: Object.fromEntries(tools.map(tool => [tool.name, tool])),
    initialActiveToolNames: tools.map(tool => tool.name),
    ...(allowExtensionTools ? {} : { allowedToolNames: [] })
  });
  const startupErrors = [];
  try {
    await session.bindExtensions({ mode: "print", onError: error => startupErrors.push(error.error) });
    if (startupErrors.length) throw failure("subagent_extension_start_failed", startupErrors.join("; "));
  } catch (error) {
    try { await closeSession(session); } catch { session.dispose(); }
    throw error;
  }
  return session;
}

async function closeSession(session) {
  try { await session.extensionRunner.emit({ type: "session_shutdown", reason: "quit" }); }
  finally { session.dispose(); }
}

// AsyncLocalStorage keeps simultaneous conversations and nested tool promises
// attached to their own credentials, stream bridge and cancellation lifetime.
setChildSessionFactory({
  async create(launch) {
    const owner = owners.getStore();
    if (!owner || owner.lifecycle.closed) throw failure("subagent_host_unavailable");
    if (launch.machine || launch.extensionPaths.length || launch.requiredExtensions?.length || launch.builtinMcpTools?.length) {
      throw failure("subagent_mobile_feature_unsupported", "Remote machines and desktop extensions are unavailable in the iOS host");
    }
    if (launch.runtime.depth > 1) throw failure("subagent_depth_exceeded");
    const profileAgent = owner.entries.find(item => `mobile-${item.id.toLowerCase().replace(/[^a-z0-9-]/g, "")}` === launch.runtime.agent);
    const preferred = owner.selectedEntry || profileAgent || owner.defaultEntry || owner.parent;
    const entry = selectSubagentModel(launch.model || identity(preferred.model), [preferred], preferred);
    const id = crypto.randomUUID();
    const progress = createSubagentProgress({
      id, agent: owner.entries.find(item => `mobile-${item.id.toLowerCase().replace(/[^a-z0-9-]/g, "")}` === launch.runtime.agent)?.name
        || `${launch.runtime.agent || "delegate"} ${owner.progress.size + 1}`, task: "", model: entry.model,
      thinkingLevel: entry.config.thinkingLevel, publish: owner.publish
    });
    owner.progress.set(id, progress);
    const requested = new Set(launch.tools ?? owner.tools.map(tool => tool.name));
    const tools = owner.makeChildTools(id).filter(tool => requested.has(tool.name) && !launch.excludeTools?.includes(tool.name));
    if (entry.toolCall === false && tools.length) {
      progress.finish("failed", { error: "subagent_tools_unsupported: The selected model does not support the tools required by this role" });
      throw failure("subagent_tools_unsupported");
    }
    const manager = launch.storage.kind === "file" ? SessionManager.open(launch.storage.sessionFile, undefined, owner.cwd)
      : launch.storage.kind === "dir" ? SessionManager.create(owner.cwd, launch.storage.sessionDir)
      : SessionManager.inMemory(owner.cwd);
    const agent = new Agent({
      initialState: { model: entry.model, thinkingLevel: entry.config.thinkingLevel || "off", systemPrompt: launch.systemPrompt || "", tools, messages: manager.buildSessionContext().messages },
      convertToLlm,
      streamFn: owner.streams(entry, id),
      toolExecution: "parallel",
      ...(owner.finishTurn(entry.config) ? { finishTurn: owner.finishTurn(entry.config) } : {})
    });
    let session;
    try {
      const childRuntime = mobileModelRuntime([entry, ...owner.entries.filter(item => identity(item.model) !== identity(entry.model))], owner.streams, owner.getAuth, owner.getProvider);
      session = await sessionHost({ agent, modelRuntime: childRuntime, cwd: owner.cwd,
        systemPrompt: [launch.systemPrompt, launch.appendSystemPrompt].filter(Boolean).join("\n\n"),
        tools, hooks: launch.hooks, sessionManager: manager, allowExtensionTools: entry.toolCall !== false });
    } catch (error) {
      progress.finish("failed", { error: error.message });
      throw error;
    }
    session.subscribe(event => progress.accept(event));
    let aborted = false;
    let disposed = false;
    const child = {
      subscribe: listener => session.subscribe(listener),
      async prompt(task) {
        progress.task(task);
        try {
          await session.prompt(task, { expandPromptTemplates: false });
          const last = session.messages.filter(message => message.role === "assistant").at(-1);
          if (last?.errorMessage || last?.stopReason === "error" || last?.stopReason === "aborted") {
            throw new Error(last.errorMessage || last.stopReason);
          }
          progress.finish(aborted ? "cancelled" : "completed", { usage: aggregateUsage(session.messages.filter(message => message.role === "assistant")) });
        } catch (error) {
          progress.finish(aborted || launch.signal?.aborted ? "cancelled" : "failed", { error: error.message });
          throw error;
        }
      },
      steer: text => session.steer(text), followUp: text => session.followUp(text),
      async abort() { aborted = true; await session.abort(); progress.finish("cancelled"); },
      async dispose() {
        if (disposed) return;
        disposed = true;
        if (progress.state.status === "running") progress.finish(aborted ? "cancelled" : "failed", { error: "Child session closed before completion" });
        await closeSession(session);
        owner.children.delete(child);
      },
      hasQueuedMessages: () => session.hasQueuedMessages(),
      get messages() { return session.messages; },
      get sessionFile() { return session.sessionFile; },
      get sessionId() { return session.sessionId; },
      get modelId() { return identity(entry.model); },
      get contextWindow() { return entry.model.contextWindow; }
    };
    owner.children.add(child);
    if (launch.signal?.aborted || owner.lifecycle.closed) { await child.abort(); await child.dispose(); throw failure("subagent_cancelled"); }
    return child;
  },
  async dispose() {
    const owner = owners.getStore();
    if (!owner) return;
    await Promise.allSettled([...owner.children].map(async child => { await child.abort(); await child.dispose(); }));
  }
});

export async function createMobileSubagentsHost({ agent, config, resolve, streams, getAuth, getProvider, tools, makeChildTools = () => tools, publish, report, finishTurn = () => undefined }) {
  const parentSystemPrompt = agent.state.systemPrompt;
  const parent = { id: "inherit", name: "親と同じ", config, model: agent.state.model, toolCall: true };
  const entries = [parent];
  const unavailable = [];
  for (const profile of config.subagents.models || []) {
    try {
      if (profile.unsupportedReason) throw failure("subagent_profile_unavailable", profile.unsupportedReason);
      const resolved = await resolve(profile.configuration);
      if (!getSupportedThinkingLevels(resolved.model).includes(resolved.config.thinkingLevel || "off")) throw failure("subagent_effort_unsupported");
      if (entries.some(entry => identity(entry.model) === identity(resolved.model) && JSON.stringify(entry.model) !== JSON.stringify(resolved.model))) {
        throw failure("subagent_model_identity_conflict", "The same Pi identity has different model-level contracts");
      }
      entries.push({ id: profile.id, name: profile.name, config: resolved.config, model: resolved.model, toolCall: resolved.toolCall });
    } catch (error) {
      unavailable.push({ ...profile, reason: profile.unsupportedReason || error.code || error.message });
      report("subagent_model_unsupported", "Subagent profile is unavailable", { id: profile.id, reason: error.code || error.message });
    }
  }
  const cwd = fs.mkdtempSync(path.join(mobileAgentDir, "session-"));
  fs.mkdirSync(path.join(cwd, ".pi"));
  // Official agent overrides give desktop roles the native mobile tool loadout.
  const defaultEntry = entries.find(entry => entry.id === config.subagents.defaultModelID) || parent;
  const agentOverrides = Object.fromEntries(["scout", "researcher", "evidence-auditor", "worker", "reviewer", "oracle", "delegate"].map(name => [name, {
    tools: defaultEntry.toolCall === false ? [] : tools.map(tool => tool.name), model: identity(defaultEntry.model), thinking: defaultEntry.config.thinkingLevel || "off"
  }]));
  fs.writeFileSync(path.join(cwd, ".pi", "settings.json"), JSON.stringify({ subagents: { agentOverrides } }));
  const owner = {
    parent, entries, defaultEntry, cwd, tools, children: new Set(), progress: new Map(), lifecycle: { closed: false },
    streams, publish, finishTurn, makeChildTools, getAuth, getProvider,
    modelRuntime: mobileModelRuntime(entries, streams, getAuth, getProvider)
  };
  const manager = SessionManager.inMemory(cwd);
  manager.appendModelChange(parent.model.provider, parent.model.id);
  manager.appendThinkingLevelChange(config.thinkingLevel || "off");
  const messages = agent.state.messages;
  const last = messages.at(-1);
  if (last?.role !== "user") throw failure("subagent_parent_input_unsupported", "The mobile extension host requires a user turn");
  for (const message of messages.slice(0, -1)) manager.appendMessage(message);
  agent.state.messages = messages.slice(0, -1);
  let session;
  const registrations = [];
  try {
    initTheme("dark");
    session = await owners.run(owner, () => sessionHost({ agent, modelRuntime: owner.modelRuntime, cwd,
      systemPrompt: agent.state.systemPrompt, tools, sessionManager: manager,
      hooks: [pi => {
        const mobileAPI = new Proxy(pi, { get(target, key) {
          if (key !== "registerTool") { const value = Reflect.get(target, key); return typeof value === "function" ? value.bind(target) : value; }
          return definition => {
            if (definition.name !== "subagent") return target.registerTool(definition);
            target.registerTool({ ...definition,
              description: definition.description + "\nOn iOS execution is in-process (async:false). Use only the provided mobile tools; shell, desktop extensions and worktrees are unavailable. "
                + "No model specified means the parent model, unless the user selected a default profile. Configured model profiles: "
                + entries.map(entry => `${entry.id} (${entry.name}): ${identity(entry.model)}:${entry.config.thinkingLevel || "off"}`).join(", ")
                + unavailable.map(profile => `; unavailable ${profile.id}: ${profile.reason}`).join(""),
              execute: async (callID, params, signal, onUpdate, ctx) => {
                try {
                  if (params.async === true || params.options?.async === true || params.worktree || params.cwd || params.workflow
                    || params.options?.machine || params.options?.extensions || params.options?.worktree || params.options?.cwd) {
                    throw failure("subagent_mobile_feature_unsupported", "iOS supports in-process children only (async:false), without desktop processes, worktrees, custom directories or extensions");
                  }
                  if (params.action && !["list", "status", "guide"].includes(params.action)) throw failure("subagent_mobile_action_unsupported", params.action);
                  const agents = params.agent ? [params.agent] : (params.tasks || params.chain?.flatMap(step => step.parallel || [step]) || []).map(task => task.agent);
                  const hasProfileAgent = agents.length > 0 && agents.every(agent => agent?.startsWith("mobile-"));
                  const requestedID = params.model || (!hasProfileAgent && !params.action ? config.subagents.defaultModelID : undefined);
                  const unavailableProfile = unavailable.find(profile => profile.id === requestedID);
                  if (unavailableProfile) throw failure("subagent_model_unsupported", unavailableProfile.reason);
                  if (requestedID && !params.model && !entries.some(entry => entry.id === requestedID)) throw failure("subagent_default_model_unavailable", requestedID);
                  const selected = params.model ? selectSubagentModel(params.model, entries, parent) : undefined;
                  return await owners.run({ ...owner, selectedEntry: selected }, () => definition.execute(callID, {
                    ...params, async: false, ...(selected ? { model: `${identity(selected.model)}:${selected.config.thinkingLevel || "off"}` } : {}),
                    // Keep all upstream session artifacts inside this parent's disposable workspace.
                    options: { ...params.options, sessionDir: path.join(cwd, "children"), artifacts: false, share: false }
                  }, signal, onUpdate, ctx));
                } catch (error) { return errorResult(error); }
              }
            });
          };
        } });
        registerSubagents(mobileAPI);
        // Public pi-subagents registration lets parallel tasks choose different
        // provider/model/effort profiles using their agent name.
        for (const entry of entries.slice(1)) registrations.push(registerAgent({ pi: mobileAPI,
          name: `mobile-${entry.id.toLowerCase().replace(/[^a-z0-9-]/g, "")}`,
          definition: { description: `${entry.name}: ${identity(entry.model)} (${entry.config.thinkingLevel || "off"})`,
            systemPrompt: "Complete the assigned task using the available iOS tools. Return your findings and concrete results to the parent agent.",
            tools: entry.toolCall === false ? [] : tools.map(tool => tool.name), model: identity(entry.model), thinking: entry.config.thinkingLevel || "off",
            defaultContext: "fresh", defaultAsync: false, allowNestedSubagents: false }
        }));
        // An empty mobile system prompt must stay empty: SDK's default prefix
        // otherwise turns an ordinary chat into a desktop coding assistant.
        // Keep only the original prompt and the extension's declared sections.
        pi.on("before_agent_start", event => {
          event.systemPromptOptions.forceSystemPrompt = [
            parentSystemPrompt, event.systemPromptOptions.appendSystemPrompt,
            ...Object.entries(event.systemPromptOptions.sections).filter(([, text]) => text)
              .map(([name, text]) => `<${name}>\n${text}\n</${name}>`)
          ].filter(Boolean).join("\n\n");
        });
      }]
    }));
  } catch (error) {
    registrations.forEach(registration => registration.dispose());
    fs.rmSync(cwd, { recursive: true, force: true });
    throw error;
  }
  return {
    async run() {
      const content = Array.isArray(last.content) ? last.content : [{ type: "text", text: last.content }];
      await owners.run(owner, () => session.prompt(content.filter(part => part.type === "text").map(part => part.text).join("\n"), {
        images: content.filter(part => part.type === "image"), expandPromptTemplates: false
      }));
    },
    snapshots: () => [...owner.progress.values()].map(progress => structuredClone(progress.state)),
    async dispose() {
      owner.lifecycle.closed = true;
      try { await owners.run(owner, () => closeSession(session)); }
      finally {
        registrations.forEach(registration => registration.dispose());
        owner.progress.forEach(progress => progress.dispose());
        fs.rmSync(cwd, { recursive: true, force: true });
      }
    }
  };
}
