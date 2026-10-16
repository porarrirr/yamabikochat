iOSチャット処理の性能改善（2026-10-16）

空の会話の検索、履歴読み込み、長文Markdown解析で、計測した処理時間を50%以上短縮した。ストリーミング解析も改善したが、短縮率は50%未満だった。以下は各処理のベンチマークであり、アプリ全体の操作時間、画面のFPS、通信やモデルの応答時間を測定した結果ではない。

- 空の会話の検索（500件の使用済み候補）: 4.388 ms → 0.248 ms（94.3%短縮）。
- 履歴の要約読み込み（500メッセージ）: 5.949 ms → 2.813 ms（52.7%短縮）。
- 送信用履歴の読み込み（500メッセージ）: 6.032 ms → 2.986 ms（50.5%短縮）。
- 長文Markdown解析（400ブロック）: 26.480 ms → 12.895 ms（51.3%短縮）。
- ストリーミング解析（長文への60回の追記）: 11.340 ms → 8.668 ms（23.6%短縮）。

Apple M2、macOS 27.0.1、Xcode 27.0（27A266a）、iPhone 18 Pro / iOS 27.0（24A434）シミュレータで計測した。Debug構成に `SWIFT_OPTIMIZATION_LEVEL=-O` を指定し、変更前後で同じ入力と同じ5つのXCTestを使用した。数値はXCTest Wall Clock Timeの10サンプルの算術平均。短縮率は `(変更前 - 変更後) / 変更前`。変更前のソースは `9468a96`。DBの作成・マイグレーション・データ投入は計測区間に含めない。ベンチマーク自身はネットワークやモデルを実行しない。変更後は同じ機種・OSの専用シミュレータを使用した。実機計測およびホスト負荷を統制した統計的な検証は行っていない。

空の会話は、全候補のデコードと候補ごとのCOUNT照会を、既存のインデックスを使うNOT EXISTS / LIMIT 1のSQLに置き換えた。履歴読み込みは、同一トランザクション内でシークレット判定を1回だけ取得する。判定をトランザクション間で保持せず、暗号化と復号、回答候補の選択、思考履歴、DBの変更通知を維持する。SQLトレースによる回帰テストで、通常・シークレットの両方について、6つの読み込み経路で判定照会が1回になることを確認した。

Markdown解析は、URL・数式の正規表現を再利用し、該当する記号がないテキストの正規表現検索を省いた。ストリーミングはUTF-8の完全一致を保ったバッファ比較を使い、参照リンクの括弧は追記部分だけを検査する。本文置換で状態をリセットし、連続バッファを利用できない文字列には従来のバイト比較を使う。使用されていなかった確定済み本文の複製も削除した。

関連するXCTest 152件は0失敗で完了した。内訳は性能テスト5件、ChatPerformancePolicyTests、ChatPresentationArchitectureTests、ChatStreamSessionTests、ConversationReadPolicyTests、ConversationVariantSelectionTests、NativeMarkdownHotPathTests、ProjectFeatureTests、SecretConversationVaultTests。日本語・絵文字・Unicode正規化の異なる本文置換・参照リンク・URL・数式・回答候補・シークレット会話・画面レイアウトを検証した。

Xcodeのテストセッションは、テスト成功の表示後に結果回収待ちで停止したため終了した。最終待機中にXcodeは `IDESchemeActionResultOperation` / `trackingOperationFinished:NO` の内部警告を出した。変更前5件と変更後152件の成功および全測定サンプルは実行ログで確認したが、テストコマンドの正常終了や最終xcresultの完成は確認できていない。別に実行したbuildは終了コード0、`BUILD SUCCEEDED`。測定値は成功したテストのログから抽出し、隣接するJSONに保存した。

再計測は `ios/` で以下を実行する（destinationのIDは使用するシミュレータに合わせる）。

```sh
xcodegen generate
xcodebuild -project YamabikoChat.xcodeproj -scheme YamabikoChat \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -configuration Debug -parallel-testing-enabled NO -jobs 4 \
  -only-testing:YamabikoTests/ChatHotPathPerformanceTests \
  -resultBundlePath /tmp/yamabiko-chat-performance.xcresult \
  SWIFT_OPTIMIZATION_LEVEL=-O CODE_SIGNING_ALLOWED=NO test
```

変更前を再現する場合は、`9468a96` の作業コピーに同じ `ChatHotPathPerformanceTests.swift` を追加してXcodeGenを実行する。比較中は入力とコンパイラ設定をそろえる。
