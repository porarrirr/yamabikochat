# iOS pi-subagents host

`pi-subagents` is pinned to 0.79.2. The iOS host adapter was explicitly approved
by the user on 2026-10-21 following the repository's Pi execution-path restriction.
The approval covers the host connection: child session creation, existing model
resolution/authentication, native tools, and progress events. It does not authorize
an alternative inference implementation or provider/protocol fallback.

## Execution

The parent keeps its existing Pi `Agent`, resolver, stream function, provider
contracts, credentials, and lifecycle. When subagents are enabled for an ordinary
chat request, a Pi `AgentSession` hosts the actual pi-subagents extension around
that agent. Pi-subagents owns the `subagent` tool, role discovery, structured
parallel/chain workflows and child dispatch. Its workflow worker is unchanged.
The original mobile system prompt (including an empty/disabled prompt) is kept;
the SDK's default desktop coding persona is not substituted. The extension's
declared subagent sections are appended through Pi's system-prompt API.

The pinned internal `setChildSessionFactory` seam installs an iOS host factory.
Each child is a separate Pi `Agent`/`AgentSession`; inference uses the existing
`resolveModel` and `standardStreamFunction`. The factory exposes only the parent's
allowed native tools, with child-specific bridge identities. Child tools and
transcripts do not enter the parent's tool history. AsyncLocalStorage scopes
credentials, selected profiles and cleanup to the invoking parent; completing
one conversation cannot cancel another conversation's children.

The bridge passes explicit user configuration to Pi, without synthesizing models
or selecting a protocol in Swift. Model-level metadata is preserved. Different
contracts for the same Pi identity are rejected as `subagent_model_identity_conflict`.
There is no retry through another provider, model, endpoint or protocol.

## Model settings

Settings → 会話 → サブエージェント contains the enable toggle, optional default
profile, and named provider/model/effort combinations. Settings use the existing
`extraJSON` container without changing existing provider settings or DB columns.
Credentials are resolved from the existing Keychain/auth repositories per request;
they are never written to Pi's filesystem credential store.

No selected default and no launch override means the exact parent model and
effort. An explicit launch model wins over the configured default. Named profiles
are also registered using the public `pi-subagents/agents` API so different lanes
of a parallel request can select different profiles. Unsupported saved profiles
stay visible with the resolver reason and are never replaced with another model.
The effort picker uses Pi's `getSupportedThinkingLevels`, and execution rejects
unsupported levels rather than allowing SDK clamping to change them.

The native Apple Intelligence/PCC tool bridge does not execute Pi extension tools;
subagents are disabled on that parent path and Apple profiles report
`subagent_native_apple_bridge_unsupported`. Desktop CLI runners, external machines,
worktrees, detached processes, schedules, workflow scripts and nested subagents
are unavailable in this mobile host. Calls requesting unsupported execution return
a typed reason. In-process children use fresh task context by default. The parent
must include the relevant information in the delegated task.

## Progress and presentation

`subagent_update` sends bounded, cumulative child snapshots over the existing
authenticated NDJSON bridge. They contain task, resolved provider/model/effort,
current action, output, tool arguments/results, timestamps and Pi-reported usage.
Raw thinking text is not used as an execution log. Output retains its last 96 KiB;
the latest 80 log entries retain at most 4096 characters each. The detail UI labels
these limits. Terminal snapshots are immediate; token updates are coalesced.

Swift stores these records in the existing tool-activity `stepsJSON` for messages,
variants and dual replies. Child artifacts stay with the child detail. Partial
state is checkpointed during execution; cold launch marks unfinished records
interrupted while keeping their output. Secret conversations continue using the
existing repository's no-durable-tool-activity path.

The chat shows one collapsed, two-line fleet summary regardless of child count.
Expansion shows at most three rows and a route to the full list. Each child opens
a large detail sheet with the assignment, model, current activity, output, tool
history and artifacts. Selection by child ID keeps an open detail live as snapshots
arrive. No percentage is invented for work whose total is unknown.

## Packaging and verification

`scripts/build.mjs` bundles the extension and SDK and preserves package-relative
data URLs. `PiAssets` includes built-in agent definitions, guides, manifests, SDK
theme data, and the exact Acorn dependency required by the upstream workflow worker.
XcodeGen copies that folder alongside `main.js`; bootstrap caching checks both.
No package installation, CLI process or code download occurs on the device.
The host sets Pi's `PI_OFFLINE` flag to disable global npm/skill-package discovery;
provider inference still uses the normal network path. The version-checked
`patch-pi-contract.mjs` patch makes Git watchdog baselines unavailable in the mobile
host before any subprocess or rejected promise is created. Desktop behavior outside
the mobile host is unchanged. Integration tests deny subprocess spawning with
`EPERM` and assert that parent/child sessions never attempt it.


Required checks when changing this integration or upgrading the plugin:

- `npm run build --prefix ios/PiRuntime && npm test --prefix ios/PiRuntime`.
- `npm run check:contracts --prefix ios/PiRuntime` for provider contract fidelity.
- `SubagentNativeRuntimeTests` exercises the actual shipped bundle on NodeMobile,
  against a local HTTP fixture, including three plugin-managed child sessions.
- JS integration tests copy the entire bundle to an isolated directory, exercise
  all five custom protocols, named profiles, inherited/default models, native tool
  calls, concurrent parents and provider failures without fallback.
- `SubagentTests` covers settings, persistence, terminal ordering, scoped artifacts,
  interrupted execution and gateway credentials.
- `SubagentUITests` checks the compact three-child footprint, details, action logs,
  live updates, and provider/model/effort settings on iPhone.
