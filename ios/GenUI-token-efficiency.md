# GenUI definitions and prompt caching

The iOS `genui` definition previously included the complete property catalog and
an enum of all 463 supported names (including 283 recovered templates). Both were
sent before the first user message, even when no GenUI was needed.

## Research and chosen approach

Reviewed on 2026-10-14:

- [Anthropic: Code execution with MCP](https://www.anthropic.com/engineering/code-execution-with-mcp)
  describes progressive disclosure, searchable definitions, and filtering results
  before adding them to model context.
- [Anthropic: Advanced tool use](https://www.anthropic.com/engineering/advanced-tool-use)
  describes Tool Search and Programmatic Tool Calling. Deferred definitions enter
  the conversation after discovery, preserving the initial cached prefix.
- [Claude Tool Search documentation](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool)
  requires a fixed complete tools array with `defer_loading`; discovered references
  must be preserved in subsequent conversation messages.
- [Claude prompt caching documentation](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
  specifies exact prefix matching, the `tools → system → messages` hierarchy,
  and model-specific minimum cache lengths (including 4,096 tokens).

GenUI is one large local tool, rather than hundreds of independently callable MCP
tools. The implementation therefore uses progressive disclosure through the
existing `genui_reference` executor. It does not introduce an MCP code-execution
environment, a new inference path, or provider-specific wire fields. Pi still
owns provider serialization, cache breakpoints, execution, history and usage.

The fixed `genui` definition retains useful runtime instructions and basic element
properties. Template contracts, aliases and the exhaustive name enum are removed
from the prefix. This deliberately retains more useful static content than a
minimal wrapper: the minimal candidate was approximately 1,000 tokens and risked
making short conversations ineligible for caching. No filler or model-dependent
definition switching is used.

## On-demand reference contract

- `{"componentName":"*","query":"currency"}` searches all supported names by
  case-insensitive substring. Names are sorted, with 32 results by default and
  a maximum page size of 64. `offset`, `totalMatches` and `nextOffset` support
  complete discovery; no-match results are empty rather than guessed alternatives.
- A specific primitive or alias returns its actual accepted properties and its
  canonical name. A specific original template retains the original source/state
  response and `sourceOffset`/`maxCharacters` pagination.
- `{"componentName":"@guide"}` retrieves runtime guidance if needed again.
  The initial definition already contains that guidance, so ordinary compositions
  do not require an extra round trip.
- Reuse retrieved contracts from conversation history. References are tool results,
  never additions to the system prompt or changes to advertised tools.

The compact `ui` schema describes the node shape inline, without enumerating names
or embedding recursive catalog definitions. The existing local validator retains
the complete catalog, checks nested nodes and rejects unsupported components.
Legacy `components`, rich `ui`, `code`, stored documents and the native PCC document
envelope continue using the same executor and validation.

## Measurements and cache guarantees

The following comparison evaluates the actual Swift static definitions at the
pre-change revision and after the change. Schemas are parsed and serialized as
compact JSON with sorted keys; the measurement covers `genui` only, rather than
the entire provider request.

- Serialized definition: 56,737 → approximately 24,000 UTF-8 bytes (58% reduction).
- `cl100k_base` estimate: 13,454 → approximately 5,400 tokens (60% reduction).
- `o200k_base` estimate: 13,352 → approximately 5,500 tokens (59% reduction).

These two tokenizers are estimates, not Claude token counts or billed usage. The
fixed core provides margin over the documented 4,096-token minimum in both
estimates before adding the system prompt, reference tool, other tools or history.
Provider tokenizer and minimum-length changes still require production measurement;
byte counts and deterministic prefixes cannot prove an actual cache-hit rate.

Unit tests assert identical serialized tool definitions before and after guide,
search, primitive and template retrieval, across scoped registries and executor
ordering. An additional offline check passed the evaluated definitions through
Pi's actual Anthropic serializer: tools, system content and their `cache_control`
markers were byte-identical before and after adding a reference tool result.
The check intercepted `onPayload` before network access.

Definitions change once when upgrading the app, so an old-version prefix is not
reusable for the first request with the new version. Subsequent requests keep the
new prefix stable regardless of what templates were discovered. User changes to
settings, models, tools or the existing daily date suffix retain their normal
cache effects.

Live validation should compare Pi's existing `cachedInputTokens`,
`cacheCreationInputTokens` and uncached input usage on repeated ordinary and GenUI
turns using the same settings/model, within the provider's cache TTL. A template
lookup adds a normal inference/tool-result round trip and its source tokens, so
per-task savings depend on which templates are needed. This implementation does
not claim a measured production hit rate or a 60% reduction in every full request.
