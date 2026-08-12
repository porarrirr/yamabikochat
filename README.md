# YamabikoChat

複数のLLMプロバイダーを切り替え、1対1チャット・2モデル比較・モデル同士の自動会話を行えるネイティブAIチャットアプリです。Android版とiOS版を同じリポジトリで管理しています。

## 対応状況

| プラットフォーム | 実装 | 最低バージョン | ビルド |
|---|---|---|---|
| Android | Jetpack Compose | minSdk 26 | `./gradlew assembleDebug` |
| iOS | SwiftUI | iOS 17+ | XcodeGenでプロジェクト生成後にXcodeでビルド |

両版は同じ主要機能とプロバイダー設定を目標にしていますが、開発中の機能には一時的な差があります。実装状況は各プラットフォームのソースとCI結果を基準にしてください。

## 主な機能

- 1対1チャット
- デュアルモード（2モデルの同時比較）
- 自動会話（モデルA/Bが交互に会話）
- Fusionモード（複数モデルの応答と判定）
- Markdown・MathJax数式表示
- 画像・PDF・テキスト添付（1ファイル最大10MB）
- 会話履歴、検索、プロジェクト、モデルプリセット
- クライアント側Web検索・ツール呼び出し

## スクリーンショット

| iPhone | iPad |
|:---:|:---:|
| ![iPhone chat](ios/AppStoreScreenshots/iphone-6.5-inch/02-chat-math.png) | ![iPad split view](ios/AppStoreScreenshots/ipad-13-inch/01-split-empty.png) |

## APIプロバイダーとデータ送信

設定したプロバイダーに応じて、入力したプロンプト、リクエストに含める会話履歴、選択した添付ファイルが、そのプロバイダーまたは指定した互換APIのベースURLへ送信されます。代表的な接続先はGoogle Gemini、OpenRouter、OpenAI、Z.ai、MiniMax、OpenCode Go、xAI/SuperGrok、Anthropic互換・OpenAI互換APIです。Models.dev連携で追加したプロバイダーやカスタムURLを使う場合、送信先とデータ取扱いはその運営者の規約に従います。

モデル一覧・価格表示のため、OpenRouter、models.dev、LiteLLMの公開メタデータを取得することがあります。Web検索やRemote MCPなどのツールを有効にした場合は、検索語・取得対象URL・ツール引数が選択した外部サービスへ送られます。機密情報を含む会話では、送信先と有効なツールを事前に確認してください。

## APIキーの保存

- Android: Android Keystoreを利用する `EncryptedSharedPreferences`（AES-256）に保存します。
- iOS: Keychainに保存します。
- APIキー、OAuthトークン、署名鍵をソースコードや `local.properties` にコミットしないでください。

端末をroot化・脱獄した環境、侵害されたOS、デバッグログの共有など、端末側の安全性が失われた場合まで保護を保証するものではありません。

## セットアップ

アプリ内の設定画面で利用するプロバイダーと認証情報を登録します。OpenAI互換・Anthropic互換の接続先では、ベースURLが意図したHTTPSホストか確認してください。

### Android

```bash
./gradlew assembleDebug
./gradlew test
```

### iOS

```bash
cd ios
xcodegen generate
open YamabikoChat.xcodeproj
```

## リリース版の入手

配布可能な成果物は [GitHub Releases](https://github.com/porarrirr/yamabikochat/releases) に掲載します。リポジトリ内にIPAやAPKなどのビルド成果物は保存しません。iOSのCI成果物は未署名の場合があり、そのまま通常の端末へインストールできることを保証しません。

## ライセンス

[MIT License](LICENSE)
