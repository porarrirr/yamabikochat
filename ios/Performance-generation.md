# iOS生成処理の性能測定（2026-10-17）

生成中の表示更新、Pythonセル、GenUIプレビュー転送で70%以上の処理時間削減を確認した。**ネットワークやモデルの生成時間を含むアプリ全体が70%速くなった、という結果ではない。** Web本文抽出の削減率は約46%である。

## 条件と結果

Xcode 27.0、iOS 27.0 / iPhone 18 Pro Simulator、Debug + `SWIFT_OPTIMIZATION_LEVEL=-O`、並列テスト無効。同じ入力の10サンプルの中央値で比較し、削減率は `1 - 改善後時間 / 改善前時間` とした。初回サンプルも削除していない。生データは [Performance-generation-results.json](Performance-generation-results.json)。

- 長い日本語Markdown回答を保持した思考・ツール更新120回: **133.69ms → 8.47ms、93.7%削減**。思考だけが変わったときに、同じ回答のフェンス除去・Markdown処理を繰り返さない。回答の差し替え、ストリームの切り替え、生成完了時は再評価する。
- 300個のCSVを持つワークスペースでのPython計算セル: **57.18ms → 12.65ms、77.9%削減**。ネイティブの `PythonWorker.execute` 全体を測定し、インタープリター起動はウォームアップで除外した。ディレクトリ探索に `scandir` を使い、キャッシュの木を降りず、変更のないファイルのパス解決を省く。メモリ・時間・ファイル制限と監査フックは維持する。
- 160段落の日本語Web記事抽出: **10.86ms → 5.91ms、45.5%削減**。Unicode文書の正規表現マッチをUTF-16位置のまま切り出し、エンティティ処理と固定の正規表現を再利用する。HTTP待ち時間を含まない。
- GenUI引数400差分、50差分/秒の固定リプレイ: 転送を **400回 → 81回**、JSON転送量を **1,227,252 → 249,127 bytes（79.7%削減）** に抑えた。ホストNodeでJSONシリアライズ＋デコードを30回測り、中央値 **3.23ms → 0.51ms（84.1%削減）**。この時間はiOSの描画時間ではない。

専用シミュレーターでの最終再測定でも、表示更新は7.79ms（初期値比94.2%削減）、Pythonセルは14.20ms（75.2%削減）、Web記事抽出は6.06ms（44.2%削減）だった。ホストの他作業による負荷もあり、絶対値にはばらつきがある。

さらにiOSの実際の `ToolActivityPayload.apply` とJavaScript構文検証を通すGenUIリプレイを比較した。同じ400個の生成途中コードを全件処理する対照群と、毎秒10回＋確定引数を処理する群を5回ずつ交互に測定し、中央値 **1,207.12ms → 239.41ms、80.2%削減**だった。最終文書が一致することも確認した。この比較はプレビュー処理の固定リプレイであり、モデル実行やWKWebViewの描画時間を含まない。

GenUIは最初のプレビューを即時表示し、途中の引数を100ms単位でまとめ、確定引数とツール開始前には最新状態を必ず送る。Piにはすべての差分が届く。変更したのはネイティブ表示への転送頻度であり、推論、モデル解決、ツール実行は既存のPi Agents経路を使う。

初期測定のシミュレーターでは別アプリのテストも動いていた。画面テスト・ライブ再検証には専用シミュレーターを使用した。これはシミュレーター上の固定負荷測定であり、実機での電池、発熱、スクロールFPSを表す値ではない。

## 無料モデルを使う実接続

埋め込みNodeMobileのPiランタイムから、Pi組み込みのモデルIDで実行した。課金設定・プロバイダー解決・プロトコルの変更や、失敗後の別モデルへの切り替えは行っていない。OpenRouterではプロンプト・出力の最大単価を0に、プロバイダーフォールバックを無効にして実行した。

- OpenRouter `cohere/north-mini-code:free`: 本文のみの生成は初回差分5.39秒、完了9.90秒、180差分。一連のPython計算・Web取得・GenUI生成・最終回答は12.72秒で成功した。先行する同じツールシナリオは7.38秒であり、外部待ち時間のばらつきが大きい。
- Gemini `gemini-2.5-flash-lite`: 本文のみの生成は初回差分2.86秒、完了3.44秒、5差分。一連のツール実行は3.28秒で成功し、有効なGenUI文書を返した。ツールシナリオの最後の説明文は空だったため、本文ストリーミングは別のリクエストで確認した。

Webでは実際の `FetchUrlTool` で `https://example.com` を取得し、Pythonでは埋め込みCPythonで `sum([12, 18, 30])` を実行した。GenUI文書の検証とツール結果の取り込みを確認した。ライブ計測は各シナリオ1回で、統計的な生成速度改善の証明には使用しない。

APIキーはメモリ内の一時ループバックエンドポイントからテストへ渡し、コード・設定・測定結果へ保存していない。モデルの無料枠の情報は [OpenRouterモデル一覧](https://openrouter.ai/api/v1/models) と [Gemini公式料金表](https://ai.google.dev/gemini-api/docs/pricing) を確認した。

## 再現用コマンド

```sh
cd ios
xcodegen generate
xcodebuild -project YamabikoChat.xcodeproj -scheme YamabikoChat \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -parallel-testing-enabled NO \
  -only-testing:YamabikoTests/GenerationWorkloadPerformanceTests \
  SWIFT_OPTIMIZATION_LEVEL=-O CODE_SIGNING_ALLOWED=NO test
cd PiRuntime
node scripts/benchmark-genui-preview.mjs
npm test
```

`GenerationLivePerformanceTests` は通常スキップする。実接続を行う場合だけ、テストランナーの `YAMABIKO_LIVE_CONFIG_URL` に、`provider`・`model`・`apiKey` を返す一時的な `127.0.0.1` エンドポイントを明示設定する。キーをソース、テスト引数、テスト添付、永続設定へ入れない。

## 回帰検証

測定中に並列Web取得のページ順序が入れ替わる問題を10回中3回再現した。各ツール呼び出しのIDで元の順に組み立てるよう修正し、取得内容と出典を維持する。

- 関連iOSユニットテスト: 159件成功、失敗0。
- GenUI画面操作テスト: 1件成功。入力変更、カードの反転、ダークモードを確認。
- ページ順序の修正後: 30回連続成功。
- Piランタイム: 93件成功。
- Pythonハーネス: 10件成功。
- 無料モデルの実接続テスト: 2プロバイダー × 2シナリオ、計4件成功。
- 最終のiOSテスト用ビルド: 成功。
