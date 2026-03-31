# iOS Port (YamabikoChat)

This directory contains the native iOS implementation for YamabikoChat.

## Requirements
- macOS with Xcode 16+
- XcodeGen (`brew install xcodegen`)

## Bootstrap
```bash
cd ios
xcodegen generate
open YamabikoChat.xcodeproj
```

## Gemini OAuth Setup
- Edit `ios/YamabikoChat/App/Resources/GeminiAuthInfo.plist`.
- Set:
  - `GEMINI_OAUTH_CLIENT_ID`
  - `GEMINI_OAUTH_CLIENT_SECRET`
- Replace `__SET_ME__` placeholders with your Google OAuth client values before using `Gemini Auth (CLI)` sign-in.
- Fallback: if `GeminiAuthInfo.plist` is missing, the app also reads the same keys from `ios/YamabikoChat/App/Resources/Info.plist`.
- Alternatively, in iOS Settings screen (`Gemini Auth (CLI)` section), you can import a `.plist` file from Files app. Imported values are stored securely and override bundled plist values.

## Targets
- `YamabikoChat`: iOS app (SwiftUI)
- `YamabikoShareExtension`: Share extension for text import
- `YamabikoTests`: unit tests

## Current scope in this repository
- App architecture and feature modules
- SQLite schema via GRDB
- Provider abstraction and all planned provider IDs
- Keychain credential storage
- Share extension payload handoff
- Codex/Gemini auth state management
- OpenRouter model directory/model endpoint retrieval
- Attachment picker/validation/persistence

Build and signing should be completed on macOS.

## CI
- repo root `.github/workflows/ios-ipa.yml`: unsigned IPA build workflow (`workflow_dispatch` and iOS-related pushes; uploads artifact and publishes/updates a prerelease asset)
- repo root `.github/workflows/ios-ci.yml`: macOS build/test (`xcodegen` + `xcodebuild`)
- `ios-testflight.yml`: manual TestFlight upload workflow (requires signing/App Store Connect secrets)
