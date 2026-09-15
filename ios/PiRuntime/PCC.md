# Apple Private Cloud Compute

## Execution contract

The iOS-only provider identity is `apple-pcc/PrivateCloudComputeLanguageModel`.
Pi owns model resolution and the Agent loop. Its `createProvider()` API dispatches
through the existing authenticated loopback bridge to `PCCProviderClient` in Swift.
No OpenAI-compatible endpoint, protocol retry, or on-device fallback is involved.
Android and catalog (`MODELS_DEV:*`) identities cannot activate this native provider.

Native capability version 1 reports availability and the SDK's asynchronous
`contextSize`. The provider uses a null base URL because Apple exposes no wire
endpoint. Apple's documented uncapped response can fill the remaining context,
so the model's response ceiling is the SDK context size. Explicit per-request
limits remain separate from that ceiling.

Swift converts the Pi context to typed transcript entries and ordered image
attachments. Unsupported content fails explicitly. Tools are disabled. Reasoning
maps low/medium/high to Apple's light/moderate/deep; the default is moderate.

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
