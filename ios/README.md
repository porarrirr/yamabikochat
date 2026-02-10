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
- Edit `ios/YamabikoChat/App/Resources/Info.plist`.
- Set:
  - `GEMINI_OAUTH_CLIENT_ID`
  - `GEMINI_OAUTH_CLIENT_SECRET`
- Replace `__SET_ME__` placeholders with your Google OAuth client values before using `Gemini Auth (CLI)` sign-in.

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
- `ios-ipa.yml`: unsigned IPA build workflow (`workflow_dispatch` and iOS-related pushes; artifact upload, optional release asset on manual run)
- `ios-ci.yml`: macOS build/test (`xcodegen` + `xcodebuild`)
- `ios-testflight.yml`: manual TestFlight upload workflow (requires signing/App Store Connect secrets)
