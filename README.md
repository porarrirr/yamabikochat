# YamabikoChat

Android向けのAIチャットアプリです。複数プロバイダーのモデルを切り替えて会話できます。

## 機能
- 1対1チャット
- デュアルモード（2モデルの同時比較）
- 自動会話（モデルA/Bが交互に会話）
- Markdown表示（MathJax数式）
- 添付対応（画像/PDF/テキスト、1ファイル最大10MB）

## セットアップ
- アプリ内設定でAPIキーを登録  
  対応プロバイダー: Google Gemini / OpenRouter / OpenAI / OpenAI互換 / Z.ai

## 開発
```bash
# デバッグビルド
./gradlew assembleDebug

# テスト
./gradlew test
```

## iOSポート
- `ios/` 配下に SwiftUI ネイティブ実装を追加しています（iOS 17+）。
- `xcodegen` を使ってプロジェクトを生成します。

```bash
cd ios
xcodegen generate
open YamabikoChat.xcodeproj
```

## ライセンス
MIT
