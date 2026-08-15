# OpenCode Go ストリーミング本文空問題の修正報告書

## 1. 不具合の原因 (Root Cause)

OpenCode Go（`deepseek-v4-flash` 等）でストリーミング送信を行った際、サーバーとの HTTP 200 / SSE ストリーム通信自体は正常に完了するものの、本文デルタ（`textDelta`）が 1 件も返されずにストリームが終了するケースがありました。

この際、以下の問題が発生していました：
- `ProviderGateway.swift` のストリーミング処理において、本文デルタが来なかった場合に適切な同期フォールバックが行われず、あるいは推論ログ（`streamReasoning`）の有無に応じた例外（`parseFailure`）がスローされたり、不整合な continuation ループに突入していました。
- これにより、`ChatStreamSession` で生成された assistant メッセージ行が空文字列のまま終了・保存され、UI 上で白い空の返信バブルが残ったまま 2 ターン目以降の会話が進まなくなる症状が発生していました。

---

## 2. 修正内容 (Fix Details)

OpenCode Go の成功扱い・本文ゼロを検出した場合に限り、同一の assistant 行を非ストリーミング（同期応答）で充足する限定回復処理を実装しました。

### (1) `ProviderGateway.swift`
- `provider.retriesNonStreamingWhenStreamReturnsNoText`（OpenCode Go で `true`）かつ `!streamHadAnswerText`（ストリーム中に本文デルタを受信しなかった）の条件を満たした場合に限定して回復処理を実行。
- 同一の元の `ProviderRequest` を用いて `client.generate`（非ストリーミング同期応答）を呼び出し、取得した `ProviderResponse`（本文テキスト・思考ログ・トークン使用量等）を `.completed` イベントとして yield。
- これにより、`ChatStreamSession` が同一の `target`（同一の `messageId` / `variantId`）に対して同期応答の結果を反映し、DB への永続化（`target.persist`）および UI スナップショット（`publishStreamingSnapshot`）を発行して同一行を安全に充足します。
- 通常の本文ストリーム時（`streamHadAnswerText == true`）や他プロバイダ（`retriesNonStreamingWhenStreamReturnsNoText == false`）では一切発動しない安全設計となっています。

### (2) テストスイートの追加・更新
- **`ChatRepositorySyncTests.swift`**:
  - `testOpenCodeGoEmptyStreamRecoversWithNonStreamingResponse`: OpenCode Go で空ストリーム完了時に非ストリーミング同期応答が実行され（`sendCallCount == 1`）、DB の assistant メッセージ行に本文が充足・保存されることを検証。
  - `testOpenCodeGoNormalStreamDoesNotTriggerNonStreamingFallback`: 通常の本文ストリーム時には非ストリーミング呼び出しが行われないこと（`sendCallCount == 0`）を検証。
  - `testOtherProviderEmptyStreamDoesNotTriggerNonStreamingFallback`: OpenCode Go 以外のプロバイダでは空ストリーム時にも非ストリーミング回復が発動しないこと（`sendCallCount == 0`）を検証。
- **`ProviderGatewayTests.swift`**:
  - `testOpenCodeGoStreamRetriesNonStreamingWhenStreamReturnsNoAnswerText`: Gateway レベルでストリーム本文ゼロ時に単一の非ストリーミングリクエストが送信され `.completed` で応答が返ることを検証。
  - `testOpenCodeGoStreamDoesNotRetryWhenStreamDeliversAnswerText`: ストリーム本文が存在する際は非ストリーミングリクエストが送信されないことを検証。
- **`ShortcutModelOptionsBuilder.swift` / `FusionChatRepositoryTests.swift`**:
  - 変更に伴う関連テストケースの整合性を調整。

---

## 3. 検証結果 (Verification)

macOS ローカル環境上の iOS シミュレータ（`iPhone 17`）を対象に `xcodebuild test` を実行し、動作およびリグレッションがないことを確認しました。

### 実行結果
- `ChatRepositorySyncTests`（全 12 件）: **全件合格 (0 failures)**
- `ProviderGatewayTests`（全 25 件）: **全件合格 (0 failures)**
- `FusionChatRepositoryTests`（全 4 件）: **全件合格 (0 failures)**
- `ShortcutModelOptionsTests`（全 6 件）: **全件合格 (0 failures)**
- `YamabikoTests` 全体テストスイート: **全 423 件中 423 件合格 (0 failures)**

```text
Test Suite 'YamabikoTests.xctest' passed at 2026-08-14 10:40:57.592.
	 Executed 423 tests, with 0 failures (0 unexpected) in 8.392 (8.601) seconds
Test Suite 'All tests' passed at 2026-08-14 10:40:57.593.
	 Executed 423 tests, with 0 failures (0 unexpected) in 8.392 (8.603) seconds
** TEST SUCCEEDED **
```
