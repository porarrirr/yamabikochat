# GenUI on iOS

GenUI uses the existing local tool registry and Pi Agents execution stream.
Provider/model resolution, API communication, token usage and follow-up turns
remain on the standard execution path. Tool exposure follows the existing
conversation settings and model capability checks. Apple PCC retains its public
SDK JSON-string `document` envelope; both envelope and direct arguments reach
the same validator.

## Usage policy

`SystemPromptComposer.genUIToolInstructions` owns the category and presentation
policy; tool descriptions retain concise invocation guidance. These instructions
are included only when GenUI is enabled for the conversation.

- Weather, currency/unit conversions, current time, and sports require widget
  search on each relevant request and display when a suitable widget is usable.
- Maps require search/display for three or more recommendations in the same
  region or route display.
- Product comparisons are recommended uses; data analysis uses charts when
  helpful. General questions and writing normally use text.
- Search with `genui_reference(componentName:"*", query:...)`, inspect the chosen
  contract, and render with `genui`. Searches match component-name substrings and
  do not retrieve live data. Reuse previously retrieved exact contracts.
- If no suitable widget, verified data, or supported functionality is available,
  answer in text and explain material limitations. Never fabricate live data.
- There is no usage quota. Prefer one widget per purpose, avoid duplication and
  decoration, and use forms only to collect multiple required inputs together.
  Convey key facts in text alongside the UI without repeating its full contents.

## Original component implementation

The app bundles all 283 recovered generated component sources, 2,511 original
SVG icons, original palettes and iOS typography/control metrics. Canonical
components execute their original source expressions with the local DIL facade.
Read [GenUI-reference.md](GenUI-reference.md) for extraction, evidence, tests and
remaining differences. This is substantially more than a name-alias catalog,
but does not claim that the whole native Valdi renderer has been ported.

Use `genui_reference` with `componentName:"*"` to list original components, then
request the desired component's source. Inspect its state shape and provide
verified data in `__state`. Long source results support `sourceOffset` and
`maxCharacters` pagination. Observed state-field lists are an index, not a full
type definition. Do not guess sports/weather/finance data or backend actions.

A rich document has a nonempty `title`, optional `subtitle`, and either `ui` or
`code`; optional `state` initializes local values and `resources` supplies
explicit referenced content. The document title is tool metadata, not an extra
heading automatically inserted into the canvas. A component owns its heading.

```js
return DIL.h('DigitalTimerWidget', {
  __state: {start_time: 90, auto_start: false, done_label: '完了'}
});
```

`ui` accepts `{type, props, children}` trees. `code` is a JavaScript function
body without imports or JSX, with `DIL`, `GenUI`, `state` and `resources` in
scope. `DIL.h` composes elements or canonical components. Calculations use
ordinary JavaScript, including `Math.pow`, loops and array operations. Hooks
provide shared local state, effects, memoized values, refs, constants, current
time, theme, breakpoints and local app data. Hook values must be JSON serializable
to survive timeline-cell recycling.

```js
const [volume, setVolume] = DIL.useState(65);
return DIL.h('col', {gap: 4},
  DIL.h('slider', {value: volume, min: 0, max: 100, onChange: setVolume}),
  DIL.h('title', {tabularNums: true}, String(volume) + '%'),
  DIL.h('button', {label: 'Copy', onClick: () => GenUI.copy(String(volume))})
);
```

JSON trees may use `bind:"volume"`, `{{volume}}` interpolation, and
`{type:"setState", key:"volume", value:"$value"}` callbacks. Intrinsics support
`Each` with `items`/`of`, `itemName` and `indexName`, `Scope` with local values,
and `Show`/`Show.Else`. Properties prefixed with `$` evaluate CEL with the
original native CEL resolver and scope, rather than an independently invented
expression language.

Hook state and document state are independent. An object `setState` action writes
`state.volume`; it cannot update the `volume` returned by `DIL.useState`, even if
their names match. In code, connect a controlled input with `value: volume,
onChange: setVolume`, then compute its explanation/result from `volume`. With
document bindings, initialize `state.volume`, use `bind:"volume"`, and read
`state.volume` or `{{volume}}`. Syntax validation cannot establish that these
connections work. Verify each selection changes its dependent content. Existing
saved code needs a corrected document; new instructions do not rewrite it.

## Explanatory UI quality

Choose a visual structure for the concept: connected list stages or SVG for a
process, a responsive `grid` with `minChildWidth` for comparisons, and inputs
with a live result and worked expression for calculations. A paragraph-only
card stack does not explain relationships. The advertised tool example uses
an authentication stepper (explicitly a local demo); a tested powers calculator
also provides a development fixture. In both,
all essential stages and explanations remain visible while controls update.
Use `sm`/`md`/`lg`/`xl` typography tokens and avoid repeated outer padding.

The October 2026 authentication diagnostic used only basic elements, not a
recovered template. Its authored line breaks were collapsed by HTML whitespace
handling. Plain `text`, `title`, `caption`, `label`, and list-item labels and
descriptions now preserve newlines while wrapping. This also covers recovered
components using those primitives and previously saved documents.
`preserveWhitespace:true` additionally preserves spaces; explicit `false` on
text primitives restores normal collapsing. Markdown and SVG retain their
own whitespace behavior. This corrects rendering, but does not turn old prose
into a newly authored interactive diagram.

## Rendering and state

Spacing numbers use the original 4px unit without mobile spacing caps. Authored
height, flexible spacers and alignment are retained. Native iOS is mobile even
on a wide viewport. `useTheme()` returns `{theme,isDark,isLight}` and respects
scoped component themes. `useBreakpoint(token)` uses the source thresholds:
xs380, sm576, md768, lg1024, xl1280 and 2xl1536. Text/control sizes, palettes,
card variants and SVG icon aliases follow recovered exports. Unknown icons
produce a diagnostic rather than an invented substitute symbol.

The canvas fits its measured content height inside the conversation. Native
row-owned height and layout revisions keep collection-cell measurement and hit
areas current. Keyed DOM reconciliation retains control identity, focus and
numeric drafts. Snapshots retain local bindings and keyed component hooks.
Rendering errors are isolated to the affected subtree and sent to diagnostics.

Pi's standard `message_update` tool-call events provide already-parsed arguments
for incremental GenUI previews. Only validated documents update the canvas.
The preview does not execute a second tool, create a provider transcript result
or start another model request. Updates retain user-edited values and component
state. `GenUIRuntime.applyPatch` also supports atomic local JSON Pointer
add/replace/remove/append batches for declarative trees.

## Charts and media

Rich charts use explicit type and supplied data. The actual iOS host calls the
original `renderChartSvg` / `renderPieChartSvg` exports in native QuickJS;
color/layout/XML dependencies are bundled with them. The existing local SVG
renderer handles scatter plots and missing samples on iOS because the recovered
renderer renders scatter as bars and converts missing samples to zero. Crowded
bar categories use local horizontal rows with full wrapped labels, a shared scale,
visible values, and consistent series colors. Short categories retain vertical bars. It also
runs in the dependency-free browser test harness. Pie values must be finite and
nonnegative with a positive total before either renderer is called. Do not infer
chart type from IDs or titles. Pointer hover integration is adapted to WebKit.
Explicit series and axis keys take precedence. Without series, the conventional
`value` column remains the default; otherwise numeric columns become series and
a single text column supplies category labels. Missing samples stay missing.
For ambiguous tables, supply `series:[{dataKey:"score"}]` and `xAxis:"label"`.
`series`, `xAxis`, and `yAxis` may also be supplied on the chart props alongside
`content`; explicit fields inside `content` take precedence. Failed charts retain
alternative text, display the rendering reason, and send a warning to Diagnostics.

Markdown uses bundled markdown-it and safe DOM construction; raw HTML is
disabled. MathJax renders math. Lottie uses the bundled SVG player. Supplied
images support a local image presentation; explicit shares use the iOS share
sheet. YouTube playback runs in an isolated media WebView with no GenUI action
or CEL bridge. Original server image references still require explicit resolved
URLs. Audio currently uses browser audio controls.

`MapWidgetV2` hosts MapKit inline. Supply complete finite coordinates, or a
place title/address/query that MapKit can search. Groups preserve marker
identity/colors. Only `show_route:true` requests actual directions in supplied
stop order; supported modes are driving, walking and transit. Failures remain
visible. Automatic stop-order optimization is unsupported; timed routing accepts
one arrival/departure time for a two-point route, not multiple timed segments.

## Host boundaries

The canvas loads bundled executable assets in restricted WKWebView. Explicit
HTTPS media URLs may load as resources; there is no remote executable-bundle
loader. `AppBlock` supports supplied content/local entrypoints, not proprietary
app bundle retrieval. Copy, link, share, supplied entity details and new-turn
host actions require an actual user gesture. `prefill_composer` inserts a draft
through the existing composer callback without sending. `email.mailto` opens a
mail-client draft using encoded recipient, subject and body fields. Effects, restoration and rendering
never authorize an external action or a new model turn.

Widget refresh, original server actions, proprietary backend lookup, opaque
image/file/citation references and remote view-state synchronization require the
original service contract. Unsupported operations return a visible reason.
These service exclusions do not excuse client-renderer differences: remaining
motion, portal and control-presentation differences are documented separately in
[GenUI-reference.md](GenUI-reference.md).

## Legacy documents

Existing documents with `inputs` and `components` remain supported. Inputs are
sliders, numbers, numeric selections, text and toggles; components include text,
metrics, tables, charts and cards. This older API retains its bounded arithmetic
parser: strings starting with `=` support numeric variables, arithmetic, `min`,
`max`, `abs`, `round`, `pow`, and `payment(principal, annualPercent, years)`.
The latter computes a monthly level payment using annual percent units.

Legacy `kind:"chart"` uses `chartType:"line"` or `"pie"`; omission preserves
the historical line default. Pie requires one series, finite nonnegative values
and a positive finite total. Invalid edited values show an unavailable result.
Rich documents cannot mix `ui`/`code` with legacy `inputs`/`components`.

## Development

Regenerate `ios/YamabikoChat.xcodeproj` from `ios/project.yml` after structural
changes. Run the runtime and native GenUI suites, and UI interaction coverage
for visible changes. The original fixture uses actual recovered components with
deterministic supplied inputs:

```sh
node --test ios/GenUIRuntimeTests/runtime.test.js
cd ios/PiRuntime && node --test test/genui-preview.test.js
```

Launch `-AppStoreScreenshotDemo -GenUIRichFixture -GenUIOriginalFixture
-ScreenshotScene chat`, optionally `-GenUIDarkFixture`. The budget/flow fixtures
remain available for backward-compatibility checks. Factory initialization tests
cover all 283 components; representative resolved-widget tests do not imply all
possible server data shapes and interaction branches are verified.
