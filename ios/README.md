# YamabikoChat for iOS

This directory contains the native iOS implementation for YamabikoChat.

Development notes and design QA evidence are indexed in [docs/README.md](docs/README.md).

## Requirements
- macOS with Xcode 27.0 (see `app-store-build.env`)
- XcodeGen (`brew install xcodegen`)
- Node.js 24.22.1 or a newer security-patched 24.x release

## Bootstrap
```bash
cd ios
./bootstrap.sh
open YamabikoChat.xcodeproj
```

Bootstrap reuses npm dependencies and Pi bundles when their inputs and output
contents match. Python uses a pinned offline Pyodide WebAssembly distribution;
its archive and scientific wheels are verified on every bootstrap. Downloads
are cached under the ignored `Vendor/PyodideCache/` and `Vendor/Pyodide/` directories.

NodeMobile is downloaded from the [YamabikoChat iOS distribution fork](https://github.com/porarrirr/nodejs-mobile).
`node-mobile-release.json` pins the release URL and archive SHA-256. Bootstrap
verifies the archive, both arm64 slices' Node version, and the composite license
before installing it. A content-based cache checks the installed framework on
every bootstrap; old frameworks and edited or missing files are replaced.
Download or validation failures stop bootstrap and preserve the previous
framework. Updating this runtime requires a new tested fork release, its checksum
in the manifest, and the matching `third_party/nodejs-mobile/LICENSE`.

Python runs in a Worker inside an ephemeral WebKit WebContent process. NumPy,
Matplotlib, Pillow, and Noto fonts are bundled and work offline. No native CPython
framework is linked. Python receives bounded workspace copies and has no native
filesystem, Keychain, or network access. Timeout/cancellation destroys the worker;
committed workspace files survive and the next cell starts a fresh namespace.
See [the security design](docs/python-security.md) for the broker, CSP, memory cap,
credential transport policy, and regression-test boundaries.
When updating an existing native-Python build, run `xcodebuild clean` once to remove
extension frameworks and Python resources previously generated inside the app bundle.

Local builds and archives do not enforce the App Store SDK ceiling. The IPA
and TestFlight workflows check the finished app and embedded binaries with
`scripts/validate-app-sdk-versions.sh` before packaging or export. App Store
distribution still requires the toolchain specified in `app-store-build.env`.

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
- repo root `.github/workflows/ios-ci.yml`: runs on iOS-related PRs and pushes to `main`; checks provider contracts, Pi, GenUI DOM, Python, packaging scripts, and iOS unit tests, then builds an unsigned IPA. Test result bundles are uploaded even when tests fail. A newer run cancels an older run on the same branch.
- `ios-testflight.yml`: manual TestFlight upload workflow (requires signing/App Store Connect secrets)

All three iOS workflows use GitHub's `xcode-27` runner image with Xcode 27.0
and the iOS 27.0 SDK, matching `app-store-build.env`. The `macos-26` image
only contains Xcode 26 and cannot build this project. The `xcode-27` image
is currently a public preview; see the [official image announcement](https://github.com/actions/runner-images/issues/14404).
The same WebAssembly Python assets are used for devices and simulators.

## Siri / Apple Intelligence

- アプリを一度起動してプロバイダ・モデル・認証を設定してから、Siriに「やまびこチャットに質問」「やまびこチャットで会話を検索」「やまびこチャットで会話を開く」と依頼します。実際のアプリ名は端末の表示言語に従います。
- 「やまびこに質問」は保存済みの単一モデル設定を使用し、回答をSiriへ返します。ショートカットの「新しい会話に保存」で保存も可能です。モデル指定アクションも利用できます。
- 通常会話をApp Entityとして公開し、タイトルと本文を検索できます。iOS 18以降ではタイトルと更新日時をSpotlightに登録し、追加・改名・削除・シークレット化に追従します。本文・添付・思考ログはSpotlightに登録しません。
- iOS 27以降では `.system.open` / `.system.searchInApp` スキーマと画面上の会話Entityの関連付けを使用します。シークレット会話は検索・Entity解決・画面の関連付け・索引の対象外です。
- AI実行は既存の `ChatRepository.runShortcut` とPiの経路を使います。認証・モデル非対応・通信エラーでは別のモデルや実行経路へ切り替えません。

実機での確認: SiriとApple Intelligenceを有効にした対応端末で、質問と回答の読み上げ、会話検索、会話の表示、表示中の会話への参照、会話の改名・削除後のSpotlight更新を確認してください。Siriの自然言語解釈はOS・言語・端末側の利用可能な機能に依存します。

公式仕様: [App Intents](https://developer.apple.com/documentation/appintents)、[System schemas](https://developer.apple.com/documentation/appintents/app-schema-domain-system-and-in-app-search)、[Onscreen context](https://developer.apple.com/documentation/appintents/providing-contextual-cues-to-apple-intelligence-and-siri)。
