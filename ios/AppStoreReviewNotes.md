# App Store Review Notes

YamabikoChat is a bring-your-own-key chat client. The app does not sell digital content, subscriptions, token credits, or provider access. Users connect their own third-party LLM accounts or API keys when they choose to use those providers.

## Reviewer Access

- The app can be opened and inspected without signing in.
- API key providers require the reviewer's own test API key.
- Codex Auth is an optional provider connection. It opens the provider's web authentication page only after the user taps Sign in.

## Privacy And Data Use

- User prompts, attachments, and selected model settings are sent only to the provider selected by the user for that conversation.
- API keys and OAuth tokens are stored in Keychain.
- Conversation history and diagnostics are stored locally on device.
- Diagnostic logs are local and user-initiated for copy/clear. They avoid recording API keys, access tokens, refresh tokens, full prompts, and local attachment paths.
- Photos access is read-only and used to attach selected or recent images to a conversation.
- Microphone and Speech Recognition are used only for voice dictation into the message composer.
- Share Extension stores shared text/URLs into the app group so the main app can create a draft conversation.

## External Tools

- Remote MCP, Google Search, URL Context, Code Execution, Google Maps, Computer Use, and Codex Web Search are off by default.
- These options send tool declarations to the selected remote provider. The app does not execute arbitrary downloaded code on device and does not grant remote providers native iOS API access.
- Remote MCP accepts only HTTPS server URLs with no embedded user/password. Optional authorization tokens are stored in Keychain.

## Privacy Manifest

The app and share extension include privacy manifests. Share extension handoff uses an app-group file, not UserDefaults.
