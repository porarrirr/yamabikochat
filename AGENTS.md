# Repository Guidelines

## Project Structure & Module Organization
- `app/` is the Android module (Jetpack Compose + data layer). Main code lives in `app/src/main/java/com/porarri/yamabikochat/` with `ui/`, `data/`, and `utils/` packages.
- Android resources are under `app/src/main/res/`; shared web assets (MathJax) are in `app/src/main/assets/`.
- Android tests: `app/src/test/` (unit/Robolectric) and `app/src/androidTest/` (instrumented).
- `ios/` contains the SwiftUI iOS port plus share extension and tests (`YamabikoChat/`, `YamabikoShareExtension/`, `YamabikoTests/`).
- Build configuration: `build.gradle.kts`, `app/build.gradle.kts`, versions in `gradle/libs.versions.toml`, iOS project spec in `ios/project.yml`.

## Build, Test, and Development Commands
- `./gradlew assembleDebug`: build Android debug APK.
- `./gradlew test`: run Android unit tests.
- `./gradlew connectedAndroidTest`: run device/emulator tests.
- `./gradlew lint`: run Android lint checks.
- `./gradlew assembleRelease`: build release APK (requires `YAMABIKO_*` signing values).
- `cd ios && xcodegen generate`: generate Xcode project.
- `cd ios && xcodebuild -project YamabikoChat.xcodeproj -scheme YamabikoChat -destination 'platform=iOS Simulator,name=iPhone 16' build`: validate iOS build from CLI.

## Coding Style & Naming Conventions
- Kotlin/Swift: 4-space indentation, keep files focused, and prefer small view models/repositories.
- Naming: classes/composables/types in PascalCase, methods/variables in camelCase, constants in UPPER_SNAKE_CASE.
- Package/module names stay lowercase (`com.porarri.yamabikochat`); Android resources use `lowercase_underscore`.

## Testing Guidelines
- Android uses JUnit4, MockK, Coroutines Test, and Espresso/Compose test libs.
- Test files follow `*Test.kt` naming and mirror source package structure.
- Add unit tests for new business/data logic; use instrumented tests only for Android framework/UI behavior.

## Commit & Pull Request Guidelines
- Current history mixes imperative summaries, Conventional Commit prefixes (`feat(...)`, `fix:`), and occasional emoji/Japanese titles. Keep messages short, specific, and consistent within a PR.
- One logical change per commit when possible.
- PRs should include: purpose, impacted areas, validation steps (commands run), linked issue, and UI screenshots for visible changes.

## Security & Configuration Tips
- Never commit secrets or keystores. Use `local.properties.example` as the template for local config.
- Keep signing credentials (`YAMABIKO_KEY_ALIAS`, `YAMABIKO_KEY_PASSWORD`, `YAMABIKO_STORE_PASSWORD`) local/CI-secret only.

## iOS Development Best Practices
- Keep iOS implementation under `ios/YamabikoChat/` and treat `ios/project.yml` as the source of truth; regenerate the Xcode project with `xcodegen` after structural file changes.
- Preserve Android parity for provider labels/order, default model presets, auth behavior, and settings semantics unless explicitly requested otherwise.
- Use SwiftUI state boundaries clearly: `View` for rendering, `ViewModel` for UI logic, and repository layer for persistence/network/auth; avoid putting side effects directly in views.
- For conversation/navigation flows, prefer selection-based navigation (`NavigationLink`/`selection`) so behavior is stable on both iPhone (compact) and iPad/macOS split views.
- Enforce dual-mode vs auto-conversation exclusivity in both UI toggles and persistence normalization to prevent invalid saved states.
- Keep browser auth robust by starting callback listener before browser launch, validating `state`/`code`, and logging all auth steps/errors into diagnostics.
- Route network/auth failures through `DiagnosticsLogger` with category/metadata so issues can be inspected from the app without Xcode.
- Add or update unit tests in `ios/YamabikoTests/` for settings normalization, auth repositories, and other non-UI business logic when behavior changes.
- For CI IPA output, rely on `.github/workflows/ios-ci.yml` (unsigned IPA artifact/release) and keep TestFlight signing/upload concerns isolated in `ios-testflight.yml`.

