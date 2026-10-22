<div align="center">

<img src="assets/readme/icon.png" alt="YamabikoChat app icon" width="128">

# YamabikoChat

**A native AI chat studio for iPhone and iPad.**<br>
One prompt, many models — compare answers side by side, let models debate each other,<br>
or fuse several responses into a single verdict.

**English** · [日本語](README.ja.md) · [简体中文](README.zh-Hans.md)

<a href="https://apps.apple.com/jp/app/yamabikochat-ai%E3%83%81%E3%83%A3%E3%83%83%E3%83%88/id6771687018"><img src="assets/readme/app-store-badge-en.svg" alt="Download on the App Store" width="180"></a>

[![Release](https://img.shields.io/github/v/release/porarrirr/yamabikochat?include_prereleases&display_name=tag)](https://github.com/porarrirr/yamabikochat/releases)
![Platform](https://img.shields.io/badge/iOS_·_iPadOS-17%2B-blue)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

**YamabikoChat** (山彦 — "mountain echo") is a SwiftUI-native AI client built around a simple idea: no single model is always right. Chat with one model, put two side by side, let two models hold a conversation on their own, or run a full panel → judge → synthesizer pipeline — all from one app, on your device.

> iOS and iPadOS only. Android development has ended; the previous implementation remains in Git history. The default development branch is `ios`.

## Screenshots

| Chat · code & math | GenUI interactive answers | Dark mode | Conversation library |
|:-:|:-:|:-:|:-:|
| <img src="assets/readme/iphone-chat.png" width="200" alt="Chat with code and math"> | <img src="assets/readme/iphone-genui.png" width="200" alt="GenUI loan comparison chart"> | <img src="assets/readme/iphone-dark.png" width="200" alt="Dark mode GenUI components"> | <img src="assets/readme/iphone-list.png" width="200" alt="Conversation list with projects"> |

| iPad split view |
|:-:|
| <img src="assets/readme/ipad-split.png" width="560" alt="iPad split view with sidebar and chat"> |

## Features

### Four conversation modes

- **Chat** — classic one-on-one with streaming answers, edit/regenerate, and response variants.
- **Dual** — send one prompt to two models and read their answers side by side.
- **Auto conversation** — choose two models, a topic, and a turn count, then watch them talk to each other.
- **Fusion** — your question goes to a panel of models in parallel, a judge model produces a structured comparison (agreements, contradictions, unique insights, suspected errors), and a synthesizer writes the final answer. Ships with quality / budget / fast presets and full custom JSON.

### Providers

| Provider | How you connect |
|---|---|
| Google Gemini | API key or Google sign-in (OAuth) |
| ChatGPT plan | Sign in with your OpenAI account — uses your ChatGPT subscription |
| OpenAI | API key |
| OpenRouter | API key — browse the full model directory in-app |
| SuperGrok (xAI) | xAI account sign-in |
| Z.ai · MiniMax | API key |
| OpenCode Go · ClinePass · Alibaba Coding Plan | Plan credentials with in-app usage tracking |
| Sarashina | API key |
| Apple Intelligence | Built in — on-device and Private Cloud Compute, no key needed |
| Custom endpoint | Any OpenAI-compatible base URL + key |
| models.dev catalog | Additional providers resolved with per-model wire contracts |

Model identity and execution are resolved by the embedded [Pi Agents runtime](ios/PiRuntime/) — unsupported models stay visible but disabled with an explicit reason instead of silently guessing a protocol.

### Client-side tools

- **Web search** — federated DuckDuckGo search the model can call mid-answer.
- **Python** — an embedded Python runtime executes model-written code and returns output and files.
- **GenUI** — models can answer with live UI: interactive charts, cards, and SVG graphics rendered natively.
- **File editor & ask-user** — structured edits and mid-task clarification.

### Rendering

- Markdown (swift-markdown), tables, and syntax-highlighted code blocks with one-tap copy.
- MathJax equations.
- GenUI rich documents with CEL-evaluated interactivity.

### Built for iOS & iPadOS

- **Siri, Shortcuts & App Intents** — ask Yamabiko hands-free, or run a saved model / Fusion preset from Shortcuts.
- **Spotlight** — conversation titles are indexed and searchable; onscreen context lets Siri act on the chat you're looking at.
- **Secret conversations** — excluded from Spotlight, Siri, and entity resolution entirely.
- **Share extension** — send text from any app straight into a new chat.
- **Attachments** — images, PDFs, and text files up to 10 MB each.
- **Organization** — projects, history search, model presets, per-message token usage statistics.
- **Dark mode** and an iPad-optimized split view.
- UI localized in English, 日本語, 简体中文, Español, and Français.

## Privacy & data handling

- Prompts, the conversation context included in a request, and selected attachments go **only** to the provider you configured. Custom endpoints and optional tools follow the data-handling terms of their respective operators.
- API credentials are stored in the iOS Keychain.
- Apple Intelligence requests run on-device or through Apple's Private Cloud Compute.
- A built-in diagnostics logger records network/auth failures with categories and metadata so issues can be inspected in-app — no Xcode required.

Before sending sensitive content, confirm the destination provider, base URL, and enabled tools.

## Download

Signed and unsigned builds are published on [GitHub Releases](https://github.com/porarrirr/yamabikochat/releases). CI-generated iOS artifacts may be unsigned and are not necessarily installable on a normal device — TestFlight distribution is handled by a separate manual workflow.

## Build from source

Requirements: macOS, Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Node.js 24.

```bash
cd ios
./bootstrap.sh        # restore dependencies, build Pi, generate the Xcode project
open YamabikoChat.xcodeproj
```

Run the test suites:

```bash
cd ios && xcodegen generate
xcodebuild -project YamabikoChat.xcodeproj -scheme YamabikoChat \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  CODE_SIGNING_ALLOWED=NO test
npm test --prefix ios/PiRuntime          # Pi runtime tests
npm test --prefix ios/GenUIRuntimeTests  # GenUI DOM tests
```

See [ios/README.md](ios/README.md) for bootstrap caching, targets, and CI details.

## Repository layout

| Location | Purpose |
|---|---|
| [ios/YamabikoChat/](ios/YamabikoChat/) | SwiftUI app — features, data layer, Pi bridge, App Intents |
| [ios/YamabikoShareExtension/](ios/YamabikoShareExtension/) | Share extension for text import |
| [ios/YamabikoTests/](ios/YamabikoTests/) | Unit tests |
| [ios/PiRuntime/](ios/PiRuntime/) | Pi Agents runtime and JS tests |
| [ios/docs/](ios/docs/README.md) | Development notes and design QA evidence |
| [docs/](docs/README.md) | Public website — privacy, support, terms, Fusion explainer |
| `scripts/` | Upstream provider contract checks |
| `third_party/` | Third-party contracts and notices |

## License

Original project code is available under the [MIT License](LICENSE). Bundled and restored third-party software remains subject to its own terms — see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
