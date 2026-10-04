# ChatGPT plan provider plugin

`src/chatgpt-plan-plugin.js` implements the official **Sign in with ChatGPT**
contract as a native Pi provider extension, registered through `Models.setProvider`.
It uses Pi 1.0.2's existing `openAIResponsesApi`; it does not copy or replace Pi's
stream parser, agent loop, tools, usage accounting or context management.
The iOS `CODEX_AUTH` saved setting now selects `openai-chatgpt`. The Android
client continues to use its existing `openai-codex` identity. The runtime bundle
and the new plugin are shared; existing provider identities are unchanged.

## Authentication and persistence

The iOS repository stores an installation UUID and separate account registrations
in Keychain. Browser authorization uses `dynamic_agent_client` only for a new
registration, `agent_name_hint=YamabikoChat`, PKCE, state, nonce and an already
listening `127.0.0.1` callback. An issued client ID is saved and acknowledged by
iOS before code exchange. Saved registrations are reused for reauthorization;
tokens are activated only after signature, issuer, audience, expiry, nonce and
selected-account checks. ID-token verification uses `jose` and OpenAI discovery
and JWKS. Errors and cancellation stop the current attempt; there is no pasted
callback or alternate authentication path.

The plugin's `OAuthAuth.refresh` integrates with Pi's serialized credential-store
refresh. Credentials retain the server's `earliest_refresh_at` (Unix seconds or
an ISO date string) and the actual access-token expiry. Pi's scheduled refresh
is bounded by that earliest time; forced refresh also respects it and rejects
expired access when refresh is not yet permitted. The iOS repository persists the rotated credential and rejects stale
results after account changes or sign-out. Sign-out revokes the refresh session
through the issuer's published revocation endpoint, stops active plan runs and
clears local tokens. On unconfirmed remote revocation, the UI explicitly asks
the user to disconnect the app in ChatGPT settings. It retains the host ID and
account/client mapping, but removes the ID-token hint on sign-out.

Legacy Codex credentials cannot authorize this provider. Existing model settings
are retained and must be selected manually if unavailable for the new account.

## Models and inference

`GET https://api.openai.com/v1/models` supplies account-specific `slug`,
`display_name`, `visibility` and ordering. A slug that exactly matches a Pi
built-in OpenAI Responses model executes as `pi_builtin` and takes precedence.
For a slug Pi does not ship, the app passes the models.dev `openai` provider's
model contract (`contracts` on `/v1/models/chatgpt` and `catalogContract` on a
run); the plugin validates that it resolves unambiguously to Pi's Responses
adapter on `https://api.openai.com/v1` — provenance `provider`/`model`, shape
`responses` or npm `@ai-sdk/openai`, matching `api`, `text` input, positive
limits, a `reasoning` flag, and declared effort values — then registers it on the
same provider as `models_dev_contract`. A contract that fails validation keeps
the model listed but disabled with `protocol_conflict`, `endpoint_conflict` or
`catalog_contract_incomplete`; a slug with neither match stays disabled with
`pi_model_missing`. No limits, modalities or capabilities are invented. The
reasoning choices come from Pi's `getSupportedThinkingLevels`.

iOS refreshes the models.dev contracts before discovering account models when
settings open. The ChatGPT model picker also offers a manual refresh that updates
both sources, with loading and failure states. New discovery results replace the
displayed list and reasoning cache without changing the saved model selection;
superseded requests and results from a signed-out account are discarded.

Pi's `onPayload` hook applies the official preview contract: `store=false`,
`stream=true`, developer instructions and namespaced local function/custom tools.
Unsupported request fields are omitted; unsupported hosted tools fail explicitly.
Pi sends and parses Responses requests, including tool namespaces and terminal
events, using the public `https://api.openai.com/v1/responses` endpoint.
Only Pi's `completed` provider status can produce a successful plan result or
LLM completion notification. Incomplete responses, including `max_output_tokens`,
stop the agent loop and cannot produce a successful final result.
There is no protocol/provider/model retry or legacy backend route.

The settings screen and subscription-sharing error cards link to
`https://chatgpt.com/settings/usage`. The old Codex usage API is not used by iOS.

## Validation

Run `npm test` and `npm run check:contracts` in this directory. The SIWC drift
check is `python3 ../../scripts/check-chatgpt-plan-contract.py`. It compares the
official registration, inference, session and preview contracts with this plugin.

Tests cover OIDC rejection cases, registration reuse, granted-scope checks,
serialized refresh, cancellation, catalog fidelity, request shaping and the
standard Pi parser's completed/failed/incomplete/interrupted responses. A bundled
runtime integration test exercises browser callbacks, persistence acknowledgement,
catalog resolution, a namespaced local tool loop and revocation without contacting
an actual account or using legacy endpoints. iOS tests cover Keychain semantics,
account separation, stale results, legacy-token rejection and routing.

Actual account eligibility and browser consent must also be tested with a user's
ChatGPT account before release. No production credentials are part of tests.

## Authoritative sources

- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations
- https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/custom-provider.md

At launch, OpenAI documents plan usage for open-source/local projects and selected
private apps. Paid or remotely hosted distribution requires the documented access
process. This extension does not assert that OpenAI has approved a particular
distribution or account.
