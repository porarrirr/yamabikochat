# iOS Port (YamabikoChat)

This directory contains the native iOS implementation for YamabikoChat.

## Requirements
- macOS with Xcode 16+
- XcodeGen (`brew install xcodegen`)
- Node.js 24

## Bootstrap
```bash
cd ios
./bootstrap.sh
open YamabikoChat.xcodeproj
```

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
- Codex auth state management
- OpenRouter model directory/model endpoint retrieval
- Attachment picker/validation/persistence

Build and signing should be completed on macOS.

## CI
- repo root `.github/workflows/ios-ipa.yml`: unsigned IPA build workflow (`workflow_dispatch` and iOS-related pushes; uploads artifact and publishes/updates a prerelease asset)
- repo root `.github/workflows/ios-ci.yml`: macOS build/test (`xcodegen` + `xcodebuild`)
- `ios-testflight.yml`: manual TestFlight upload workflow (requires signing/App Store Connect secrets)
