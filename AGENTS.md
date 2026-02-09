# Repository Guidelines

## Project Structure & Module Organization
- `app/`: Android app module. Core code in `app/src/main/java/com/porarri/yamabikochat/`.
- Packages: `ui/` (Jetpack Compose screens/components), `data/` (repositories), `utils/`, `data/remote/` (Retrofit APIs).
- Resources: `app/src/main/res/` (themes, strings, drawables, `xml/` configs).
- Tests: `app/src/test/` (unit, Robolectric) and `app/src/androidTest/` (instrumented/UI).
- Build scripts: `build.gradle.kts`, `app/build.gradle.kts`; versions in `gradle/libs.versions.toml`.

## Build, Test, and Development Commands
- `./gradlew assembleDebug` — build debug APK to `app/build/outputs/apk/debug/`.
- `./gradlew installDebug` — install on connected device/emulator.
- `./gradlew test` — run unit and Robolectric tests.
- `./gradlew connectedAndroidTest` — run instrumented tests (device/emulator required).
- `./gradlew lint` — run Android Lint; fix or justify suppressions.
- `./gradlew assembleRelease` — build release; requires signing in `local.properties` (see `local.properties.example`).

## Coding Style & Naming Conventions
- Kotlin, 4‑space indentation; use IDE formatter.
- Packages lowercase dotted (e.g., `com.porarri.yamabikochat`).
- Classes/Composables PascalCase (`MainScreen`, `CodeBlockCard`).
- Functions/vars camelCase; constants UPPER_SNAKE_CASE.
- Resources lowercase_underscores (e.g., `res/xml/network_security_config.xml`).

## Testing Guidelines
- Frameworks: JUnit 4, Robolectric, AndroidX/Espresso, Compose UI testing.
- Unit tests in `app/src/test/.../*Test.kt`; Android tests in `app/src/androidTest/.../*Test.kt`.
- Prefer fast unit tests; use Robolectric for Android‑dependent logic.
- Name tests descriptively (e.g., `SvgAnalyzerTest`).
- Run `./gradlew test connectedAndroidTest` locally before opening a PR.

## Commit & Pull Request Guidelines
- Commits: short, present tense; group related changes. Existing history uses descriptive titles with emojis (e.g., `🔧 コード品質改善`, `🚀 Release 1.0`). Use English or Japanese consistently.
- PRs: include purpose, key changes, screenshots for UI, reproduction/validation steps, and linked issues (e.g., `Closes #123`). Ensure `./gradlew lint test` passes.

## Security & Configuration Tips
- Do not commit secrets. Keep `local.properties` untracked; use the example as a template.
- Release signing uses `YAMABIKO_*` entries and `yamabiko-release-key.keystore`; protect keystores and rotate if exposed.
- Provide API keys via app settings; avoid embedding in code.

