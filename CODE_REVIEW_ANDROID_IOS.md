# YamabikoChat コードレビュー統合レポート（Android + iOS）

- **調査日**: 2025年（セッション内レビュー）
- **対象**: Android `app/`（Kotlin, 約12,650行）／ iOS `ios/YamabikoChat/`（Swift, 約36,900行）
- **視点**: APIリクエスト層 / コンテキスト管理 / その他ハーネス（ストリーミング・ツール・Fusion・認証）に限定。低性能LLMが生成した疑いのある箇所を、ファイル:行番号・コード引用付きで特定。
- **方法**: 親エージェントによる中核ファイルの直接精読＋5×2＝10件の並列レビューエージェント（各領域を全ファイルread＋grep横断）。未使用関数・重複はgrepで実証したもののみ記載。
- **検証制約**: Web検索が認証エラーで利用不可のため、一部のAPIフィールド（OpenRouter `cache_control` / `reasoning_details` / iOS `session_id`）は「実在が疑わしい・要仕様確認」として留保扱い。

---

## スコア総括

| 領域 | Android | iOS |
|---|---|---|
| APIサービス層（Wire/SSE定義） | 7/10 | 7/10 |
| Provider/変換層（ApiRepository/ProviderGateway） | 5/10 | 7.5/10 |
| コンテキスト管理（ViewModel/履歴/自動会話） | 5.5/10 | 6.5/10 |
| ストリーミング/ツール層 | 6.5/10 | 7/10（Networking） |
| Fusion層 | 6/10 | 8/10 |
| その他ハーネス（auth/overlay/utils） | 7/10 | 7.5/10 |
| **全体** | **5.5〜6/10** | **7/10** |
| 低性能LLM由来の比率（体感） | 約3割 | 約2割 |

**総括**: Androidは「広く機能するが、コピペ重複・デッドコード・ハルシネーション臭いAPIフィールドが多数」の典型。iOSはAndroidの悪いコードを良いモデル/人手が書き直した結果で明らかに高品質。ただしiOSには「履歴切り詰めゼロ」というAndroidより深刻な欠陥がある。

---

# Part 1: Android（app/）

## 1-1. APIサービス層（data/remote/）

### 仕様ミス（高リスク）

- **[高][仕様ミス] `AnthropicCompatibleModels.kt:16,62` / `AnthropicCompatibleProvider.kt:118` — `output_config` のハルシネーション混入**
  `AnthropicMessageRequest.outputConfig`（`@SerialName("output_config")`）は**標準Anthropic Messages API（Claude）に存在しないフィールド**（Alibaba Qwen coding-plan拡張）。`buildRequest` は `reasoningEffort` 非空時に**全Anthropic互換エンドポイント**へこれを付与するため、実Claude宛で400系になるリスク。→ Alibaba専用に分離すべき。

- **[中][仕様ミス] `RequestConverter.kt:59-61,238-246` — fileData添付が静かに消失**
  `hasMultiModal` 判定は `fileData != null` も含めるが、`convertToMultiModalParts`（およびテキスト系変換）は `text`/`inlineData` のみ処理し **fileData（URL参照添付）をどこにも出力しない**。リクエスト送信時に添付が消える。→ 判定を `inlineData` 基準に揃えるか、fileData→URL画像パート変換を実装。

- **[中][仕様ミス] `RequestConverter.geminiToResponses`（405-488）— Codex（Responses API）変換でツール履歴が消失**
  `functionCall`/`functionResponse` パートを `else -> null` で全破棄。ツールを使った過去ターンをCodexへ送ると履歴から消える。

- **[中][仕様ミス・要検証] `OpenRouterRequest.kt:35-36,58-59` + `RequestConverter.kt:83-87,230-233` — トップレベル `cache_control`**
  Claudeモデルで常に `"cache_control":{"type":"ephemeral"}` がOpenAI互換 `chat/completions` のトップレベルに載る。`cache_control` はAnthropic形式のブロック内パラメータで、OpenAI互換APIにトップレベルで存在するか不明（**要仕様確認**）。

- **[低〜中][仕様ミス・要検証] `OpenRouterRequest.kt:183,242` — `reasoning_details` フィールド**
  `OpenRouterResponseMessage.reasoningDetails` / `ChatCompletionDelta.reasoningDetails` は実在が疑わしい（**要仕様確認**）。iOS側も同名をパースしておりクロスプラットフォームで意図的に使われている可能性はある。

- **[低][仕様] `OpenRouterMessage.kt:77` — toolロールに `name` フィールド**
  OpenAI互換APIのtoolメッセージに `name` は非標準（`tool_call_id` と `content` のみ）。多くのプロバイダは無視するが、厳格な実装では問題になり得る。

- **[低][仕様ミス] `RequestConverter.kt:196` — toolメッセージの `toolCallId` フォールバックが `"call-0-${response.name}"`**
  indexを常に0にするフォールバックで、同一メッセージ内の複数functionResponseでID衝突の可能性。

- **[中][仕様ミス] `OpenRouterModels.kt:132,137-138` vs `:21` — 型不統一**
  モデル一覧API側が `context_length`/`max_completion_tokens`/`max_prompt_tokens` を `Double` で受ける一方、同じスキーマの `OpenRouterModel.contextLength` は `Int`。API実値は整数なので `Double` 側は誤り（`coerceInputValues` との相性も悪い）。→ `Int` に統一。

### 重複・設計

- **[中][重複] `OpenRouterRequest.kt:20-63` — `OpenRouterRequest`/`OpenRouterMultiModalRequest` の約18フィールド完全複製**
  差分は `messages` の型のみ。→ 共通型に収束可能。

- **[中][重複] `OpenRouterRequest.kt:71-92` — `OpenRouterMessage`/`OpenRouterMultiModalMessage` 複製**
  `content` の型（`String?` vs `List<OpenRouterContentPart>?`）のみ差異。

- **[中][デッドコード] `RetrofitClient.kt:82-89` — `openAiStaticInstance` 参照0件**
  grepで定義1件のみ。実利用は `makeOpenAiInstance(baseUrl)` 動的生成。→ 削除。

- **[低][デッドコード] `RetrofitClient.kt:114-116` — `@Deprecated instance` 互換エイリアス**
  「互換性のため」の残骸。

- **[低][設計] `RetrofitClient.kt:31-41` — 全インスタンスで `readTimeout(0)` 無期限を共用**
  長時間生成への対応としては意図的で妥当だが、`LiteLlmPricingApiService`（raw.githubusercontent.com）にも無期限が適用される。価格取得が無限ハングし得る。→ クライアント分離を検討。

- **[低][設計] `OpenRouterApiService.kt:5` — `import retrofit2.http.*` ワイルドカードのみ**
  他サービスと不統一（LLM生成コードの典型）。

- **[低][LLM臭] `OpenRouterModels.kt:67-72` — `SimpleModel.promptPrice` 後方互換getter冷え残り**
  per-1Mとper-1tokenの二重表記。実UIは全てperMillionで、per-token側はテストのみ参照。

- **[低][LLM臭] `GenerateContentRequest.kt:68-75` — `ThinkingConfig` 多目的クラス**
  Gemini/OpenAI reasoning/Z.ai思考/Codexを1クラスに詰め込み、enum化せず自由文字列で判定（`ZaiProvider.kt:19-34` が `"enabled"/"disabled"` へ分岐）。

### 堅牢性

- **[中][堅牢性] `OpenAIHostedSkillsClient.kt:86-107` — `@Synchronized` 下で同期ネットワークI/O**
  コンテナ取得が全ホストスキル実行を直列化。ロック外で取得し、キャッシュ書込のみロックすべき。

- **[低〜中][堅牢性] `OpenAIHostedSkillsClient.kt:236-277` — `wrapHostedStream` の二重出力方式**
  生SSE行をそのままPiped Streamへ流しつつ、別途 `data:` 行を再パースして合成イベントを追記。`[DONE]` は破棄するがSSE境界の正規化が暗黙的。

- **[低][LLM臭] `OpenRouterModels.kt:178,180,286-289` ほか — 冗長コメント**
  プロバイダ差異を1コメントで吸収する書き方。

### 良い点
- HTTPメソッド/パス/認証ヘッダー（`x-api-key`+`anthropic-version`+`text/event-stream`、`Bearer`）は各実仕様と一致。`@Streaming` + `Response<ResponseBody>`、エラー時 `Response.error(code, body)` でHTTPボディ保持は妥当。`!!` 乱用はほぼ無し。

## 1-2. Provider/変換層（data/api/ + data/remote/ Provider群）

### 最重要

- **[高][重複] `ApiRepository.kt:624-926` — provider分岐とAPIキー解決が5〜6重コピペ**
  `generateContent`(446) / `streamGenerateContent`(536) / `generateDualContent`(624, A/Bで2ブロック) / `streamDualContent`(776, A/Bで2ブロック) / `generateAutoConversationResponse`(928) が、同じ「キー解決→`when(provider)`分岐」を約30行ずつ繰り返す。`resolveApiContext`(106-189) を**dual系は迂回して独自実装**しており既にドリフト：
  - dual系は models.dev 対応・Hosted Skills・`sessionId` を欠落（`generateContent` はCodexに `sessionId` を渡すのにdualは渡さない）
  - プロバイダ追加のたびに5箇所同期が必要。→ `ApiContext` ベースに一本化すれば約400行削減。

- **[高][仕様ミス] 自動会話のrole整合性違反 — `AutoConversationManager.kt:463-495`**
  `buildConversationHistory` は「現在話す側の視点」で自分=model/相手=userに置換するが、先頭の共有初期 "USER" の直後に相手モデルが居ると **`user,user,...` と同role連続で始まる**（例: B話者・履歴 USER→A1 はB視点で `user,user,model,...`）。Anthropicや厳格なOpenAI互換は連続同roleをエラーにする。A視点は交互になるため発現が分かりにくい。

- **[中][仕様ミス] `RequestConverter.kt:59-61,238-246` — fileData消失**（1-1に同じ。変換経路全体の問題）

- **[中][設計] `ApiRepository.kt:624-635,776-788` — dual系の二重構成パス**
  models.dev 検出時だけ `generateContent`/`streamGenerateContent` へ再帰委譲し、通常時は自前のキー解決。挙動の分岐が増える。

- **[中][堅牢性] `ApiRepository.kt:773,925` — dual系の同時401リトライでトークン更新が競合**
  `deferredA`/`deferredB` が並行して `callCodexAuthWithRetry` → 両方401で `refreshCodexAuthToken(force=true)` を呼ぶと使い捨てrefresh tokenを上書きし合う。`Mutex`/タイムスタンプ排他が必要。

- **[低][パフォーマンス] `OpenCodeGoProvider.kt:66-80` — prompt cache key のseedが内容の一部のみ**
  `firstMessage` のtext/roleとsystemのみでSHA-256を組み、以降の会話を無視。会話が進んでも同一キーに畳まれ、誤キャッシュヒットの可能性（断言は留保）。`MessageDigest` を毎リクエスト初期化。

### デッドコード（grepで確定）

- **[中] `CodexResponsesProvider.kt:414-514` — `parseResponsesSseToGemini` 約300行が無呼び出し**
  SSE処理は呼び出し側（UI層）が生 `ResponseBody` を読む設計のため消し忘れ。`incrementalDelta` 等の累積ロジックも不要。

- **[中] `RequestConverter.kt:365,384` — `openRouterStreamToGemini` / `openRouterStreamResponseToGemini` 無呼び出し**
  「とりあえず変換関数を生やした」痕跡。

- **[中] `OpenAiProvider.kt:25-30` — 常に500を返すだけのdead override**
  `ApiProvider` interfaceを満たすためだけに存在し、呼ばれると必ず失敗。interface設計（baseUrl可変対応）が悪い。

- **[中] `ProviderCatalog.kt:78-82` — `remapRemovedProvider` 無呼び出し**
  本命は `Settings.remapRemovedProviders()`（Settings.kt:869-877）で二重実装。`ApiRepository.resolveApiContext:116` の `knownProviderIds + setOf("GEMINI_AUTH","QWEN_CODE")` と齟齬。

### LLM臭・設計

- **[低][LLM臭] `ApiRepository.kt` — デフォルトURL文字列が4箇所以上で重複**（`settings?.openAiBaseUrl ?: "https://api.openai.com/v1/"` 等）
- **[低][LLM臭] `ApiRepository.kt:158,452,459` / `RequestConverter.kt:33,37,56` / `OpenRouterProvider.kt:47,51,56,108` — 運用コードに残る `Log.d`**
- **[低][設計] `ApiRepository.kt:204-229` — `modelsDevBaseUrl` のハードコードカタログ + `removeSuffix("/chat/completions")` ハック**
- **[低][堅牢性] `ApiRepository.kt:983` — `apiKeyResult as ApiKeyResult.Success` の unchecked cast**（直前の `is` チェックはあるが書き方として脆い）
- **[低][設計] `RequestConverter.kt:429` — `val text = part.text` の冗長ローカル**（nullチェック済みプロパティの再代入）

### 良い点
- `resolveApiContext` の設計（ApiContext sealed結果、missing key は401レスポンス化）は方向性として正しい。`callCodexAuthWithRetry`/`callSuperGrokAuthWithRetry` の401再試行は1回に限定され安全側。

## 1-3. コンテキスト管理（ChatViewModel / ConversationHistoryBuilder / AutoConversation）

### 最重要

- **[高][重複/デッドコード] `ChatViewModel.kt:948-993` と `998-1043` — 自動会話統合の完全コピペ＋3重実装**
  `updateAutoConversationProgress` と `integrateAutoConversationResults` は約40行同一（speakerName決定→displayContent→**[$speakerName]**構築→重複判定→insertMessage→addedCount++）。さらに `onNewMessage` コールバック（203-218）で同じ挿入ロジックが**3回目**として存在。**`updateAutoConversationProgress` は呼び出し0件のデッドコード**。

- **[高][堅牢性] `AutoConversationManager.kt:233` — `maxTurns<=0` を「無制限」として無限ループになり得る**
  終了シグナル頼み。`maxTurns` に下限（max(1,..)）が必要。

- **[高][堅牢性] `ChatViewModel.kt:898` — `delay(500) // 初期化を待つ` レースハック**
  `observeAutoConversation()` の開始を500ms待つ。`combine(currentConversationId, isRunning)` で素直に観測すべき。

- **[中][堅牢性] `AutoConversationManager.kt:91-129` — `stopConversation` の複雑なキャンセル分岐**
  `withContext(NonCancellable)` 内で `currentJob == callerJob` を判定して自分を殺す/殺さないを分岐。END_SIGNAL/MAX_TURNS（ループ内から呼ぶ）とユーザー停止で経路が混在し脆い。「フラグをfalseにする→ループ側が終了処理」+「外部からのJobキャンセル」の2点に単純化可能。

- **[中][堅牢性] `startAutoConversation`/`stopConversation` のタイミング競合**
  guard（`_isRunning`）が抜けた直後に停止されると開始ループが走り続け得る。単一の「running/stopping」状態機械が必要。

- **[中][デッドコード] `ChatViewModel.kt:454-473` `createSecretConversation` / `:504-506` `getFullMessageById` — Android側呼び出し0件**
- **[中][デッドコード] `AutoConversationManager.kt:36` — `MAX_RETRY_ATTEMPTS = 3` 宣言のみ未使用**（リトライ実装なし・APIエラーで即終了）
- **[中][デッドコード] `AutoConversationManager.kt:134-194` — `pauseConversation`/`resumeConversation` 呼び出し0件**（`continueAutoConversationLoop` もデッド）
- **[中][LLM臭] `ChatViewModel.kt:575-664` — `applyPreset` の設定フィールド爆発**
  プロバイダ別 private settings（`superGrokReasoningEnabled`/`codexReasoningEnabled`/`openRouterThinkingEnabled`...）をLLMが足し続けた形。`baseThinkingUpdate` は2分岐でしか使われない。

### 履歴構築

- **[中][仕様ミス] `ConversationHistoryBuilder.kt:35-37,208` — 履歴は件数20で `takeLast`、トークン非考慮**
  トークン概算・system prompt考慮・最大トークン超過時の処理が無い。巨大な単一メッセージ/添付で簡単にオーバーフロー。また `takeLast(20)` 後の先頭が `model` ロールになり得、厳格エンドポイントで先頭role違反の可能性。

- **[中][重複] `ConversationHistoryBuilder.kt` — 添付解決が4重複**
  `resolveStoredMessageParts`/`resolveDualUserMessageParts`/`resolveDualModelParts`/`buildNewMessageParts` は同一のキャッシュ+URI解決ロジック。

- **[中][設計] `ConversationHistoryBuilder.kt:22-26,192-200` — 二重キャッシュ**
  インスタンス `attachmentCache`（LinkedHashMap+synchronized）とセッションローカル `sessionCache` が意味的に重複。`withContext(ioDispatcher)` 内なので `synchronized` 自体も不要。

- **[低][設計] 表示用textと履歴用raw textの混在** — 自動会話は `**[$speakerName]**\n\n$displayContent`（thinkingブロック含む）をそのまま `ChatMessage.text` として保存し、それがそのままモデルへ再送される。`AutoConversationFormatter` の「raw textはLLMに返す」意図と矛盾。

### その他

- **[中][LLM臭] `ChatViewModel.kt:310-321` — 状態の二重管理**
  `_isAutoConversationRunning`/`_autoConversationStatus`（VM）と `_isRunning`（Manager）を並行監視。文字列ベースのステータスプロトコル（`contains("停止")`）も脆弱。

- **[低][LLM臭] `AutoConversationTrigger.kt:4-7,33-42` — テスト回避ハック**
  `testPatterns`（"a","t","1","2"...）と `it.code > 0x3000` で非ASCII全部を日本語扱い。**実質5文字以上ならほぼ常に発火**し、判定が機能していない。

- **[低][堅牢性] ViewModel内のDBアクセス不徹底** — `repository.getMessagesForConversation(id).first()` 等がメインスレッドでFlow collectされる箇所あり（Room自体はバックグラウンドで動くため致命的ではない）。

- **[低][設計] `syncNewChatWithSettingsIfEmpty` の条件が難解** — `shouldSync` のネスト条件は意図が読みにくい。

### 良い点
- `sendMessage` の分岐（Fusion/Dual/自動会話/通常）はCoordinator委譲で整理されている。自動会話の終了シグナル正規表現・`NonCancellable` での状態更新は丁寧。`init` の `collectLatest` によるメッセージ監視は正しい。

## 1-4. ストリーミング/ツール層（ui/chat/logic/ + data/tools/）

### 最重要

- **[高][重複] `ChatResponseStreamer.kt` と `StreamChunkConsumer.kt` が実質コピペ（約400行）**
  `parseCodexResponsesDelta`/`parseCodexResponsesUsage`、`parseAnthropicCompatibleDelta`、`looksLikeCompleteJsonEvent`、`extractOutputTextFromItem`、`parseGeminiParts`（部分）、SSE行読み取りループが同一実装。`consumeStream` を呼ぶのは `DualChatResponder` と `ChatRepository` のみ。→ 単一SSEパーサ+プロバイダ分岐に統合すべき。

- **[中][重複] `incrementalDelta` が4箇所に複製**
  `ChatResponseStreamer.kt:746` / `StreamChunkConsumer.kt:245` / `ToolModels.kt:248` / `CodexResponsesProvider.kt:424`。`ToolModels.kt:246` のコメントに「and Android ChatResponseStreamer.incrementalDelta」と**重複を認識したまま放置**した自己言及あり。

- **[中][堅牢性] `incrementalDelta` のフォールバックが危険**
  接頭辞不一致時に `incoming` 全量をデルタとして返す（:746-753）。プロバイダが断片を再送すると**テキストが重複**する。→ 接頭辞一致しない場合は `""` を返し欠落を選ぶ、または一致部分のみ消費。

- **[中][仕様ミス] ストリーミング時の `delta.tool_calls` 完全無視**
  `ChatCompletionDelta.tool_calls`（OpenRouterRequest.kt:244）が定義されているのに両コンシューマは `content`/`reasoning` しか読まない。ツール呼び出しストリーミングするモデルの tool_calls が静かに失われる（現在はクライアントツール制御を非ストリーミングに寄せているため実害は限定的）。

- **[中][デッドコード] `ToolModels.kt:37-88` — `ToolCallAccumulator`/`ToolCallDelta` 完全未使用**
  上記 `delta.tool_calls` 無視と合わせ「ストリーミングtool_calls未対応の残骸」。使うか削除するか決めるべき。

### 堅牢性・パフォーマンス

- **[低][パフォーマンス] 巨大文字列の `+=`（O(n²)）** — `ChatResponseStreamer.kt:427,433` / `StreamChunkConsumer.kt:138,148`。`StringBuilder` 化を。
- **[低][堅牢性] SSEバッファ結合のヒューリスティック** — 「pendingが完全JSONならflush、そうでなければ改行で継ぎ足す」方式で、1チャンクに複数JSONが混在するケースの対応が不完全（実害は限定的）。
- **[中][セキュリティ] SSRFガードのTOCTOU** — `SearchModels.kt:108-128` の `validatePublicHTTPURL` はDNS解決して判定するが、実際のOkHttp接続は**別途DNS再解決**される。DNSリバインディングでlocalhostに届く可能性。解決済み `InetAddress` を `dns()` で固定すべき。`resolvedAddresses`(140-146) はDNS一時障害を即 `InvalidUrl` 例外にする。
- **[中][堅牢性] `DuckDuckGoHTMLEngine.parseResults`（18-61）— 正規表現によるHTMLパース**
  `result__a`/`result-link`/`rel=nofollow` を正規表現で頼み、`HTMLTextExtractor` もタグ除去を複数パスの正規表現で実施。DDGのDOM変更に脆弱（Liteフォールバックの二段構えは堅実）。

### デッドコード・設計

- **[低][デッドコード] `DualChatResponder.streamResponses`(136-238) 呼び出し0件**（`generateResponses` が実経路）
- **[低][重複] ツール⇄メッセージ変換の3重実装** — `data/tools/ClientToolCallingRunner.kt`（contentsToToolMessages/toolMessagesToContents）、`data/fusion/ClientToolCallingRunner.kt`（toContents/toToolTurnResponse）、`ToolCallingOrchestrator`。
- **[低][LLM臭] `TokenUsageSnapshot.mergedUsage`（ToolCallingOrchestrator:146-163）** — ラウンド毎にusageを継ぎ足し `response.copy(usage=combinedUsage)` で上書き。意図は分かるが伝わりにくい。

### 良い点
- `maxRounds=15`＋`seenCalls` 重複抑制＋ループ冒頭 `ensureActive()` の無限ループ対策は妥当。ラウンド上限到達時もレスポンスを残して正常終了。`CancellationException` の明示的再throw（WebSearchTool:77, FetchUrlTool:100）も丁寧。単一ストリーマーはチャンク毎にStateFlow更新のみ・DB書込みは完了時1回の分離が正しい。

## 1-5. Fusion層（data/fusion/）

### 最重要

- **[高][重複/LLM臭] 同名クラス衝突 — `data/fusion/ClientToolCallingRunner.kt:23`（fun interface）と `data/tools/ClientToolCallingRunner.kt:17`（具象class）**
  `FusionService.kt:23` は同一パッケージ優先でFusion側に解決されるが、`ChatInteractionCoordinator.kt:40` と `DualChatResponder.kt:27` はtools側を参照。import付け忘れで意図と異なる型が解決されるリスク。さらに `DefaultClientToolCallingRunner.toToolTurnResponse()`（:111-135）とトップレベル `toFusionInvokeResult()`（:157-182）はほぼ同一のテキスト結合+ツール抽出。→ Fusion側を改名し共通抽出。

- **[高][LLM臭/デッドコード] `FusionService.kt:227-235` — if/elseの両分岐が `null` で、算出した `mergedSystem` が未使用**
  ```kotlin
  val mergedSystem = FusionOrchestrator.mergeSystemPrompts(
      if (phase == FusionPhase.panel || phase == FusionPhase.fallback) { null } else { null },
      systemPrompt
  )
  ```
  丸ごと削除可能。作者の「conversation systemを合成したい」意図と実装が矛盾したハルシネーション的残骸。

- **[高][仕様ミス] phase別システムプロンプト適用が三者三様**
  panel: `request.systemPrompt`（会話システム）を完全無視。fallback（FusionOrchestrator.kt:342）: 会話システムのみ。synthesizer（:110-127）: `mergeSystemPrompts` で両方。同一実行内で仕様がバラバラ。229行コメントも実装と辻褄が合わない。

### 中重要度

- **[中][仕様ミス] judge repair成功時のlatency集計漏れ（FusionOrchestrator.kt:279-306）**
  `latencyMs = repairLatency`（repairのみ）なのに `cost` は初回+repairを合算。初回呼び出し分のlatencyが trace の totalLatencyMs から欠落。

- **[中][仕様ミス] `fallbackModel` がパネル全滅時に使われない**
  :73-75 で成功0件なら `throw FusionError.AllPanelsFailed`。`fallbackModel` は再帰深度上限時の `runRecursionFallback` でのみ使用。しかも `FusionService.runFusion` はこの例外を捕捉せず（捕捉は合成段のtry/catchのみ）**UIへ素通し**され、ハンドリングが無いとクラッシュ/無応答になり得る。

- **[中][重複] `applySkillContext` 実装複製** — `FusionService.kt:253-276` と `ChatInteractionCoordinator.kt:648` が完全同一。

- **[中][設計] `SynthesisPhase` の二重 system_instruction 設定（FusionOrchestrator.kt:112-127）**
  `buildRequest(synthSystemPrompt)` が設定→直後 `.copy(system_instruction=mergedSystem)` で上書き破棄。`buildRequest` 側の設定が無駄。

### 低重要度

- **[低][LLM臭] 未使用フィールド群** — `FusionTypes.kt:140` `PanelModelConfig.timeoutMs`、`:157` `FusionRequest.timeoutMs`、`FusionPresetLoader.kt:15` `timeoutMs`（「legacy互換」コメント付きで未使用）、`PanelResult.finishReason`（常にnull代入）。
- **[低][堅牢性] `FusionJudgeParser.kt:21-35` — `lastIndexOf('}')` による手動JSON抽出**
  ネスト`{}`や末尾文言で誤括り。パース失敗→repair呼び出しで二重コスト。静的フォールバックは機能。
- **[低][LLM臭] `FusionPrompts.kt:151-159` — `synthesizerUserPromptWithoutJudge` は薄いラッパー**
  `synthesizerUserPrompt(judgeAnalysis=null, judgeParseFailed=true)` を呼ぶだけ。呼び分けは `judgeAnalysis != null` に依存するので冗長。
- **[低][設計] `FusionService.buildGenerateRequest` がpublic露出** — DI経由で使われる契約が曖昧。

### 良い点
- panel→judge→synthesizer+fallbackの状態機械、trace記録、progress通知の分離は良好。並列パネル実行は `coroutineScope`+`Mutex` で `chipPanels` 更新を直列化し、`.awaitAll()` で親スコープにキャンセル伝播。スレッド安全性は確保。

## 1-6. その他ハーネス（auth / overlay / actions / utils）

- **[中][重複] `CodexAuthRepository.kt` — 「refresh→再交換」ブロックが `login()`(108-124) と `getApiKey()`(176-193) でコピペ**
- **[低][LLM臭] `OverlayService.kt:38-39` — 未使用import（`Card`/`CardDefaults`、`clip`）**
- **[低][LLM臭] `CodexSessionIdUtils.kt` — 7行で `UUID.randomUUID()` をラップするだけの過剰抽象**
- **[低][設計] `MiniMaxUtils.kt` / `ToolingUtils.kt` / `DiagnosticsLogger.kt` / `ProcessTextActivity.kt` — 問題なし（良好）**
- **良い点**: `CodexAuthRepository` はPKCE・state検証・DNSフォールバック（DnsOverHttps 2系統）・`NonCancellable`・ログサニタイズが丁寧。`ProcessTextActivity` のPROCESS_TEXT検証・4000文字トランケーションも妥当。

---

# Part 2: iOS（ios/YamabikoChat/）

## 2-1. Networking層（Networking/）

### 最重要

- **[高][重複] `AnthropicCompatibleProviderClient.swift:130-222` — `ProviderSSEStreamRunner` が存在するのにSSEポンプループを丸ごと再実装**
  fullText/fullReasoning/latestUsage/toolCallAccumulator、`[DONE]`→`.completed`、インライン`.completed`マージ、EOF finishを自前実装。同型ループは `CodexProviderClient.swift:52-130`（usage判定を`[DONE]`の前に置く等のバリエーション混在）にもあり**合計3コピー**（runner+Anthropic+Codex）。OpenAI/OpenCodeGo/SuperGrokはrunnerを正しく使用。3者でusageのはぎ取り順・reasoningSummaryの扱いが微妙にズレており修正取りこぼしの温床。

- **[高][重複] `AnthropicCompatibleProviderClient.swift:456-559` — usageパースと `intValue(in:keys:)` ヘルパーを完全複製**
  `OpenAICompatibleUsageParser.parse` / `OpenAICompatibleProviderClient.swift:531-552` の同名ヘルパーとほぼ同一（`sortedKeys` も重複）。収束値だけ `.normalized()` vs `.normalizedNonEmpty()` と微妙に食い違う。

### 中重要度

- **[中][重複] `OpenAICompatibleProviderClient.swift:554-572` — `readStreamErrorBody` が `URLSessionHTTPClient.readResponseBody`(HTTPClient.swift:89-104) のほぼ複製**（16KBキャップ付き読み出し）
- **[中][堅牢性/LLM臭] `SSEPayloadAssembler.swift:12-19` — ブランクライン分岐の非直感的挙動**
  単一`data:`行=完全JSONのとき空行でもflushしない（defer）。喪失はしないがイベントが1つ遅延・順序依存に。`looksLikeCompleteJSONEvent`(48-56) はトップレベルキー文字列（`choices`/`type`/`candidates`）の存在で完全性を推定する脆弱ヒューリスティック（usage-only chunkや未知typeで mid-stream auto-flushが効かない）。
- **[中][堅牢性] `try? JSONSerialization...else continue` で不正JSONを黙殺**
  `ProviderSSEStreamRunner.swift:53` / `AnthropicCompatibleProviderClient.swift:176` / Codex / OpenCodeGo。診断ログなしでプロトコル逸脱が静かに捨てられ、プロバイダ改変で応答欠落に化ける。→ `DiagnosticsLogger` 記録 or 連続N回で `.parseFailure`。

### 低重要度

- **[低][仕様] `OpenAICompatibleWire.swift:31,95` — `reasoning_content` をassistantに限り全OpenAI互換へ送信**
  DeepSeek/Qwen系固有フィールド。Azure/OpenAI直結では未知フィールドとして無視/拒否の可能性。→ metadataからの条件付き注入に。
- **[低][設計] `ProviderRequest.swift:49,78` — `ProviderRequestMessage.id = UUID()` がCodable+Equatableに混在**
  デコードのたびに新品になり、同一JSONを2回decodeしたメッセージがEquatable不一致（永続化round-tripで同一性が壊れる）。→ CodingKeys/Equatableからid除外。
- **[低][パフォーマンス] `HTTPClient.swift` — `.shared` 直使いで timeoutInterval nil時はURLSession既定60秒**
  長時間reasoningのSSEでfirst/periodic byteが60秒空くと不安定。→ stream用専用セッション（長めtimeout/`waitsForConnectivity`）を。※Androidは `readTimeout(0)` 無期限を意図設定しており、この点はAndroidが正しい。

### 良い点
- `SSEPayloadAssembler` が一元化されAndroidの2ファイル400行コピペを解消。`OpenAICompatibleStreamParser` は**`delta.tool_calls` を実際にパース**（Androidは無視）。`ProviderSSEStreamRunner.pump` のOptions注入設計は拡張性が高い。`[DONE]`・複数JSON混在・エスケープは概ね正しい。

## 2-2. Provider層（ProviderGateway / ProviderClients / Resolver）

### 最重要

- **[高][仕様ミス] `ProviderGateway.swift:423-454` — OpenCodeGoの「stream無テキスト→非stream再試行」で `.completed` が二重送出**
  stream内ループ（404-421）が受信イベントをそのまま `continuation.yield` するため、`ProviderSSEStreamRunner.pump` の正常終了`.completed`が既に届く。その後 `!streamHadAnswerText` なら `client.generate` → **2回目の** `.completed` を441-453で送出。`ChatStreamingPersistence.consumeStreamEvent`(200-210) は `.completed` をマージする（`fullText.isEmpty` のときのみ `response.text` を採用）ため全損は回避されるが、「final」スナップショット送出後に再更新される順序問題が残る。→ `didEmitCompleted` フラグで未送出時のみ送出に。

- **[高][堅牢性] `ProviderGateway.swift:227,490` — `try? await Task.sleep` がキャンセルを握りつぶす**
  transient Gemini 500リトライの待機で `CancellationError` が握りつぶされリトライループが続行。→ `do { try await Task.sleep(...) } catch is CancellationError { throw CancellationError() }`。

### 中重要度

- **[中][仕様ミス・要検証] `OpenAICompatibleProviderClient.swift:19-20,34,316-324` — `session_id` が `promptCacheKey` と同一メタデータキーから充填**
  `sessionId(for:)` も `promptCacheKey(for:)` も `request.metadata["promptCacheKey"]` を返し、OpenRouter/OpenAI宛ボディに `prompt_cache_key` と `session_id` の両方が同一会話IDで送られる。`session_id` は標準OpenRouterパラメータに存在しない疑いが高い（**要仕様確認**）。最低でもキー分離を。
- **[中][設計] `ProviderRequestSettingsResolver.swift:248-320` — alibabaCodingPlan（Anthropic互換）でthinkingが一切未設定**
  `thinkingConfigForProvider` の分岐は OPENROUTER/CODEX_AUTH/SUPERGROK/GEMINI のみで、ALIBABAは `default: return nil`。`AnthropicCompatibleProviderClient` の `buildThinking`(358-364) と `AnthropicOutputConfig`(21-23) は実質動かない（reasoning実装がデッド機能化）。

### 低重要度

- **[低][LLM臭] `GeminiProviderClient.swift:232-233` — `if streamFinished { return }` が2回連続（コピペ）**
- **[低][デッドコード] `OpenAICompatibleProviderClient.swift:531-552` — 未使用 `intValue` ヘルパー2種**（usageパースは `OpenAICompatibleUsageParser` に委譲済み）
- **[低][デッドコード] `ProviderClient.swift:21-53` — プロトコル拡張の既定 `stream`（空白分割の擬似ストリーム）が実質未使用**
  全8実装型が自前実装のため到達不能。誤用防止のため削除または `fatalError` 化を。
- **[低][デッドコード] `ProviderRequestSettingsResolver.swift:240` — `geminiFunctionDeclarations` メタデータが未消費**
  `request.tools` の `function_declarations` tool（140-143）が正しい経路で、metadata（240）は誰も読まない重複。
- **[低][設計] `ProviderGateway.swift:804-813` — `knownModelsDevBaseURL` のハードコードカタログ**（Android `modelsDevBaseUrl` と同一の二重管理）

### 良い点
- Geminiキー/モデルローテーション（`GeminiRotationCandidate` + `GeminiCredentialOverride` でKeychainキーだけを差し替える巧妙な設計、認証失敗時は同キー残りモデルをスキップ、in-memoryで前回成功位置から再開）は高品質。
- transient Gemini 500リトライの「`yieldedAnyEventThisAttempt` が無い場合のみ再試行」という部分出力重複防止の配慮、`withConversationMetrics`/`recordLLMMetric` によるメトリクス記録、`ProviderClientParityTests`/`ProviderGatewayTests` のテスト網は優秀。

## 2-3. コンテキスト管理（ChatViewModel / ChatRepository / 自動会話）

### 最重要

- **[高][堅牢性/設計] `ChatRepository.swift` — 全履歴を無制限送信。トークン/件数ベースの切り詰めが存在しない**
  `buildProviderRequest`(616)・`buildSingleTurnRequest`(2270) は `conversations.fetchProviderHistory(conversationId:)`（`ConversationRepository.swift:711`）で**全メッセージを全件取得**し `flatMap(\.providerMessages)` で全履歴をプロンプトに流す。コードベース全体で切り詰めが皆無（grepで`dropLast`/`suffix`/トークン切り詰めがリクエスト経路にゼロ）。`ChatViewModel.resolvedContextLimit`(1136-1144) は**表示（contextUsageLabel）専用**で実トリミングに未接続。長会話でコンテキストウィンドウ超過・コスト・遅延が無制限に増大。→ 末尾N件＋トークン概算の切り詰めを導入し `resolvedContextLimit` を実装に接続。

- **[高][堅牢性] `ChatRepository.swift:1942` — 自動会話の `maxTurns=0` 時に絶対上限なし**
  終了条件は maxTurns突破・終了シグナル/正規表現・apiError・`checkCancellation()` のみ。UIは `autoMaxTurns=0`＝無制限を許可（AutoConversationSettingsSection:95）。モデルが終了を宣言しないと2秒遅延+1APIコールのループが実質永久に回る。→ 絶対ターン上限 or 無進行タイムアウト。

- **[中][仕様ミス・要確認] `ChatRepository.buildDualHistory`(2388-2450) — 相手モデルの出力を履歴から完全に省略**
  side Aの履歴は「通常履歴+ユーザー発言+**A自身の過去応答のみ**」。**Bの発言は一切含まれない**。Androidは相手の発言を `user` ロールで注入しており、**クロスプラットフォームで挙動が大きく異なる**（AGENTS.mdのparity方針に照らし、意図的でない可能性が高い。製品仕様として要確認）。

### 中重要度

- **[中][デッドコード] `ChatViewModel.swift:18,112` — `messageSummaries` 未使用**
  代入2件のみで一度も読まれない。常時GRDB ValueObservationの純コスト。→ 状態と購読を削除。
- **[中][デッドコード] `ChatRepository.swift:2459-2465` — `decodeArray` 定義のみ未使用**（使用実装は `ConversationRepository:1316`）
- **[中][堅牢性] `ChatViewModel.swift:281-393,469-494` — fire-and-forgetの `Task {}` が保持されずキャンセル不能**
  通常送信・再生成にUIからの停止経路なし。自動会話は `autoConversationTask` で管理可能なのに非対称。VM破棄時の `self` 強保持の可能性。
- **[中][堅牢性] `ChatViewModel.swift:281` — `sendMessage` に再入防止ガードなし**（UIの `.disabled(isSending)` 依存のみ。二重呼び出しでユーザーメッセージ重複挿入の可能性）
- **[中][重複] `ChatViewModel.swift:727-738` vs `769-781` — Fusion表示ラベルのほぼ逐語コピー**
  `workspaceSubtitleLabel` と `composerContextLabel` のFusion分岐が同一成形コードを重複。

### 低重要度

- **[低][LLM臭] `ChatViewModel.swift:547-596` — `enablingDual`/`enablingFusion`/`enablingAuto` は冗長変数**（`updated.isXModeEnabled` と常に同値）
- **[低][堅牢性] `ChatRepository.swift:1412-1413` — `_ = try settingsForNewConversation()` の副作用依存**
  正規化結果を破棄しつつ副作用だけ期待。ローカル `settings`（1393でload済み）に正規化が反映されず、リクエスト構築は旧値・会話作成は新値の不整合が起き得る。
- **[低][並列性] `ChatRepository.swift:946-956` — デュアルの `async let` 両側が同一dbQueueに並行書き込み**（GRDBが直列化するのでクラッシュはしない）
- **[低][パフォーマンス] `ChatViewModel.swift:322,376,481` — ストリームΔ毎に `Task { @MainActor }` 生成**
  永続化は100msで絞られているがUIへのhopは全Δで発生。`handleStreamingSnapshot` のflush Task管理(:424)は適切。
- **[低][設計] `ChatViewModel.swift:372` — `autoConversationStatus` を通常チャットの「推論中...」表示に流用**（役割の混線）

### 良い点
- `SystemPromptComposer.composeForAPI` の単一実装・3箇所再利用、`mergeForAPI` のFusion利用は妥当。自動会話のロール変換（`buildAutoConversationHistory`）と `toolTranscript` 連結、ストリーム用GRDB書き込みスロットリング（`ChatStreamingPersistence`）とUIスナップショットの概念分離は設計良好。`@MainActor`・Combineスコープ・`BackgroundTaskGuard` も適切。

## 2-4. Fusion層（Features/Fusion/）

- **[中][堅牢性/デッドコード] `FusionOrchestrator.swift:26,301-368` / `FusionTypes.swift:212` — `maxFusionDepth=1` の再帰ガードが本番で実質デッドコード**
  `fusionDepth` は**どこからもインクリメントされない**（`0 >= 1` は常にfalse）。`runRecursionFallback`(301) に到達できるのはテストが `FusionContext(fusionDepth: 1)` を直接指定した場合のみ（FusionOrchestratorTests:252で確認）。「防衛策」が機能していないのにガードがあることで守られているかのような誤解を生む。→ 再帰を実装するか除去。
- **[中][仕様ミス] `timeoutMs` 群が完全なデッド設定**
  `FusionTypes.swift:99,112` / `FusionPresetLoader.swift:6,35` / `FusionExtensions.swift:35` に `timeoutMs` がある一方、実際のネットワーク呼び出しは `FusionService.swift:280` で `timeoutInterval: .greatestFiniteMagnitude` に固定。**ユーザーがプリセット/UIでtimeoutを変えても一切反映されない**「値を指定できるAPIが存在するのに無視される」矛盾したUI表面。→ 撤去 or 実装。
- **[中][重複/LLM臭] `FusionTypes.swift:158-379` — `JudgeAnalysis` と `JudgeAnalysisDTO` 一式の鏡像重複**
  必須10フィールドの `JudgeAnalysis` に対し `JudgeAnalysisDTO`+`JudgeContradictionDTO`+`JudgeUniqueInsightDTO`+`JudgeSuspectedErrorDTO`+`JudgeStrongestPartDTO`（全部Optional）と、`toJudgeAnalysis()` の手動マッピング約70行。→ 単一の全Optional型+`convertFromSnakeCase`+`decodeIfPresent` で一本化可能。**Androidにも同一パターン（低性能LLMの共通祖先の証拠）**。
- **[中][堅牢性] `FusionService.swift:135` — シンセ失敗フォールバックが空文字を無検証で `finalAnswer` に返す**
  成功側(75)は `trimmedNonEmpty` で空回答を弾くのに、失敗側は `outcome.staticFallbackAnswer` が空でも `FusionRunResult(finalAnswer: "")`（status=`synthesis_fallback`）を返す。非対称。
- **[低][デッドコード] `FusionPanelRunner.swift:75,129-130` — 常にnil/空のフィールド**（`finishReason: nil`、実質空になる `toolCalls`、未使用の `role`）
- **[低][LLM臭] `FusionPrompts.swift:152-162` — `synthesizerUserPromptWithoutJudge` は薄いラッパー**（`judgeParseFailed: true` で呼ぶだけ。Orchestrator:76-87 の分岐も1引数の違いしかない）
- **[低][仕様ミス] `FusionOrchestrator.swift:385` — 静的フォールバックが「最速」パネルをベスト扱い**（`min(by: latencyMs)`。速度は品質を保証しない）
- **[低][堅牢性] `FusionJudgeParser.swift:16-29` — JSON抽出が「最初の`{`〜最後の`}`」で過剰抽出**（複数オブジェクト/前置・後置テキスト混在でデコード失敗→repair遷移の二重コスト。`replacingOccurrences("```")` が別フェンスも消す）

### 良い点
- 責務分割（Service=アセンブリ/確保、Orchestrator=状態遷移、PanelRunner=並列、不変`Sendable`型）は明確。`withTaskGroup`+逐次回収で `chipPanels` の競合なし、`@Sendable` クロージャ、`[weak self]`+allocationガードも適切。judgeパース失敗時のrepairリトライ・追加コスト合算は正しい。

## 2-5. ツール/auth/共有拡張（Features/Tools/ + Data/Auth/ + その他）

### 最重要

- **[高][セキュリティ] `SearchEngine.swift:124-157` — SSRF/DNS rebinding（TOCTOU）**
  `WebToolURLPolicy.validatePublicHTTPURL` は `getaddrinfo` で解決したIPを公開ルーティング判定するが、直後の `URLSession.bytes(for:)` は**独自にDNS再解決**。検証時は公開IP・接続時にプライベートIPを返すDNS rebindingでローカルNWスキャンが可能。→ 検証済みIPへ接続をピン留め（解決IP直接続+Hostヘッダ）を。※端末上のlocalリソース読み取りなので実害は限定的だが設計上の穴。

- **[高][堅牢性] `LocalAuthCallbackServer.swift:95-218` — タイムアウト不能（ハング）**
  `awaitCallback` のタイムアウト `timeoutWork`（`queue.asyncAfter`）とブロッキング `acceptConnection` ループ（`queue.async`）が**同一の直列DispatchQueue**に乗っている。`accept` が接続待ちで直列キューを塞ぐため、タイムアウトタスクは実行されない。ユーザーがブラウザで認証を完了しない限り `withCheckedThrowingContinuation` は永遠にresumeされず、`callbackTask.value`（Codex 189 / SuperGrok 115）がハング。→ acceptを分離キュー化し、タイムアウトと取消で確実に解決。

### 中重要度

- **[中][仕様ミス] `CodexAuthRepository.swift:257-316` — refreshのsingle-flight欠如**
  SuperGrok側（`SuperGrokAuthRepository.swift:204-229`）には「refresh tokenは使い捨て」の単一flight（`RefreshTaskBox`+`refreshLock`）があるがCodex側には無い。同時401や並行refreshで使い捨てtokenが再使用になり `refresh_token_reused` を招き得る。→ 同機構を導入。
- **[中][セキュリティ] `SuperGrokAuthRepository.swift:50,74,324` — nonce不検証**
  nonceを生成しauthorize URLに含めるが、戻ったid_tokenのnonce claimを検証していない（`SuperGrokAuthModels.swift:36-39` のパーサも非検証）。PKCE/stateは検証済み。→ id_token replay防止のためnonce検証を実装。
- **[中][LLM臭/重複] `CodexAuthRepository.swift` と `SuperGrokAuthRepository.swift` — 全面的なコピペ出自**
  `generatePKCE`/`generateState`/`randomBytes`/`base64URL`/`formURLEncode`/`sha256`（695-730 / 606-641）、`launchBrowser`+`waitForListenerReady`（482-516 / 531-565）、refreshフロー全体、JWTパーサ（`AuthModels.swift:CodexJWTParser` vs `SuperGrokAuthModels.swift:SuperGrokJWTParser`）がほぼ同一。→ 共通モジュール抽出。
- **[中][設計/堅牢性] `ToolCallingOrchestrator.swift:32,77,153-171` — 重複抑止の仕様曖昧化**
  2周目以降の同一工具・同一引数を自動的に「Duplicate tool call suppressed」として明示エラー化。`duplicateKey` の `max_results` 型揺れや `normalizeSearchQuery`（実行時は生query使用）の差異により、意図しない「見かけ上の重複」抑制が起き得る。仕様として明文化すべき（無限ループ防止のmaxRounds=15は妥当）。
- **[中][LLM臭/パフォーマンス] `DuckDuckGoHTMLEngine.swift:57-64,76-139,257-288` — 正規表現によるHTMLパース**
  `NSRegularExpression` で生HTMLから直接抽出し、`matches` が毎回 `try?` で正規表現を再生成。DDGのDOM変更に脆弱（リテラル中心でReDoS実リスクは低め）。`extractPublishedDate` のフォーマッタ毎回生成等の小非効率も散在。
- **[中][LLM臭/重複] `AuthModels.swift:73-134` と `SuperGrokAuthModels.swift:119-176` — `CodexAuthRefreshError`/`SuperGrokAuthRefreshError` ほぼ同一**
  分類ロジックの相違は `"invalid_grant"`（SuperGrok 152）のみ。
- **[中][堅牢性] `FetchUrlTool.swift:54-57,61-63` — 到達不能のデッドコード**
  `URLSessionWebToolHTTPClient.get` が2MB超過時にストリーム内でthrowするため、`guard data.count <= maxResponseBytes` は到達不能。上限チェックを一極化。

### 低重要度

- **[低][仕様ミス] `CodexAuthRepository.swift:89-116,411-418` — `CodexAuthJSON.lastRefresh` と別キー `codex_last_refresh` の二重管理**
  refresh判定が2経路で分岐し得る。統一を。
- **[低][堅牢性] `ShareExtensionItemLoader.swift:40-66` — `withCheckedContinuation` にタイムアウトなし**
  コールバックが来ない場合に戻らない構造。→ タイムアウト or `withTaskGroup` ダウンカウンタ。
- **[低][設計] `ClientToolFallbackPolicy.swift:11` — `catalog.isEmpty != false` の難解イディオム**（`catalog.isEmpty || catalog == nil` と明示すべき）
- **[低][設計] `RunFusionIntent.swift:25-31` — `logPrompts: debug` のサニタイズ経由確認が必要**
- **[低][性能] `KeychainStore.swift:32-35,104` — serviceが全プロバイダ共通の単一String**（実害なし。個別アクセスなので）

### 良い点
- 骨格は堅実: 無限ループ防止（maxRounds）、重複呼び出し抑止、Keychain、state/code検証、loopback listener、`DiagnosticsLogSanitizer` によるログサニタイズ、`actor OpenAISkillContainerManager`（Androidの `@Synchronized`+同期I/O問題を解消）。

---

# Part 3: クロスプラットフォーム比較

| 項目 | Android | iOS | 評価 |
|---|---|---|---|
| 履歴切り詰め | 件数20で `takeLast`（トークン非考慮・先頭role違反の可能性） | **切り詰めゼロ（全量送信）** | 両方欠陥、方向が逆。iOSがより深刻 |
| SSEパーサ | 2ファイル約400行コピペ | `SSEPayloadAssembler` で一元化（ただしポンプは3重） | iOS優位 |
| `incrementalDelta` | 4箇所複製 | 1箇所（`StreamDeltaAccumulator`）に集約 | ただし**欠陥（接頭辞不一致時全量返却）ごとAndroidから移植**とコメント明記 |
| `delta.tool_calls` | 型定義のみ・完全無視 | パースして `ToolCallAccumulator` に累積 | iOS優位 |
| `ToolCallAccumulator` | 完全デッドコード | 3箇所で実使用 | iOS優位 |
| Hosted Skillsロック | `@Synchronized` 下で同期ネットワークI/O | `actor` で解決 | iOS優位 |
| Fusion品質 | 6/10（同名クラス衝突・両分岐nullのif） | 8/10（DTO鏡像・薄いラッパーは共通） | iOS優位。**共通残骸（DTO鏡像・薄いラッパー）= 同一LLM祖先の証拠** |
| デュアル履歴 | 相手の発言を `user` ロールで注入 | **相手の発言を完全省略** | **挙動が大きく異なる。仕様確認が必要** |
| 自動会話トリガ | 弱い判定（実質常時発火） | 同一コードを移植（同じ弱さ） | 共通欠陥 |
| `output_config`（Anthropic） | **存在**（実Claudeで400の恐れ） | 存在せず | Androidのみの問題 |
| トップレベル `cache_control` | **存在**（要仕様確認） | 存在せず | Androidのみの問題 |
| `session_id` 二重充填 | 存在せず | **存在**（要仕様確認） | iOSのみの問題 |
| ストリーミングタイムアウト | `readTimeout(0)` 無期限（意図的） | `URLSession.shared` 60秒既定 | Androidが正しい（ただし価格APIにも無期限を共用する欠点あり） |
| 認証 | Codex（PKCE+DoHフォールバック・丁寧） | Codex/SuperGrok コピペ＋single-flight欠如＋nonce不検証＋コールバックサーバハング | iOSがauth領域で劣る |
| テスト網 | 限定的 | `YamabikoTests` 約70ファイルと充実 | iOS優位 |

---

# Part 4: 低性能LLM痕跡の共通パターン（両プラットフォーム横断）

1. **無呼び出しデッドコード**（grep実証）
   - Android: `CodexResponsesProvider.kt:414` `parseResponsesSseToGemini`（約300行）/ `RequestConverter.kt:365,384` `openRouterStreamToGemini`・`openRouterStreamResponseToGemini` / `ProviderCatalog.kt:78` `remapRemovedProvider` / `OpenAiProvider.kt:25` 常時500override / `RetrofitClient.kt:82` `openAiStaticInstance` / `ToolModels.kt:37` `ToolCallAccumulator` / `ChatViewModel.kt:948` `updateAutoConversationProgress` / `:454,504` `createSecretConversation`・`getFullMessageById` / `DualChatResponder.streamResponses` / `AutoConversationManager.kt:36` `MAX_RETRY_ATTEMPTS` / `:134,155` pause/resume
   - iOS: `ChatViewModel.swift:18` `messageSummaries` / `ChatRepository.swift:2459` `decodeArray` / `OpenAICompatibleProviderClient.swift:531` `intValue` / `ProviderClient.swift:21` 既定stream / `ProviderRequestSettingsResolver.swift:240` `geminiFunctionDeclarations` / `FusionOrchestrator.swift:26` `maxFusionDepth` / `FusionTypes.swift` `timeoutMs` / `FusionPanelRunner.swift:75` `finishReason` / `FetchUrlTool.swift:61` 到達不能ガード
2. **コピペ重複**: Android: SSEパーサ2ファイル400行 / `incrementalDelta`×4 / ApiRepository分岐×5〜6 / 自動会話統合×3 / `applySkillContext`×2 / OpenRouterRequest 18フィールド / CodexAuthのrefreshブロック×2。iOS: SSEポンプ×3 / usageパース複製 / Codex⇔SuperGrok認証全体 / AuthRefreshError / Fusion表示ラベル×2 / `readStreamErrorBody`
3. **ハルシネーション疑いフィールド**: `output_config`（確定的に非標準）/ トップレベル `cache_control`（要確認）/ `reasoning_details`（要確認）/ `session_id`（要確認）
4. **無意味コード**: `FusionService.kt:227-235` 両分岐nullのif / `RequestConverter.kt:429` 冗長ローカル / `GeminiProviderClient.swift:232-233` 重複return
5. **エラー握りつぶし**: `try? JSONSerialization...continue`（iOS SSE）/ `try? await Task.sleep`（iOS Geminiリトライ）/ `runCatching`+`getOrNull` の多用
6. **DTO鏡像パターン**: Android `FusionTypes`系＋iOS `JudgeAnalysisDTO` 一式（共通のLLM祖先）
7. **薄いラッパー/過剰抽象**: `synthesizerUserPromptWithoutJudge`（両プラットフォーム）/ `CodexSessionIdUtils` / 後方互換typealias3連
8. **非対称エラーハンドリング**: iOS `FusionService.swift:135` 空回答無検証
9. **正規表現パース**: DuckDuckGo HTML（両プラットフォーム）/ FusionJudgeParser（Android）/ SSE完全性の文字列キー判定（iOS）
10. **テスト回避ハック**: `AutoConversationTrigger` の `testPatterns`（両プラットフォーム同一）
11. **運用コードに残るデバッグログ**: `RequestConverter` / `ApiRepository` / `OpenRouterProvider`（Android）
12. **設定の乱立**: Android `applyPreset` のプロバイダ別settingsフィールド爆発
13. **レースハック**: `delay(500)`（Android）→ iOSは `combine` 等で解決済み
14. **セキュリティ共通の穴**: SSRF DNS再解決TOCTOU（両プラットフォーム）

---

# Part 5: 推奨アクション（優先順）

## 共通（両プラットフォーム）
1. **履歴切り詰めの統一仕様化**: トークン概算ベースの切り詰めを実装（Androidは `takeLast(20)` を置換、iOSは新規導入）し、先頭ロールを `user` に正規化。コンテキスト上限（iOS `resolvedContextLimit` / Android `GenerationConfig`）を実トリミングへ接続。
2. **ハルシネーション疑いフィールドの仕様確認**: `output_config`（確定的に分離）・`cache_control`・`reasoning_details`・`session_id` を各プロバイダ仕様と突合し、非標準なら分離・削除。
3. **自動会話の絶対上限**: `maxTurns=0` 時にもターン上限/無進行タイムアウト（両プラットフォーム）。
4. **デッドコードの一括削除**: Part 4-1 のリスト（合計600行超）。
5. **SSRFガードのTOCTOU修正**: 検証済みIPへ接続をピン留め（両プラットフォーム）。
6. **`incrementalDelta` のフォールバック修正**: 接頭辞不一致時に全量返却しない。

## Android優先
7. **ApiRepositoryの分岐を `ApiContext` に一本化**（約400行削減・dual系のドリフト解消）。
8. **SSEパーサ統合 + `incrementalDelta` 単一化**（`ChatResponseStreamer`/`StreamChunkConsumer`）。
9. **自動会話統合をべき等な1関数に集約**（3重実装の解消）、`delay(500)` を `combine()` 観測に置換。
10. **`output_config` をAlibaba専用に分離**、`OpenRouterRequest` の18フィールド統合、`openAiStaticInstance` 削除、`@Synchronized` 下I/Oの排除。
11. **ストリーミング `delta.tool_calls` を実装 or 非対応を明示**（`ToolCallAccumulator` を活かす/削除）。
12. **Fusion**: 同名 `ClientToolCallingRunner` 解消、`FusionService:227-235` 削除、phase別システムプロンプトポリシー統一、judge repair latency集計修正、`AllPanelsFailed` のUIハンドリング。

## iOS優先
13. **履歴切り詰めの実装**（最大の欠陥）＋ `resolvedContextLimit` 接続。
14. **`LocalAuthCallbackServer` のタイムアウト修正**（acceptの分離キュー化）。
15. **SSEポンプを `ProviderSSEStreamRunner` に統合**（Anthropic/Codex）＋usageパース一本化。
16. **Codexにrefresh single-flight追加**、SuperGrokのnonce検証、認証コード/JWTパーサの共通モジュール抽出。
17. **OpenCodeGo二重 `.completed` 修正**、`try? Task.sleep` のキャンセル伝播。
18. **Fusion**: `maxFusionDepth`/`timeoutMs` の撤去 or 実装、`JudgeAnalysis` DTO一本化、シンセフォールバックの空回答検証。
19. **デュアル履歴の仕様確定**（相手出力の省略 vs Androidの注入 — どちらかに統一）。
20. **fire-and-forget `Task` のキャンセル対応**（送信/再生成の停止UI）＋ `sendMessage` 再入ガード。

---

# 付録A: スコアとエージェント対応表

| # | 領域 | エージェント | Androidスコア | iOSスコア |
|---|---|---|---|---|
| 1 | APIサービス層 | fb85c584 / 8d932019 | 7/10 | 7/10 |
| 2 | Provider/変換層 | fbc1d8c5 / e5f3daa5 | 5/10 | 7.5/10 |
| 3 | コンテキスト管理 | 05b7e5b4 / 953cd347 | 5.5/10 | 6.5/10 |
| 4 | ストリーミング/ツール | 5ef9adc3 | 6.5/10 | — |
| 5 | Fusion | b982514e / 749a2577 | 6/10 | 8/10 |
| 6 | ツール/auth/その他 | 29dae1e3 | — | 7.5/10 |
| 7 | その他ハーネス（親エージェント直接調査） | — | 7/10 | 7/10 |

# 付録B: 未検証事項（要仕様確認リスト）
- OpenRouter: トップレベル `cache_control`（OpenAI互換API）／ `reasoning_details` フィールドの実在
- OpenAI/OpenRouter: `session_id` パラメータの実在（iOS）
- OpenAI Responses API: `prompt_cache_key` / `include=["reasoning.encrypted_content"]` の実在（Android RequestConverter.geminiToResponses）
- OpenCodeGo: prompt cache key seedの実影響
- iOSデュアルモード: 相手モデル出力の履歴省略が意図的か否か（Androidとの挙動差）
