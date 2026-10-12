# GenUI on iOS

The iOS `genui` local tool uses the existing Pi tool registry and stream. It is
offered in normal and dual conversations to models advertising client tool
support. Secret conversations, auto conversations, and Fusion panels do not
receive it. Gemini native tools take precedence over this function tool.
Apple PCC uses its existing public SDK tool path with a single JSON-string
`document` parameter, because GenerationSchema cannot express recursive unions.
The same local executor validates and persists the contained document; other
providers receive the full document schema directly.

The original declarative document remains supported. A document has
a title, optional subtitle, inputs, and an ordered list of components. Supported
inputs are sliders, numbers, numeric selections, text, and toggles. Supported
components are text, metrics, tables, line/pie charts, and card grids.

Legacy `kind:"chart"` selects its visualization with `chartType:"line"` or
`chartType:"pie"`. Omission preserves the historical **line** default; IDs and
titles (including `coin_pie`) never select the chart type. Pie charts require
exactly one series, finite nonnegative point values, and a positive finite total.
They render native Swift Charts sectors colored by category with a legend.
Formulas recalculate locally; invalid pie values after editing show an unavailable
value, not a line chart. For example:

```json
{"title":"構成比","components":[{"id":"shares","kind":"chart","chartType":"pie","series":[{"name":"割合","points":[{"label":"A","value":"40"},{"label":"B","value":"60"}]}]}]}
```

Rich `Chart` nodes use a different shape: `props.content` contains
`{chartType:"pie",data:[{name:"A",value:40},{name:"B",value:60}],nameKey:"name",valueKey:"value"}`.
Generation instructions require explicit pie selection and prohibit describing
an unspecified legacy line chart as a pie chart. Previously saved documents
without `chartType` retain their original line visualization.

Strings beginning with `=` are bounded arithmetic expressions. Numeric input IDs
are variables; supported operations are `+ - * / ^`, parentheses, `min`, `max`,
`abs`, `round`, `pow`, and `payment(principal, annualPercent, years)`. `payment`
calculates a monthly level payment, with the rate expressed as percent (2 means
2%). Literal strings can interpolate any input with `{{inputID}}`.

For example, combine a `principal` slider, a `rate` slider, and a `years` number
input with a metric whose value is `=payment(principal,rate,years)`, format is
`currency`, and unit is `円`. Table cells, chart points, and cards can reference
the same inputs. Label assumptions and units in the document. Fetch current
facts through existing tools before supplying chart or table data.

Documents are validated before execution succeeds. Invalid kinds, unknown
variables/functions, non-finite defaults, duplicate IDs, and invalid ranges
are rejected. Runtime calculation failures display `—`.
Legacy input edits update locally without another LLM call. Rich UI executes
client callbacks; only an explicit user-activated follow-up starts a new
conversation turn through the existing Pi execution path.

The successful document is saved in existing tool activity with the message and
its selected response variant. Input state lives in the timeline row, survives
cell recycling, and returns to the document defaults after reopening the chat.
No database migration or Pi provider routing change is required. Older iOS
records that retained successful GenUI results only in the provider transcript
restore validated documents when loaded, without another tool or model call.

## Mobile presentation

Legacy documents lead with their first metric or card summary. A Results / Inputs
switch keeps that summary visible while editing conditions. The first chart stays
in the results panel; other sections and card assumptions expand on demand.
The selected panel belongs to the timeline row's local state. Compact layouts
use smaller spacing and 160-point charts while retaining 44-point input targets,
wrapping labels, and larger-text layouts. Rich documents use compact mobile
styles with content-measured height, up to 560 points (800 in regular layouts).
Only longer content scrolls within the canvas; no empty status row is reserved.
Below 640px, gaps are capped at 12px and padding at 16px after applying the DIL
4px spacing scale. Ordinary layout containers use intrinsic height rather than
fixed/minimum heights or distributed vertical whitespace, and spacers use 8px.
Media, charts, and explicitly scrollable regions retain authored dimensions;
desktop layout properties are unchanged. Input rows stay inline and reference
links use full-width 44px-or-larger touch targets. These rules apply to saved
rich trees and client code as well as newly generated documents.

## Component compatibility runtime

Rich documents use `title`, optional `subtitle`, and either `ui` or `code`.
`ui` is a component tree with `{type, props, children}`; children may be nodes,
strings, or numbers. `code` uses the bundled compatibility runtime's `DIL.h` builder
and `DIL` state hooks. Optional `state` supplies initial local state. Optional
`resources` maps explicit reference IDs to supplied `title`, `url`, `src`, `text`,
and `mime` content. Rich documents cannot also contain legacy `inputs` or
`components`.

This is an app compatibility API for the supplied component vocabulary, not
ChatGPT's proprietary renderer or a React package. The runtime supplies text,
layout, interactive controls, lists/tables, media, charts, map launchers, and
special content components. A rich document can share local state across its
controls and visualizations. Unknown or unavailable content produces a visible
fallback rather than a fabricated result. Rich documents have no app-defined
fixed document/code byte limit, node/depth limit, or initial state/resource
count limit. Nested JSON arrays and objects and interaction snapshots likewise
have no app-defined size limit. Actual capacity still depends on device memory,
Foundation JSON parsing, JavaScript and WebKit; this is not a guarantee of
unlimited execution or of ChatGPT's undocumented limits. Legacy `components`
retain their original input/component/table/chart/card and arithmetic-parser
limits for compatibility; use `code` for general calculations.

The web runtime runs inside a restricted WKWebView with bundled code. No remote
JavaScript bundles are loaded. `AppBlock` can render content supplied with the
document; `app_block_id`, `bundle_version`, or an entrypoint do not grant access
to ChatGPT app bundles. Proprietary image/video search references, entity
lookup, memory/citation backends, and file references are unavailable unless the
document supplies the corresponding resource. A `query` is not fetched or
silently converted into a result.

Host actions (`copy`, `openUrl`, `issueNewTurn`, and `openEntityDetail`) require
an explicit user interaction and are guarded by the native host. Declarative
events may update/reset local state or request those actions. Rendering,
effects, and restoring saved state do not authorize an external action or a
new model turn. Explicit external URLs use HTTPS. Supplied entity details are
shown locally; unavailable entity lookup returns a visible status.

## Native maps

`MapWidgetV2` displays an interactive native MapKit map directly inside the chat
card, without an open button or sheet. The map follows the web layout and scrolling;
local state changes update or remove it. Supply `points` with a place
`title`/`name`, `address`, or `query`; iOS searches Apple MapKit for the location.
Include the city/address for ambiguous names. Numeric `lat`/`lng` (or
`latitude`/`longitude`) remain supported and skip place search; supplied coordinates
must be complete, finite and in range. `origin` accepts the same shape. Optional
`id` and `group`/`group_id` preserve point identity and grouping. Failed searches
remain visible and prevent routing through an incomplete set of stops. Optional `groups`
accepts group IDs or `{id, title}` objects, and map markers use group colors.
The card shows `title`, `narrative`, and `answer`, with search and route status
on the map. Explicit map presentation actions still require a user gesture;
rendering an inline map does not authorize external actions.

Only `show_route: true` requests actual MapKit directions between supplied stops
in their supplied order. `travel_mode` accepts `driving`, `walking`, or `transit`;
MapKit availability and failures are shown as status text. Routes are never
fabricated. `optimize_stop_order: true` reports that automatic stop optimization
is unsupported. ISO 8601 `arrive_by` or `depart_at` may be supplied for a
two-point route; specifying both or using timed multiple segments reports a
visible unsupported status.

`GenUIDemoFixture` and `GenUIUITests` provide a loan example and interaction
coverage. Launch the simulator app with `-AppStoreScreenshotDemo -GenUIFixture
-ScreenshotScene chat` for the example, optionally adding `-GenUIDarkFixture`.

Run `node --test ios/GenUIRuntimeTests/runtime.test.js` from the repository root
for the dependency-free runtime tests. These exercise typed data interpolation,
local state, guarded actions, native map launch, media fallbacks, and chart
geometry through a lightweight DOM harness. Native coordinate parsing is covered by `GenUIMapTests`. `GenUIRichUITests`
checks shared JavaScript state, reset, native copying, and map presentation.
Launch `-AppStoreScreenshotDemo -GenUIRichFixture -ScreenshotScene chat` for
this example.

### Client code and property semantics

`code` is a JavaScript function body, without JSX or imports. Calculations use
JavaScript `+ - * / **`, `Math.min`, `Math.max`, `Math.abs`, `Math.round`,
`Math.pow`, custom functions, `if`/`else`, loops and array iteration. They are
not restricted to the legacy `components` formula language. Loan repayment,
compound interest and statistics can be implemented locally with DIL hooks:

```js
const [principal, setPrincipal] = DIL.useState(300000);
const monthly = DIL.useMemo(() => {
  const rate = 5 / 1200;
  const months = 30 * 12;
  return principal * rate / (1 - (1 + rate) ** -months);
}, [principal]);
return DIL.h('col', {},
  DIL.h('slider', {value: principal, min: 0, max: 600000, onChange: setPrincipal}),
  DIL.h('text', {}, Math.round(monthly) + ' / month at 5% for 30 years')
);
```

The runtime uses ordinary JavaScript conditionals and iteration, not a separate
proprietary `if`/`each` template syntax. `AppBlock` supports inline component
nodes and client function entrypoints, not arbitrary HTML documents or an
unrestricted browser environment. Network connections, external modules and
native host actions remain restricted.

A basic shared-state example:

```js
const [volume, setVolume] = DIL.useState(65);
return DIL.h('col', {gap: 4},
  DIL.h('slider', {value: volume, min: 0, max: 100, onChange: setVolume}),
  DIL.h('title', {tabularNums: true}, String(volume) + '%'),
  DIL.h('button', {label: 'Copy', onClick: () => GenUI.copy(String(volume))})
);
```

For JSON-only documents, initialize `state`, use `bind: "volume"` on a slider,
and display `{{volume}}` in another node. `onChange` can use
`{type: "setState", key: "volume", value: "$value"}`. Host actions use the same
object format. Hook state must be JSON serializable to survive cell recycling.

The supplied list does not define complete types/enumerations, so this API uses
browser/iOS equivalents: spacing numbers are multiples of 4 px; `useTheme`
returns `light`/`dark`; `useBreakpoint` returns `sm`/`md`/`lg`. Masks support
`#`, `9`, `A`, `*` alphanumeric placeholders. Popovers stay in document flow;
`side`/`align` do not implement portal positioning or collision avoidance.
Selects use the system picker; custom popup side/icon presentation is advisory.
Media queries require results from an existing research tool. CodeBlock is a
displayed/editable excerpt without remote execution or model preview. AppBlock
accepts inline nodes or a client function entrypoint without remote bundles.
Unknown icon names and unresolved proprietary references show a fallback.
