# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Repository Overview

This is a monorepo containing two related projects:

1. **pryamabiko (YamabikoChat)**: Cross-platform AI chat application
   - Android: Kotlin + Jetpack Compose
   - iOS: SwiftUI (iOS 17+)
   - Supports multiple AI providers (Gemini, OpenRouter, OpenAI, Z.ai)
   - Features: dual-mode (2-model comparison), auto-conversation, markdown with MathJax, file attachments

2. **opencode-gemini-auth**: Opencode plugin for Google Gemini authentication
   - TypeScript + Bun
   - Implements OAuth flow for Gemini API access
   - Published to NPM as a plugin for the Opencode CLI

## Key Architectural Patterns

### YamabikoChat (pryamabiko)

**Android Architecture** (`app/` directory):
- **UI Layer**: Jetpack Compose in `app/src/main/java/com/porarri/yamabikochat/ui/`
- **Data Layer**: Room database + Retrofit networking in `app/src/main/java/com/porarri/yamabikochat/data/`
- **Utils**: Helpers and extensions in `app/src/main/java/com/porarri/yamabikochat/utils/`
- **Resources**: XML layouts, strings, colors in `app/src/main/res/`; web assets (MathJax) in `app/src/main/assets/`

**iOS Architecture** (`ios/` directory):
- SwiftUI view structure mirrors Android UI (shared semantics for providers, models, settings)
- Xcode project generated from `ios/project.yml` via xcodegen
- SQLite persistence via GRDB
- Keychain for credential storage
- Share extension (`YamabikoShareExtension/`) for text import

**Provider Abstraction**:
- Both platforms use a unified provider interface (Gemini, OpenRouter, OpenAI, Z.ai)
- Provider labels, ordering, and default model presets should remain consistent across platforms
- Settings and auth behavior synchronized between Android and iOS

### opencode-gemini-auth

- **Single entry point**: `index.ts` exports the plugin interface
- **Plugin architecture**: Uses `@openauthjs/openauth` for OAuth flow
- **TypeScript with Bun**: Modern toolchain with type safety
- **No build step**: Direct TypeScript execution via Bun

## Development Commands

### YamabikoChat - Android

```bash
cd pryamabiko

# Build and test
./gradlew assembleDebug           # Build debug APK
./gradlew test                     # Run unit tests
./gradlew connectedAndroidTest    # Run device/emulator tests
./gradlew lint                     # Lint checks

# Release (requires signing credentials in local.properties)
./gradlew assembleRelease         # Build release APK
./gradlew assembleDebug --info    # Detailed build log

# Run specific test
./gradlew test --tests "*ClassName"
```

**Signing Configuration**:
- Signing credentials required: `YAMABIKO_KEY_ALIAS`, `YAMABIKO_KEY_PASSWORD`, `YAMABIKO_STORE_PASSWORD`
- Set in `local.properties` or as Gradle properties
- Keystore file: `../yamabiko-release-key.keystore`
- Template: `local.properties.example`

### YamabikoChat - iOS

```bash
cd pryamabiko/ios

# Generate Xcode project (run after structural changes)
xcodegen generate
open YamabikoChat.xcodeproj

# Build from CLI
xcodebuild -project YamabikoChat.xcodeproj -scheme YamabikoChat \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
xcodebuild test -project YamabikoChat.xcodeproj -scheme YamabikoChat
```

**Requirements**: Xcode 16+, xcodegen (`brew install xcodegen`)

**OAuth Configuration**:
- Primary: `ios/YamabikoChat/App/Resources/GeminiAuthInfo.plist` (Google OAuth credentials)
- Fallback: `ios/YamabikoChat/App/Resources/Info.plist`
- Settings allow runtime `.plist` import from Files app (stored in keychain)

**CI Workflows** (in `.github/workflows/`):
- `ios-ci.yml`: xcodegen + xcodebuild (unsigned IPA artifact)
- `ios-ipa.yml`: Unsigned IPA build and optional release asset
- `ios-testflight.yml`: Manual TestFlight upload (requires App Store Connect secrets)

### opencode-gemini-auth

```bash
cd opencode-gemini-auth

# Install and develop
bun install

# Link locally in Opencode config
# Update ~/.config/opencode/opencode.json:
# "plugin": ["file:///absolute/path/to/opencode-gemini-auth"]

# Update upstream reference (optional)
bun run update:gemini-cli
```

**Publishing**: Built as NPM package; versions in `package.json`

## Code Organization & Conventions

### Naming
- **Classes/Composables/Types**: `PascalCase`
- **Functions/Variables**: `camelCase`
- **Constants**: `UPPER_SNAKE_CASE`
- **Android packages/resources**: `lowercase_underscore`
- **Android resources**: `lowercase_underscore` (e.g., `activity_main.xml`, `button_primary.xml`)

### Code Style
- **Indentation**: 4 spaces (Kotlin, Swift)
- Keep files focused; prefer small view models and repositories
- SwiftUI: Use clear state boundaries—`View` for rendering, `ViewModel` for UI logic, repositories for persistence/network
- Android Compose: Follow standard Compose patterns; avoid side effects directly in composables

### Testing
**Android**:
- Unit tests: `app/src/test/` (JUnit4, MockK, Coroutines Test)
- Instrumented tests: `app/src/androidTest/` (Espresso/Compose test libs)
- File naming: `*Test.kt`, mirror source package structure
- Add unit tests for new business/data logic; use instrumented tests only for Android framework/UI behavior

**iOS**:
- Tests in `ios/YamabikoTests/`
- Unit tests for settings normalization, auth repositories, and non-UI business logic
- Add tests when auth or persistence behavior changes

## Important Implementation Notes

### Android (Jetpack Compose)
- Compose BOM pin for consistent dependency versions
- Room database for persistence; KAPT for annotation processing
- Retrofit + OkHttp for networking; kotlinx.serialization for JSON
- Markdown rendering via Markwon (4.6.2) with LaTeX support and SVG rendering
- ExifInterface for image orientation handling
- Security: Use AndroidX security-crypto for sensitive data
- Build variants: debug, release, diagnostic (with obfuscation via ProGuard/R8)
- Compilation: Java 17, Kotlin jvmTarget 17

### iOS (SwiftUI)
- GRDB for SQLite persistence (type-safe, Codable integration)
- Keychain integration via Apple's Security framework
- Navigation: Prefer selection-based (`NavigationLink`/`selection`) for stable iPad/macOS split view behavior
- Dual-mode vs auto-conversation: Enforce exclusivity in both UI toggles and persistence normalization
- Auth robustness: Start callback listener before browser launch; validate state/code; log all steps to DiagnosticsLogger
- Network/auth failures: Route through `DiagnosticsLogger` with category/metadata for in-app inspection
- Share extension: Handles text payload handoff to main app
- Targets: `YamabikoChat` (app), `YamabikoShareExtension` (share), `YamabikoTests` (tests)

### Provider System
- Unified provider interface across both platforms
- Gemini: Uses OAuth (CLI) for authentication, supports thinking models
- OpenRouter: Model directory/endpoint retrieval integrated
- OpenAI: Standard API key authentication
- Z.ai: Standard API key authentication
- All providers support the same conversation/attachment API surface

## Dependencies & Versioning

### YamabikoChat - Android
- **Gradle**: 8.x with Kotlin plugins
- **Android SDK**: compileSdk=35, minSdk=24, targetSdk=35
- **Compose**: Latest via BOM from libs
- **Room**: Latest via BOM
- **Retrofit**: Latest via BOM with Gson + Kotlinx Serialization converters
- **See**: `gradle/libs.versions.toml` for all managed versions

### opencode-gemini-auth
- **Runtime**: Node-compatible runtime (uses Bun)
- **@openauthjs/openauth**: ^0.4.3 (OAuth flow library)
- **TypeScript**: ^5.9.3 (peer dependency)
- **See**: `package.json` for dependencies and `bun.lock` for lock file

## Git & Sync

**YamabikoChat canonical sync**:
- Target: `porarrirr/yamabikochat` branch `ios`
- Keep local and remote branch aligned
- Commit messages: Short, specific; mix of imperative and Conventional Commit prefixes acceptable
- One logical change per commit when possible
- PR guidelines: Include purpose, impacted areas, validation steps, issue links, and UI screenshots for visible changes

## Security & Secrets

**Never commit**:
- API keys, tokens, or signing credentials
- `local.properties` (use `local.properties.example` as template)
- Keystores or signing files (except template/example files)

**Local configuration**:
- Signing credentials: Set via `local.properties` or Gradle properties
- OAuth: Store in `.plist` files or keychain (iOS) / encrypted shared preferences (Android)
- Debug builds can read from config files; release builds must use secure storage

## Troubleshooting & Common Tasks

### Android Build Issues
- **Gradle sync fails**: Check `gradle/libs.versions.toml` and `.gradle/` folder consistency
- **Lint warnings**: Run `./gradlew lint` to identify issues; many are configurable via ProGuard rules
- **Dependency conflicts**: Inspect `gradle dependencies` output to resolve version conflicts

### iOS Build Issues
- **Xcode project mismatch**: Always run `xcodegen generate` after file structural changes to `ios/project.yml`
- **Signing issues**: Ensure correct team/bundle ID in `ios/project.yml` and Xcode settings
- **Framework linking**: If new dependencies added, regenerate project with xcodegen

### Multi-Provider Development
- When adding a new provider: Update both Android and iOS implementations
- Ensure provider labels and default models match across platforms
- Test auth flow for new providers on both platforms
- Add unit tests for provider-specific logic in both layers
