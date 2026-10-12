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
components are text, metrics, tables, line charts, and card grids.

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
variables/functions, non-finite defaults, duplicate IDs, invalid ranges, and
oversized documents are rejected. Runtime calculation failures display `—`.
Legacy input edits update locally without another LLM call. Rich UI executes
client callbacks; only an explicit user-activated follow-up starts a new
conversation turn through the existing Pi execution path.

The successful document is saved in existing tool activity with the message and
its selected response variant. Input state lives in the timeline row, survives
cell recycling, and returns to the document defaults after reopening the chat.
No database migration or Pi provider routing change is required.

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
fallback rather than a fabricated result. Documents are bounded to 256 KiB;
code is bounded to 64 KiB, trees to 512 nodes and 32 levels, and initial state
and resources to 64 keys each.

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

`MapWidgetV2` displays supplied information inline and opens a native MapKit
sheet only when the user presses its map button. Supply `points` with numeric
`lat`/`lng` (or `latitude`/`longitude`), optional `title`/`name`, `address`, `id`,
and `group`/`group_id`. `origin` uses the same coordinate shape. Coordinates must
be finite and in range; address-only points are unsupported. Optional `groups`
accepts group IDs or `{id, title}` objects, and the sheet shows group colors,
selectable point cards, `title`, `narrative`, and `answer`. Opening a point in
Apple Maps requires another explicit button press.

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

`code` is a JavaScript function body, without JSX or imports:

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
