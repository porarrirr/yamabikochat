# Repository Guidelines

## Project Structure & Module Organization
- YamabikoChat is maintained exclusively for iOS and iPadOS. Android development has ended; its implementation remains in Git history.
- `ios/YamabikoChat/` contains the SwiftUI app, `ios/YamabikoShareExtension/` the share extension, and `ios/YamabikoTests/` the unit tests.
- `ios/PiRuntime/` contains the Pi Agents runtime and JavaScript tests; `ios/GenUIRuntimeTests/` contains DOM tests.
- `ios/project.yml` is the Xcode project source of truth. `docs/` contains the public website; `scripts/` contains upstream contract checks.

## Build, Test, and Development Commands
- `cd ios && ./bootstrap.sh`: restore dependencies, build Pi, and generate the Xcode project.
- `cd ios && xcodegen generate`: regenerate the Xcode project after structural changes.
- `cd ios && xcodebuild -project YamabikoChat.xcodeproj -scheme YamabikoChat -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' CODE_SIGNING_ALLOWED=NO test`: build and test iOS.
- `npm test --prefix ios/PiRuntime`: run Pi runtime tests.
- `npm ci --prefix ios/GenUIRuntimeTests --ignore-scripts && npm test --prefix ios/GenUIRuntimeTests`: run GenUI DOM tests.
- `npm run check:contracts --prefix ios/PiRuntime`: check upstream provider contracts.
- `python3 -m unittest ios/PythonTests/test_yamabiko_runtime.py`: run embedded Python tests.

## Coding Style & Testing Guidelines
- Swift: 4-space indentation, focused files, and small view models/repositories.
- Types use PascalCase; methods and variables use camelCase.
- Add unit tests under `ios/YamabikoTests/` for new business/data logic. Select validation according to affected behavior.

## Commit & Pull Request Guidelines
- Current history mixes imperative summaries, Conventional Commit prefixes (`feat(...)`, `fix:`), and occasional emoji/Japanese titles. Keep messages short, specific, and consistent within a PR.
- One logical change per commit when possible.
- PRs should include: purpose, impacted areas, validation steps (commands run), linked issue, and UI screenshots for visible changes.
- Canonical sync target for this workspace is `porarrirr/yamabikochat` on branch `ios`. Use this target when synchronization is requested.

## Security & Configuration Tips
- Never commit secrets, signing certificates, provisioning profiles, or API keys.
- Keep Apple signing and App Store Connect credentials local or in CI secrets; use the manual TestFlight workflow for signed distribution.

## Pi Agents Standard Path
- Treat the standard Pi Agents execution path as the single source of truth for AI execution, API communication, token usage, and context management.
- Do not create, extend, or use custom paths that bypass, replace, or reimplement Pi Agents.
- Pi Runtime exclusively owns provider/model resolution. Native iOS code must pass model identity and explicit user configuration, not select a wire API or synthesize a Pi model.
- Execute only an exact Pi built-in model or a separately verified official contract registered on an existing Pi provider. Otherwise return a typed unsupported reason and stop that model execution. During development, investigation, diagnostics, and tests may continue; implementing an alternative execution path still requires explicit user approval.
- Do not retry through another protocol, endpoint, provider, or model after resolution or stream failure.
- If the standard path cannot satisfy a requirement, stop before implementing an alternative and report the reason and required change to the user.
- Technical necessity does not grant permission for a custom implementation; proceed only after explicit user approval.

## Provider Catalog Fidelity
- Treat provider and model metadata received from models.dev or an upstream provider contract as authoritative. Preserve model-level overrides for provider package, API/base URL, wire shape, capabilities, modalities, limits, and other execution fields; model-level values take precedence over provider-level defaults.
- Do not infer or silently rewrite a model's wire protocol from a provider-level npm/SDK package when the provider can expose heterogeneous per-model protocols. In particular, never collapse Responses, Chat Completions, Anthropic Messages, Gemini, or another protocol into a single generic adapter without an explicit model-level contract.
- Do not treat an unknown or unverified provider package as OpenAI-compatible. If the catalog does not provide enough information to select a Pi adapter unambiguously, stop with an unsupported-provider/model error and report the missing contract instead of guessing.
- Do not overwrite catalog model IDs, endpoints, capability flags (`attachment`, `reasoning`, `tool_call`, modalities), or token limits with app-side heuristics. Only syntax normalization and explicit legacy-ID migrations are allowed; each migration must be narrowly scoped, logged or otherwise observable, and covered by tests.
- Do not synthesize missing URLs, protocols, capabilities, limits, or provider termination fields such as `finish_reason`.
- Keep unsupported catalog models visible but disabled with the exact resolver reason. Never replace a saved unsupported model automatically.
- A user-defined compatibility provider is allowed only through Pi's compatibility/provider APIs and only when the user explicitly supplies both protocol and base URL; catalog metadata is not user authorization to infer either value.
- When models.dev cannot express a provider's documented per-model routing, use a separately maintained authoritative provider contract only for the missing fields. Add an automated drift check against the upstream contract and keep iOS and Pi mappings identical.
- For provider, catalog, or resolver changes, add or update and run tests for every affected executable provider identity, including built-in IDs and `MODELS_DEV:*` IDs, and every affected protocol kind. Validate all providers when shared resolution changes. For other changes, select validation according to the affected behavior.

## iOS Development Best Practices
- Keep iOS implementation under `ios/YamabikoChat/` and treat `ios/project.yml` as the source of truth; regenerate the Xcode project with `xcodegen` after structural file changes.
- Preserve existing iOS provider labels/order, model presets, auth behavior, and settings semantics unless explicitly requested otherwise.
- Use SwiftUI state boundaries clearly: `View` for rendering, `ViewModel` for UI logic, and repository layer for persistence/network/auth; avoid putting side effects directly in views.
- For conversation/navigation flows, prefer selection-based navigation (`NavigationLink`/`selection`) so behavior is stable on both iPhone (compact) and iPad/macOS split views.
- Enforce dual-mode vs auto-conversation exclusivity in both UI toggles and persistence normalization to prevent invalid saved states.
- Keep browser auth robust by starting callback listener before browser launch, validating `state`/`code`, and logging all auth steps/errors into diagnostics.
- Route network/auth failures through `DiagnosticsLogger` with category/metadata so issues can be inspected from the app without Xcode.
- Add or update unit tests in `ios/YamabikoTests/` for settings normalization, auth repositories, and other non-UI business logic when behavior changes.
- For CI IPA output, rely on `.github/workflows/ios-ci.yml` (unsigned IPA artifact/release) and keep TestFlight signing/upload concerns isolated in `ios-testflight.yml`.
