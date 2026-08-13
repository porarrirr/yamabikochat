# YamabikoChat

English | [日本語](README.ja.md)

A native AI chat app for Android and iOS that lets you switch between multiple LLM providers, compare two models side by side, and run automatic model-to-model conversations.

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

API credentials are stored with Android Keystore-backed encrypted preferences on Android and Keychain on iOS. Before using sensitive content, confirm the destination provider, base URL, and enabled tools.

## Build

Android:

```bash
./gradlew assembleDebug
./gradlew test
```

iOS:

```bash
cd ios
xcodegen generate
open YamabikoChat.xcodeproj
```

Builds intended for distribution are published on [GitHub Releases](https://github.com/porarrirr/yamabikochat/releases). CI-generated iOS artifacts may be unsigned and are not necessarily installable on a normal device.

## License

[MIT License](LICENSE)
