# iOS Port (YamabikoChat)

This directory contains the native iOS implementation for YamabikoChat.

Development notes and design QA evidence are indexed in [docs/README.md](docs/README.md).

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

Bootstrap reuses npm dependencies, Pi bundles, and extracted Python packages
when their inputs and output contents match. Wheel checksums and the active SDK
are still validated. These caches live under the ignored `Vendor/` directory;
deleting `Vendor/*cache.json` and `Vendor/PythonSitePackages/.*-cache.json`
forces preparation on the next bootstrap.

The Python build phase checks input and product hashes on every build, then
reuses unchanged packaging. Debug builds reuse individual file hashes when
device, inode, size, permissions, nanosecond modification time and change time
match; file additions, deletions and same-size edits with restored modification
times still invalidate the cache. Release builds always read all file contents.
SDK, architecture, deployment target, and signing
settings participate in the cache key. Its stamp lives in Xcode's target
temporary directory, so a clean build repackages Python. Release builds reuse
existing framework dSYMs only when their UUIDs match the binaries.

Xcode's `YamabikoBuildMetadata` dependency generates the app and share extension
Info.plist inputs together before processing or embedding. Both use the same
build timestamp; unchanged versions preserve the generated files' timestamps.
Source Info.plist files remain the templates. Legal notices declare their inputs
and outputs so Xcode skips unchanged copies.

To measure local incremental builds, run the same command twice after the first
successful build (without cleaning DerivedData):

```bash
cd ios
xcodebuild -project YamabikoChat.xcodeproj -scheme YamabikoChat \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -showBuildTimingSummary build
```

Measured on 2026-10-17 with Xcode 27.0, iPhone 18 Pro Simulator and signing
disabled: two unchanged builds averaged 4.74 seconds before and 3.14 seconds
after these changes (34% less wall time). Each configuration was warmed first,
using the same dedicated DerivedData directory; clean builds and the initial
cache migration are excluded. Clean and Release build times were not compared.

See Apple's [incremental build guidance](https://developer.apple.com/documentation/xcode/improving-the-speed-of-incremental-builds)
for script dependency declarations.

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

## Siri / Apple Intelligence

- アプリを一度起動してプロバイダ・モデル・認証を設定してから、Siriに「やまびこチャットに質問」「やまびこチャットで会話を検索」「やまびこチャットで会話を開く」と依頼します。実際のアプリ名は端末の表示言語に従います。
- 「やまびこに質問」は保存済みの単一モデル設定を使用し、回答をSiriへ返します。ショートカットの「新しい会話に保存」で保存も可能です。既存のモデル指定・Fusionアクションも引き続き利用できます。
- 通常会話をApp Entityとして公開し、タイトルと本文を検索できます。iOS 18以降ではタイトルと更新日時をSpotlightに登録し、追加・改名・削除・シークレット化に追従します。本文・添付・思考ログはSpotlightに登録しません。
- iOS 27以降では `.system.open` / `.system.searchInApp` スキーマと画面上の会話Entityの関連付けを使用します。シークレット会話は検索・Entity解決・画面の関連付け・索引の対象外です。
- AI実行は既存の `ChatRepository.runShortcut` とPiの経路を使います。認証・モデル非対応・通信エラーでは別のモデルや実行経路へ切り替えません。

実機での確認: SiriとApple Intelligenceを有効にした対応端末で、質問と回答の読み上げ、会話検索、会話の表示、表示中の会話への参照、会話の改名・削除後のSpotlight更新を確認してください。Siriの自然言語解釈はOS・言語・端末側の利用可能な機能に依存します。

公式仕様: [App Intents](https://developer.apple.com/documentation/appintents)、[System schemas](https://developer.apple.com/documentation/appintents/app-schema-domain-system-and-in-app-search)、[Onscreen context](https://developer.apple.com/documentation/appintents/providing-contextual-cues-to-apple-intelligence-and-siri)。
