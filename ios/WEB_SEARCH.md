# iOS client web search

`web_search` remains a Pi local tool. It uses public HTML search pages directly,
without API keys, accounts, paid APIs, an external proxy, or additional AI calls.
Provider/model resolution and Pi execution are unchanged.

## Retrieval

- Japanese locale or Japanese-script queries: Yahoo! JAPAN and Bing concurrently.
  Other queries/locales: Bing. The Japanese preference includes kanji-only queries.
- Yahoo organic cards receive a modest ranking preference. Merge uses reciprocal
  rank, query term overlap, and a domain diversity penalty. Agreement between
  engines improves rank but does not establish factual correctness.
- Only organic cards are parsed. Ads, related questions and generated answers are
  excluded. Bing desktop/mobile layouts and encoded destination links are handled.
- Known tracking parameters are removed for deduplication; resource query
  parameters, path case and fragments are preserved. Each result reports
  `search_engines`. Dates in snippets are not asserted as publication metadata by
  the new adapters.
- If the initial engines both fail/return no readable results, DuckDuckGo HTML/Lite
  is a fallback. Search has an eight-second cooperative deadline including fallback;
  each new HTML adapter's request timeout is six seconds. Completed results survive
  another engine timing out. No CAPTCHA bypass or automatic repeated probing.
- Public HTML endpoints can restrict access or change markup. Yahoo returned
  organic results with the app's existing iPhone User-Agent during development,
  while a generic User-Agent returned a simplified page without organic cards.
  Empty/challenge/changed pages are treated as unavailable, never fabricated hits.

## Source reading and reuse

`goal` alone no longer starts page downloads. Set `read_sources: true` with `goal`
to optionally read two sources concurrently with a five-second cooperative budget.
Results include completed pages, the original source association, and
`source_reading_status`; missing pages can be requested using `fetch_url`.
Search snippets remain unverified until their original sources are inspected.

Cancelled HTTP cache waiters return promptly. A shared download continues while
another reader needs it, and is cancelled when its last waiter leaves. HTTP and
WebKit limits, SSRF checks, script isolation and source provenance are retained.
Successful duplicate tool calls automatically replay retained evidence with the
new call ID; `recover_cached` remains supported. Retention is bounded and scoped
execution bookkeeping remains isolated. Empty search responses are not cached.
Search/cache and optional page-reading timing are included in results/diagnostics.

## Verification

`WebSearchToolTests` covers organic-only parsing, mobile markup, Bing redirects,
Japanese routing, tracking/resource identity, multi-engine deduplication, a blocked
Yahoo with successful Bing, fallback, partial deadline results, cancellation,
source attribution, cache sharing and duplicate replay, alongside existing fetch
and SSRF regressions.

On 2026-10-17, a local Swift probe using the production search engine and HTTP
client returned five merged hits for `京都 紅葉` and `Swift TaskGroup cancellation`
with `ja_JP`. Single observed durations were about 1.2s and 0.8s. These are smoke
checks on one network, not a ranking benchmark or availability guarantee.
