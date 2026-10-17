# YamabikoChat

English | [日本語](README.ja.md)

A native AI chat app for iPhone and iPad that lets you switch between multiple LLM providers, compare two models side by side, and run automatic model-to-model conversations.

Development and maintenance focus exclusively on iOS. Android development has ended; its previous implementation remains in Git history. The default development branch is `ios`.

## Highlights

- Standard one-to-one chat
- Dual mode for comparing two model responses
- Automatic conversations between model A and model B
- Fusion mode for collecting and evaluating multiple responses
- Markdown and MathJax rendering
- Image, PDF, and text attachments up to 10 MB per file
- Conversation history, search, projects, and model presets
- Optional client-side web search and tool calling

## Screenshots

| iPhone | iPad |
|:---:|:---:|
| ![iPhone chat](ios/AppStoreScreenshots/iphone-6.5-inch/02-chat-math.png) | ![iPad split view](ios/AppStoreScreenshots/ipad-13-inch/01-split-empty.png) |

## Providers and privacy

YamabikoChat connects to the provider you configure, including services such as Gemini, OpenRouter, OpenAI, Z.ai, MiniMax, OpenCode Go, xAI/SuperGrok, and compatible APIs. Prompts, the conversation context included in a request, and selected attachments are sent to that provider. Custom endpoints and optional tools follow the data-handling terms of their respective operators.

API credentials are stored in the iOS Keychain. Before using sensitive content, confirm the destination provider, base URL, and enabled tools.

## Build

```bash
cd ios
./bootstrap.sh
open YamabikoChat.xcodeproj
```

Builds intended for distribution are published on [GitHub Releases](https://github.com/porarrirr/yamabikochat/releases). CI-generated iOS artifacts may be unsigned and are not necessarily installable on a normal device.

## Repository layout

| Location | Purpose |
|---|---|
| [ios/](ios/README.md) | iOS app, tests, and build tooling |
| [ios/docs/](ios/docs/README.md) | Development notes and design QA evidence |
| `scripts/` | Provider contract checks |
| [docs/](docs/README.md) | Public website and legal/support pages |
| `third_party/` | Third-party contracts and notices |

Local reference clones belong in `.local/reference-repos/` (ignored by Git).
Build caches and restored dependencies remain in the locations expected by the build tools.

## License

Original project code is available under the [MIT License](LICENSE). Bundled and restored third-party software remains subject to its own terms; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
