# Pi Agent runtime

YamabikoChat bundles `@earendil-works/pi-agent-core` and `pi-ai` 0.84.2 and runs them on
NodeMobile 24.18.0-0. `src/main.js` is the only JavaScript entry point. It exposes an
authenticated loopback NDJSON bridge used by `PiAgentRuntime.swift`.

Run `../scripts/bootstrap-pi-runtime.sh` after changing dependencies or the entry point.
The script installs from `package-lock.json`, rebuilds `bundle/main.js`, and downloads the
NodeMobile XCFramework when it is not already present. Runtime packages are bundled at build
time; the app never downloads or executes JavaScript after distribution.
