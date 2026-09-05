# Pi Agent runtime

YamabikoChat bundles `@earendil-works/pi-agent-core`, `pi-ai` 0.84.2, and the audited
`pi-grok` 0.10.1 commit `8b304e65c088f84ccb932959d97739245fe47d97`. They run on NodeMobile
24.18.0-0. `src/main.js` is the only JavaScript entry point and exposes an authenticated
loopback NDJSON bridge used by `PiAgentRuntime.swift`.

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
