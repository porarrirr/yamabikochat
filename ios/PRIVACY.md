# YamabikoChat Privacy Policy

Last updated: 2026-05-21

YamabikoChat is a bring-your-own-key (BYOK) chat client. This policy describes how the iOS app handles information on your device.

## What the app stores locally

- Conversation history, projects, and app settings on your device.
- API keys and OAuth tokens in the iOS Keychain.
- Optional diagnostic logs that you can view, copy, share, or clear from Settings.

## What the app sends to third parties

- When you send a message, your prompt, selected model settings, and attachments are sent only to the provider you selected for that conversation (for example OpenAI, Google Gemini, OpenRouter, or a custom API endpoint you configure).
- Optional tools (remote MCP, search, code execution, and similar features) are disabled by default. When enabled, related requests are sent to the provider or HTTPS endpoint you configure.
- The Share Extension stores shared text or a URL in the app group so the main app can open a draft conversation.

## What the app does not do

- The app does not sell subscriptions, tokens, or provider access inside the app.
- The app does not use App Tracking Transparency or cross-app tracking.
- Diagnostic logs are designed to avoid recording API keys, access tokens, refresh tokens, full prompts, and local attachment paths.

## Permissions

- Photos: read-only access to attach recent images to a conversation.
- Microphone and Speech Recognition: used only for optional voice dictation into the message composer.

## Web version

https://porarrirr.github.io/yamabikochat/privacy.html

## Contact

Questions or requests: https://porarrirr.github.io/yamabikochat/support.html
