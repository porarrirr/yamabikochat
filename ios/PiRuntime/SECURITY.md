# Credential and conversation boundaries

Inference and authentication remain on the Pi provider path. These controls do not
make a cloud provider an offline service or change its retention rules.

- A secret single or dual conversation carries `executionPolicy` with both client
  tools and subagents disabled. The gateway omits child configurations and credentials.
  Pi enforces the policy before skills, extensions, provider discovery for children,
  or tool execution. Legacy requests with `supportsClientTools=false` are restricted too.
- Authentication failures expose fixed messages and allowlisted codes, never response
  bodies, JSON parser excerpts, upstream free text, or exception causes. Native decoding
  also replaces malformed authentication responses with a fixed error.
- Credential-bearing native sessions and Pi transports reject redirects. Browser
  authorization URLs must use the exact approved HTTPS authentication hosts.
- ChatGPT and SuperGrok stop active runs and attempt session revocation on logout.
  Refresh and revoke operations share a provider-scoped queue so revocation uses the
  latest rotated tokens. SuperGrok revokes both refresh and access tokens at the endpoint
  advertised by `https://auth.x.ai/.well-known/openid-configuration` (RFC 7009).
  A missing or untrusted endpoint and an unsuccessful response fail closed. Local
  credentials are deleted even when remote revocation is unconfirmed, and the UI
  explicitly reports that the user should review provider account connections.
- The pinned pi-grok provider uses an ephemeral loopback port and checks state and
  request method before consuming successful or error callbacks. No replacement login,
  refresh, protocol, provider, or model fallback is introduced.
- Keychain secrets use `WhenUnlockedThisDeviceOnly`, with synchronization disabled.
  Startup upgrades dormant credentials too. Locked-device background credential reads
  can therefore fail and must wait until the device is unlocked.
- Internal attachments, generated files, queued share drafts, and temporary exports use
  iOS Complete File Protection and backup exclusion. This is OS-managed file encryption,
  not an application-defined ciphertext format. New generated files live in private
  Application Support; prior Documents files keep their existing references and receive
  the same protection. Implicit Documents file sharing is disabled. Explicit user export
  and share actions still create readable copies for the chosen destination.
- Export completion/dismissal removes its ZIP. Startup removes abandoned ZIP/staging
  copies and attachment staging files. A migration removes historical app diagnostic
  files in both Debug and Release. Copies already shared outside the app and OS logs
  from previous builds cannot be recalled by this change.

`npm test` includes offline regression tests for restricted requests, wrong-state and
non-GET callbacks, malformed token bodies, revocation failures, and refresh/revoke races.
It also exercises all Pi built-in identities and protocol kinds. The xAI metadata drift
check is `python3 scripts/check-supergrok-auth-contract.py` from the repository root.
The provider patch is applied and checked on dependency installation and every build.
Real account credentials are not needed by these tests.

Before distribution, verify the signed Release on physical devices for lock/unlock,
backup/restore, external-browser sign-in and provider-side revocation. Simulator tests
cannot certify those device and service behaviors or prove that a past leak never
occurred.

## Validation on 2026-10-23

- Pi runtime: 143 tests passed, including the offline security regressions above.
- Ad hoc signed iOS simulator: 1,088 tests passed and 7 opt-in/platform tests skipped.
  The 78 web-tool tests passed separately after an earlier full run encountered DNS
  resolution failures. Three presentation tests were excluded from the successful
  run after reproducing their failures on unchanged commit `8ecf2a8`:
  `testRapidCompletedHistoryScrollingKeepsReusedCellsOnTheirOwnMessage`,
  `testReturningToShortConversationDoesNotReuseTallCellHeight`, and
  `testStreamingMarkdownKeepsRenderedPriorParagraphStableWhileAppendingParagraph`.
- Unsigned Release build for generic iOS succeeded, including the share extension.
  The signed Debug simulator app launched to the connection screen successfully.
- Official ChatGPT and xAI auth contract checks passed, as did the independent
  provider endpoint/catalog credential-alias check. The complete contract command
  still fails in the unchanged Azure check because the live catalog no longer
  contains `claude-opus-4-1`. No provider/model substitution was made.

These results do not include real-account login, provider-side token invalidation,
or physical-device lock and backup testing. The earlier full test run is not a
clean pass; the known exclusions and contract drift remain separate follow-up work.
