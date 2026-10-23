# Pi Agent runtime

YamabikoChat bundles `@earendil-works/pi-agent-core`, `pi-ai` 1.0.2, and the audited
`pi-grok` 0.10.1 commit `8b304e65c088f84ccb932959d97739245fe47d97`. They run on NodeMobile
24.18.0-0 (Pi requires Node.js >=22.19.0). TypeBox is pinned to 1.3.27, matching
Pi's schema dependency so the bundle uses one schema implementation. `src/main.js`
is the only JavaScript entry point and exposes an authenticated loopback NDJSON
bridge used by `PiAgentRuntime.swift`.

`pi-coding-agent` is pinned to 1.0.2 as a runtime dependency. Its `AgentSession`
and extension APIs host `pi-subagents` 0.79.2 in-process. The CLI is never launched.
`pi-grok` remains at its audited commit. See [SUBAGENTS.md](SUBAGENTS.md) for the
user-approved mobile host integration and its validation boundary.

Pi 1.0 removed `formatSkillInvocation` from Agent Core. The user authorized a
prompt-formatting-only compatibility exception on 2026-10-04. `src/skill-context.js`
preserves Pi's skill blocks and relative-reference directory for native skill
selections; inference, tools, usage and context estimation still use Pi.

OpenCode Go routes follow the official contract checked by `check:contracts`.
The default for a new selection is GLM-5.3. Saved retired model IDs are preserved
and resolve as unsupported. Kimi K2.6 remains listed because its official route
exists, but Pi 1.0.2 lacks its model metadata. Resolution returns `pi_model_missing`
when no catalog contract is supplied, or `catalog_contract_incomplete` for an
incomplete contract, instead of preventing the entire runtime from starting.

On iOS, `PiNodeRunner` sends lifecycle commands through anonymous pipes. The bridge
closes its TCP listener before suspension and opens the same port on foreground entry;
the Node engine and Pi agent state are never restarted. Accepted requests can finish
within an acknowledged UIKit background task so tool-result requests remain usable.
At expiration the listener closes even if a request is still active. The lifecycle
pipe is separate from TCP because iOS can reclaim a suspended listening socket without
notifying Node (Apple TN2277). Lifecycle transitions are recorded in the runtime log.
`npm test` covers repeated transitions, background startup, draining and active streams.

ChatGPT login and refresh use the official SIWC provider extension described in
[CHATGPT_PLAN.md](CHATGPT_PLAN.md). SuperGrok login,
refresh, OIDC verification, proxy headers, request sanitization, and CLI proxy routing use
`pi-grok`. OAuth credentials are returned to Swift and persisted in the iOS Keychain; they
are not written to Pi's filesystem credential store.

The pinned `pi-grok` revision was reviewed before integration. It has no runtime dependencies,
install scripts, or command-execution path. Authenticated requests reject redirects, OIDC
endpoints and JWKS are restricted to HTTPS xAI origins, ID tokens are verified with ES256,
and response bodies/JSON traversal are bounded. The dependency stays commit-pinned so a new
upstream revision requires a fresh review.

Run `../scripts/bootstrap-pi-runtime.sh` after changing dependencies or the entry point.
The script installs from `package-lock.json`, rebuilds `bundle/main.js`, and downloads the
NodeMobile XCFramework when it is not already present. Runtime packages are bundled at build
time; the app never downloads JavaScript after distribution. `bundle/PiAssets`
contains the pinned package data and the Acorn parser that the upstream workflow
worker loads through `createRequire`; it must be shipped beside `main.js`.

The entire `bundle/` directory is generated and ignored by Git. Run `ios/bootstrap.sh`
from the repository root before opening a fresh checkout in Xcode. `npm test`
automatically rebuilds the bundle before running the runtime tests.

Security boundaries are documented in [SECURITY.md](SECURITY.md). Secret conversations
carry a host execution policy which disables all client tools and child agents before
Pi loads extensions; the native gateway omits child credentials. The build applies
`patch-pi-grok-security.mjs` to the pinned provider for state-checked callbacks,
body-free parse errors and RFC 7009 revocation discovered from xAI's OIDC metadata.
This uses the existing provider authentication path and never infers another endpoint.
