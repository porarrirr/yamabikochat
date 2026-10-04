# Pi Agent runtime

YamabikoChat bundles `@earendil-works/pi-agent-core`, `pi-ai` 1.0.2, and the audited
`pi-grok` 0.10.1 commit `8b304e65c088f84ccb932959d97739245fe47d97`. They run on NodeMobile
24.18.0-0 (Pi requires Node.js >=22.19.0). TypeBox is pinned to 1.3.27, matching
Pi's schema dependency so the bundle uses one schema implementation. `src/main.js`
is the only JavaScript entry point and exposes an authenticated loopback NDJSON
bridge used by `PiAgentRuntime.swift`.

Android uses the same bundle through `PiAgentRuntime.kt` and NodeMobile 24.18.0-0.
Its JNA 5.19.1 Android AAR provides the native dispatcher, including 16 KB page-size
support. The APK also ships the official NDK r27 `libc++_shared.so` dependency,
restored from a pinned Google source revision with per-ABI SHA-256 checks.
APK ABIs are restricted to the three supplied NodeMobile architectures.
The JNA binding calls Android's exported `node::Start(int, char**)` symbol from
the pinned NodeMobile headers; the iOS-only `node_start` wrapper is not assumed.
The network security configuration allows HTTP only for Pi's `127.0.0.1` bridge;
remote requests retain the existing HTTPS requirement. JNA and `NodeLibrary` are
preserved in both release and diagnostic R8 configurations.
Android startup is process-owned and completes even if the first caller is
cancelled, so another model lookup cannot start Node a second time.

Run `../../scripts/bootstrap-pi-runtime-android.sh` to restore Android binaries and
rebuild from the shared lockfile. `./gradlew :app:connectedDebugAndroidTest` from
the repository root verifies native startup, bundled script extraction, built-in
protocol resolution and all OpenCode Go routes without provider requests.
Repeat with `-PyamabikoTestBuildType=diagnostic :app:connectedDiagnosticAndroidTest`
to exercise the same bridge in an R8-minified APK. The diagnostic profile retains
runtime dependencies and public APIs used by the separate instrumentation APK;
R8 can still optimize the bridge implementations and private application code.

`pi-coding-agent` is pinned to 1.0.2 as a build dependency to satisfy `pi-grok`'s
peer dependency without installing a second, older Pi dependency tree. The CLI
is not imported into the mobile bundle. `pi-grok` remains at its audited commit.

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

Codex login and refresh use Pi's built-in `openai-codex` OAuth provider. SuperGrok login,
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
time; the app never downloads or executes JavaScript after distribution.
