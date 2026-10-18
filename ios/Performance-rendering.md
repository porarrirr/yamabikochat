# iOS描画・操作負荷の測定（2026-10-18）

実際のチャット画面の描画処理を改善し、長いリストのストリーミングでCPU時間を **6.756秒 → 2.960秒、56.2%削減**した。思考更新は34.0%、描画リプレイのスクロールは24.8%削減だった。**アプリ全体のCPU・GPUを80%以上削減する目標は未達。** 通常本文・待機・画面操作も同じ条件で測定し、改善幅の小さい結果も残している。

生データ・各サンプル・検証結果は [Performance-rendering-results.json](Performance-rendering-results.json)。削減率は `1 - 改善後の中央値 / 改善前の中央値`。今回の値はアプリのプロセスが消費したCPU時間で、モデルの生成速度、実機のGPU時間、電池消費の削減率ではない。

## 条件と描画結果

- 基準コード: `1d25c374c8496a46911a71c822d7d4bd5df45341`。別worktreeに同じ測定用テストだけを追加し、製品コードは変更していない。
- 改善後: この作業ツリーの変更。製品コードとテストのSHA-256を生データに記録した。
- Xcode 27.0 / 27A266a、iPhone 18 Pro Simulator / iOS 27.0 / 24A434。専用シミュレーターを使用。
- Apple M2、8コア、24GB、macOS 27.0.1 / 26A434。Mac上ではほかの作業・シミュレーターも稼働しており、ホスト全体を専有した測定ではない。
- 両側ともDebug + `SWIFT_OPTIMIZATION_LEVEL=-O`、コード署名なし、並列テスト無効。Release / 実機の性能を示す値ではない。
- 日本語・`ja_JP`、ライト表示、標準文字サイズ。描画リプレイのウィンドウは402 × 874 pt。
- 比較には、両側でアプリをアンインストールして保存データを初期化した正常終了の実行を使用した。描画は `before-render-clean` / `after-render-clean-2`、画面操作は `before-ui-clean` / `after-ui-clean`。プロファイラー付き、途中終了、以前のコード・入力条件での試行は混ぜていない。改善後の最初のclean描画実行はビルドと重なって失敗したため除外し、製品コードを固定して再実行した。ホスト上の他作業による影響は排除できていない。

実際の `ChatTimelineViewController`、SwiftUIの行、選択可能なUITextView、UICollectionViewのレイアウトを通した。履歴100行と応答1行を用意し、各シナリオを3回測った。750msの表示準備後、120入力を毎秒30回の絶対時刻で適用し、最後の確定表示・250msの待機までを測定した。処理が間に合わなくても入力を捨てず、全120件を適用する。全サンプルを採用し、最初の回も除外していない。

| 固定シナリオ | 改善前CPU秒 | 改善後CPU秒 | 削減率 |
| --- | ---: | ---: | ---: |
| 日本語24セクション、リンク・強調・コード付き本文 | 1.206512 | 1.142867 | 5.3% |
| 日本語100項目、リンク・強調・コード付きリスト | 6.755902 | 2.959650 | 56.2% |
| 長い回答を保持した思考テキスト120更新 | 1.553223 | 1.024404 | 34.0% |
| 履歴全体を往復する120段階のスクロール | 3.437017 | 2.586308 | 24.8% |
| 同じ画面で待機 | 0.274149 | 0.230494 | 15.9% |

リストの処理完了までの実時間は中央値 **7.350秒 → 4.411秒**。毎秒30入力に追いつかない場合の遅れも測定時間に含む。FPSやフレーム落ち率の測定ではない。通常本文のCPU時間は改善前1.160〜1.387秒、改善後0.848〜1.238秒と範囲が重なるため、5.3%という小さい差を安定した改善と断定しない。待機も0.260秒付近で範囲が重なる。各3回の中央値であり、統計的有意差や全ユースケースへの一般化は確認していない。

最終応答行の高さは全サンプルで一致した（本文・思考・スクロール・待機2451 pt、リスト3499 pt）。未表示行を含む全体のcontentSizeには推定高さが混ざるため、その値の一致を品質指標には使っていない。AIへの通信・Pi Runtimeのイベント受信・ツール実行は、この描画リプレイには含まない。

## 実アプリの画面操作

XCUITestでアプリを起動し、実際のタップ・スワイプ・キーボード入力を実行した。各3回、最初の回も含め、`XCTCPUMetric(application:)`、`XCTMemoryMetric`、`XCTClockMetric`を採取した。前後とも同じデモ用データを使い、API通信は行わない。

| 固定操作 | 改善前CPU秒 | 改善後CPU秒 | 削減率 | 操作実時間 前→後 |
| --- | ---: | ---: | ---: | ---: |
| 履歴200件を6スワイプ、履歴メニュー開閉2回、17文字入力・削除 | 3.844124 | 3.698844 | 3.8% | 23.064→22.976秒 |
| 設定の「会話」「表示」に遷移、各画面を上下スクロール | 2.151939 | 2.097222 | 2.5% | 11.339→11.379秒 |

この小さい差を確実な改善とは断定しない。履歴操作のCPU時間は改善前3.705〜5.014秒、改善後2.951〜3.920秒で範囲が重なる。物理メモリーの中央値も履歴操作160.849→162.619 MB、設定55.577→55.479 MBで、メモリー削減は示していない。操作実時間にはXCUITestの待機・ジェスチャー時間が含まれ、タップ応答レイテンシーではない。

改善後の操作を25秒Time Profilerで確認した。7,447サンプルのうち、Swiftランタイムの `swift_conformsToProtocolMaybeInstantiateSuperclasses` 自身が34.4%を占めた。起動・最初の画面構築も含む診断用トレースであり、測定区間だけの負荷比率や今回変更したコードの割合とは解釈しない。実アプリ全体に今回の描画改善と同率の効果があるという根拠は得られなかった。

## Instrumentsで確認した箇所と変更

Time Profilerを専用シミュレーターの実行中のアプリに接続した。改善前の25.666秒の記録には11,517件のCPUサンプルがあり、11.517秒相当のうち11.389秒相当がメインスレッドだった。`ChatTimelineCollectionCell.preferredLayoutAttributesFitting` を通るスタックが46.5%、選択テキストの更新が11.1%を占めた。これらは包含関係のある割合なので加算できない。

- `ChatTimelineCollectionView.swift`: 同じ内容・同じ幅の高さを再利用する。入力欄のフォーカス変更など、行IDも表示設定も変わらない更新ではスナップショット準備を省く。内容変更、幅変更、Dynamic Type・太字設定、非同期のMarkdown・HTML・GenUI表示では計測を無効化する。
- セルの最初のUIKitフィッティングは維持する。当初これも省くと高速スクロールで別の行の表示が残り、既存テストが失敗した。再利用時に必要な最初の処理を戻し、繰り返しのフィッティングだけを省いた。HTML行のサイズ通知が循環する問題も回帰テスト中に修正した。
- `NativeMarkdownView.swift`: 確定済みの同じブロックを再利用し、リストなどの追記時にはUITextViewの属性付き文字列の変更末尾だけを編集する。UTF-16位置、改行、選択範囲、リンク・装飾を保つ。削除・途中の書き換え・文字サイズ変更・空の見出しでは必要な範囲を作り直す。
- `ChatTimelineStore.swift`: 折り畳まれた思考本文だけの更新ではセルの再構築・高さ計測を省く。最新の思考本文は行に通知し、ボタンから開ける状態を保つ。ボタンの出現・消失、回答・ツールの変化、完了時は従来どおり更新する。

独自の高さ計測カウンターは本文・リストで約484回→122回、思考中は482回→4回になった。ただし、これはCPU・GPUの削減率ではない。表のCPU時間は同じ入力全体を実行したプロセスのuser + system時間で比較している。

改善後のTime Profilerでも、残る高さ計測、TextKitのレイアウト、スクロール時のテキストビュー生成を確認した。速くなったリストでは25秒内に進むシナリオ範囲も変わるため、前後のトレースのサンプル総量から削減率は計算していない。前後とも1表の入力元が不明というInstrumentsの警告が出たが、`time-profile` 表のスタックと対象プロセスの記録をエクスポートできた。

Pi Agentsの実行・通信・モデル解決経路は変更していない。入力の間引き、機能の削除、文字装飾や選択機能の簡略化による削減は行っていない。

## GPUで確認できた範囲

同じシミュレーター・描画リプレイにMetal System Traceを25秒ずつ接続した。最初の試行は `_lockKPerf: could not lock kperf` で失敗したため採用せず、ほかのトレースが終わってから新しい出力先 `before-metal-clean-2` / `after-metal-clean-2` へ再取得した。これらのプロファイラー付き実行のCPU時間は比較表に使っていない。

GPU実行イベントはMac上の他アプリ、WindowServer、複数シミュレーターのSimMetalHost / SimRenderServerにも帰属している。`gpu-counter-value` と `metal-gpu-counter-intervals` はいずれも空で、YamabikoChatプロセスだけのGPU実行時間・使用率は得られなかった。対象アプリに直接帰属するGPUイベントがないことを「GPU負荷ゼロ」とは解釈しない。シミュレーターの描画プロセスを含むイベントと、対象の同一入力区間の対応も確立できていないため、ホスト全体のイベント数や25秒の合計を前後の削減率に換算していない。

従って、**GPUの削減率、実機GPU・電池・発熱の改善は未検証**。CPUの高さ計測削減や、独自カウンターの80%超減少からGPU改善を推定することもしていない。再取得したtrace、テーブルXML、各テーブルの行数とハッシュを保存し、追検証できるようにした。

## 回帰検証と残る問題

- iOSユニット: 全件実行で、今回の初期セルフィッティングに起因する1件の失敗を修正した。改善前でも再現した下記4件を明示的に除外して最終コードを再実行し、**993件成功、7件スキップ、失敗0（計1000件）**で正常終了した。除外なしで全件成功したという意味ではない。
- 関連する描画・選択・キャッシュ・ストリーミング・セル再利用の102件も成功。追加テストで、Unicodeの選択範囲、属性の追記・削除・変更、空の見出し、幅・内容変更時の再計測、思考本文の最新状態を検証した。
- Pi Runtime 94件、GenUI DOM 66件、Pythonハーネス10件が成功。
- 前後のテスト用ビルド、`git diff --check`、測定スクリプトのPython構文確認が成功。

改善前でも同じ失敗を再現した4件は、この最適化では修正していない。

1. `ChatPresentationArchitectureTests/testToolSummaryAndAnswerNeverMoveTogetherDuringStreamingUpdates`: ツール表示の先頭描画位置のピクセル比較が不一致。
2. `GenUIReferenceToolTests/testGuidePreservesRuntimeContractsWithoutDumpingTheCatalog`: ガイドの期待文言4箇所が不一致。
3. `ModelsDevCatalogTests/testOnlyDedicatedProvidersRemainBuiltIn`: 組み込みプロバイダー一覧の期待値が不一致。
4. `PCCNativeToolsTests/testAllLocalToolSchemasCompileWithTheAppleSDK`: `ask_user_question` のスキーマが `pcc_tool_schema_unsupported`。

画面操作の2テストは前後とも成功した。最終画面のスクリーンショットを `.build/performance-20261018/after-ui-clean/attachments/` にエクスポートして確認し、履歴の本文と入力欄が表示され、入力した下書きが削除されていることを確認した。ストリーミングの描画テストは各側15シナリオを正常完了した。ただし、全画面・全Dynamic Type・iPad・音声入力・実APIのエンドツーエンド性能を網羅する検証ではない。

最終ユニットテストには `HtmlPreviewBrowser.swift` / `MermaidDiagramView.swift` のview更新中のstate変更、`SpeechRecognitionService.swift` の音声セッション同期APIをメインスレッドで実行する警告も残っている。今回の変更範囲外であり、アプリ全体に警告がないとは主張しない。音声経路は別途、権限と入出力を揃えた応答性の計測が必要。

次の最適化候補は、確定時と内容変更時に残るTextKit・ホスティングビューのサイズ計測、スクロールで新しく出現する選択テキストビューの生成である。最初のフィッティングを単に省くとセル再利用の表示が壊れることが確認できたため、80%を目指してその処理を削除することは採用していない。Pi経路・実ネットワーク・ツール実行・WebKit子プロセス・ホストの描画プロセスまで含む全体のCPU/GPU削減は、今回の測定からは算出できない。

## 再現と保存先

測定コードは [ChatRenderingPerformanceTests.swift](YamabikoTests/ChatRenderingPerformanceTests.swift)、[AppInteractionPerformanceTests.swift](YamabikoUITests/AppInteractionPerformanceTests.swift)、実行用CLIは [benchmark-rendering.py](scripts/benchmark-rendering.py)。通常のテストでは明示的に有効化しない限り測定をスキップする。

このワークスペースには `.build/performance-20261018/` 以下に前後のビルド、基準worktree、全測定ログ、`.xcresult`、Instrumentsの`.trace`、XMLエクスポートを保存した。これらはGitの管理対象外。共有用JSONはリポジトリ内に残している。

```sh
# リポジトリのルートで実行。既存の専用シミュレーターを使う例。
xcodebuild -project ios/YamabikoChat.xcodeproj -scheme YamabikoChat \
  -destination 'platform=iOS Simulator,id=20705736-EF0A-4657-BD21-48E13607AB75' \
  -derivedDataPath .build/performance-20261018/candidate-derived \
  -parallel-testing-enabled NO -jobs 4 \
  CODE_SIGNING_ALLOWED=NO SWIFT_OPTIMIZATION_LEVEL=-O build-for-testing

python3 ios/scripts/benchmark-rendering.py \
  --products "$PWD/.build/performance-20261018/candidate-derived/Build/Products" \
  --device 20705736-EF0A-4657-BD21-48E13607AB75 \
  --output "$PWD/.build/performance-rerun-after" --reset-app-data
```

`--kind ui` で画面操作を測る。`--trace cpu` または `--trace metal` は診断用であり、その実行の時間は前後比較から外す。出力先には新しいディレクトリを指定する。基準側は同じコマンドでproject・derivedData・productsを `.build/performance-20261018/baseline/ios/YamabikoChat.xcodeproj` と `baseline-derived` に変更する。

新しい環境で基準を作る場合は、上記の基準コミットを別worktreeに展開し、測定用のSwiftテスト2ファイルだけを同じ場所にコピーする。両側で同じ `ios/Vendor` を利用して依存関係を揃え、各 `ios/` で `xcodegen generate` 後に同じオプションでビルドする。製品コードを基準側へコピーしない。

トレースは例えば次の手順でスタックを集計できる。[summarize-rendering-trace.py](scripts/summarize-rendering-trace.py) は参照IDを解決し、包含スタックと自身のサンプルを分けて保存する。

```sh
xcrun xctrace export \
  --input .build/performance-20261018/after-cpu-profile/cpu.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  --output .build/performance-20261018/after-cpu-profile/time-profile.xml
python3 ios/scripts/summarize-rendering-trace.py \
  --input .build/performance-20261018/after-cpu-profile/time-profile.xml \
  --output .build/performance-20261018/after-cpu-profile/summary.json
```

GPUの空テーブルも次のように再エクスポートできる。`metal-gpu-intervals` はホストの他プロセスも含むため、単純な件数比較には使わない。

```sh
xcrun xctrace export \
  --input .build/performance-20261018/after-metal-clean-2/metal.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="gpu-counter-value"]' \
  --output .build/performance-20261018/after-metal-clean-2/gpu-counter-value-rerun.xml
```

最終ユニットテストの完全なコマンドは共有JSONの `validation.unit_command`、各比較のコマンドは `adopted_runs.*.command` に記録した。既存4件の除外も明示してある。測定テスト以外の製品コードを変更した場合は、既存のビルド製品を流用せず両側を再ビルドする。
