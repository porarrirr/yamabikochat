# Apple Private Cloud Compute

## Execution contract

The iOS-only provider identity is `apple-pcc/PrivateCloudComputeLanguageModel`.
Pi owns model resolution and the outer Agent run. Its `createProvider()` API dispatches
through the existing authenticated loopback bridge to `PCCProviderClient` in Swift.
No OpenAI-compatible endpoint, protocol retry, or on-device fallback is involved.
Android and catalog (`MODELS_DEV:*`) identities cannot activate this native provider.

Native capability version 2 advertises native tool support alongside availability and the SDK's asynchronous
`contextSize`. The provider uses a null base URL because Apple exposes no wire
endpoint. Apple's documented uncapped response can fill the remaining context,
so the model's response ceiling is the SDK context size. Explicit per-request
limits remain separate from that ceiling.

Swift converts the Pi context to typed transcript entries and ordered image
attachments. Unsupported content fails explicitly. Version 1 remains text/image-only; version 2 enables the tools selected in the app. Reasoning
maps low/medium/high to Apple's light/moderate/deep; the default is moderate.

## Authorized PCC tool-loop exception

The user explicitly authorized this PCC-only exception on 2026-09-15: Apple's
`LanguageModelSession` owns tool calling and generation continuation. This does
not authorize alternative execution paths for other providers or models.

- `PCCNativeTool` implements Apple's public `Tool` API with runtime schemas
  built using `DynamicGenerationSchema`. Unknown schema constraints fail with
  `pcc_tool_schema_unsupported`; protocols and capabilities are never inferred.
- Calls execute through the existing `LocalToolRegistry`, with the same chat
  namespace, attachment metadata, artifact handling and activity notifications.
  A run-scoped queue serializes local side effects, including Python execution.
- Only request-authorized tools can execute. Cancellation reaches queued and
  running tools; a tool failure is returned to Apple as a tool result. Transport
  and model failures terminate the request without retrying another model.
- Native tool activity is reported to Pi's bridge. Already-executed calls live in
  `pccToolCalls`/`pccToolResults`, never in Pi's executable `content` tool blocks.
  This prevents the outer Agent from executing tools a second time. The final
  termination reason stays `unknown`; no finish reason is invented.
- The generated native transcript (only response, reasoning, tool-call and
  tool-output entries) is encoded using Apple's `Transcript` Codable contract
  in `pccTranscript` on the Pi assistant message. Follow-up requests restore it
  verbatim, preserving SDK call IDs, outputs, image artifacts and reasoning.
- The SDK's accumulated session usage is the aggregate for the native run;
  snapshots are not summed, and unknown cache-write counts remain unknown.
  Context occupancy is unknown after a native tool loop: its aggregate token
  usage must not be displayed as the last inference's context size.
- On-device Apple Intelligence remains unchanged. Android cannot activate the
  native provider. The shared JS bundle accepts tools only after native v2
  resolution enables them.

Simulator tests use Apple's actual session/tool machinery with a deterministic
`LanguageModelExecutor` test double. Live PCC checks remain opt-in and require
an entitled physical device.

## Audited Pi 0.84.2 extension

`npm ci` applies `scripts/patch-pi-contract.mjs`, with version and exact-source
checks that reject dependency drift. This preserves the Pi execution path:

- `Usage` allows null for unreported counters. PCC reports input total, cache-read,
  output and reasoning counts. Pi input excludes cache-read; cache-write is null.
- A `done` event with `stopReason: unknown` means the request completed but Apple
  did not report why generation ended. No `finish_reason` is invented. Pi does
  not execute tool arguments when termination is unknown.
- Native models may have a null base URL. Error codes survive the bridge.
- Unknown counters do not become known costs through JavaScript arithmetic.
  Apple documents zero cloud API cost for eligible developers, independent of
  token counts. Non-free providers retain unknown cost for incomplete usage.
- Bridge aggregation, stored Pi history, SQL cache-write totals, and usage UI
  preserve unknown values. Partial totals are not displayed as complete totals.

`check-pcc-contract.py` checks the upstream Apple documentation used by the
adapter. Run it after SDK updates, alongside the version-checked Pi patch and
provider resolution tests. It checks required documented fields and semantics;
it does not claim to detect every possible upstream behavioral change.

## Signing and validation

The app entitlement is `com.apple.developer.private-cloud-compute = true`.
The App ID and provisioning profile must be approved by Apple. The share extension
has no PCC entitlement. The deployment target remains iOS 17; PCC requires iOS 27.

The opt-in `PCCProviderTests/testLivePCCThroughPiWithImageAndFollowUp` consumes two
PCC requests. Set `YAMABIKO_PCC_LIVE_TEST=1` in the test runner environment on an
entitled physical device. Default automated tests use synthetic native events and
do not contact PCC. They cover bridge authentication, request matching, usage,
errors, cancellation, settings persistence, images and transcript roles.

Sources:
- https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel
- https://developer.apple.com/documentation/foundationmodels/generationoptions/maximumresponsetokens
- https://developer.apple.com/documentation/foundationmodels/languagemodelsession/usage-swift.struct
- https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting
- https://developer.apple.com/private-cloud-compute/
