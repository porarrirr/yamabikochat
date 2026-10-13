# GenUI: recovered implementation and evidence

Reference: `/Users/porari/kaihatu/codeanal/analysis/`. Read
`GENUI-REPORT.md`, `GENUI-UI-ELEMENTS.md`, then the expanded Valdi modules.
This implementation uses recovered client code and data, rather than merely
recreating components with similar names. The primitive host is still an iOS
WebKit/SwiftUI adaptation; importing templates does not imply full Valdi parity.

## Recovered assets

| Evidence | Included implementation |
| --- | --- |
| `dil_generated_components.valdimodule/src__restricted__components__*.generated.js` | All 283 `componentSource` JavaScript expressions, preserved in `reference-components.js` and loaded as lazy factories |
| `dil_icon_assets.valdimodule/res.assetpackage`, `LucideIconAliases.js` | 2,511 original SVGs and original alias table, in `reference-icons.js` |
| `DILColorsDefinition`, `DILTextTypography`, `DILWidgetSizes`, `DILSelectControlMetrics` | Original color palettes, iOS typography, control and select metrics in `reference-tokens.js` |
| `cel.valdimodule` | All 16 original CEL bytecode modules executed by the compatible Valdi QuickJS engine through `GenUICELBridge` |
| `dil_charts/SvgChart`, `PieChart` and their color/layout/XML dependencies | Original pure SVG rendering exports executed in the same native engine; 26 bytecode modules including CEL are bundled |
| `DILRootComponent`, `DILSpacingAttributes`, original `Card`/`Button`/`Icon` sources | Native mobile detection, 4px spacing without compact caps, scoped themes, recovered dimensions and icon tint behavior |

`GenUI-reference-components.json` records each recovered source SHA256,
observed property names and observed state fields. Field extraction is an index,
not a complete schema or a substitute for reading the source. `genui_reference`
is a read-only tool on the existing local tool registry; it returns component
names, contracts and paginated original source so the model can populate the
actual `__state` shape rather than invent an approximate widget.

## Reproduction

```sh
python3 ios/scripts/recover-genui-reference.py \
  --analysis /Users/porari/kaihatu/codeanal/analysis \
  --valdi /path/to/Valdi
cd ios
xcodegen generate
```

The script requires clang, zstd and a Valdi checkout containing
`third-party/quickjs`. Valdi module files carry a four-byte header followed by
QuickJS bytecode. The extractor deserializes the compatible bytecode and reads
module exports. It does not infer JavaScript from identifier strings. Generated
component expressions remain unchanged; platform hooks are provided separately
by `runtime.js`. Keep asset and catalog generation together.

The native QuickJS engine has a 32MiB memory budget, a 512KiB stack budget and a
100ms per-call interrupt budget. Its entry points accept only local expression
bindings or chart data. It has no model, network or general native-action APIs.
The class-registration shims used to load chart modules are not used for
rendering: the pure original SVG exports perform the actual chart calculation.

## Client behavior and limits

Original generated components run against the DIL hook/element facade, including
state, memo/effects, timers, local app data, breakpoints and scoped themes.
Supplied data drives the original calculations and composition. CEL properties
prefixed with `$` are evaluated using the original resolver and scope. Exact
chart SVG output is imported into the WebKit DOM. Lottie uses a bundled SVG
player; Markdown uses bundled markdown-it with raw HTML disabled. YouTube uses
an isolated native WKWebView player, and maps use MapKit.

Pi's standard parsed tool-call updates supply incremental GenUI previews.
Validated updates reuse the existing canvas and preserve edited controls and
keyed hook state. No alternate AI API or provider path is involved. Explicit
follow-ups continue through the existing Pi execution path. Prefill actions update
the existing composer without sending; email actions open a mail-client draft.

Original server-bound actions, widget refresh, opaque proprietary image/file
references and backend data lookup cannot execute without the original service
contract. They return an explicit unsupported reason. Supplying verified data
or explicit media URLs enables local rendering; a widget name or query does not
manufacture live results. Local copy, share, composer prefill, mail drafts, supplied entity details, explicit
HTTPS links and supplied media presentations use the existing guarded host.

Remaining client differences must not be described as server limitations:
Valdi's full renderer, animation timelines and portal collision behavior are
not reproduced by WebKit. Flashcard flip/stack and enter animations are adapted;
exit/shuffle/dismiss/restore choreography is not verified as identical. Audio
currently uses native browser controls rather than the source waveform UI.
Chart SVG generation is original, while pointer hit testing is adapted. Hook
persistence is row-local, not the original remote view-state synchronization.
No running source-app screenshot comparison has established pixel identity.

## Validation

Runtime tests initialize all 283 factories and exercise representative resolved
components, restored state, bindings, streaming replacement, themes and actions.
Factory initialization alone does not prove every component's data-dependent
branch or backend integration. Native tests cover source lookup, CEL, original
SVG output, validation, host policy, Pi previews and tool exposure. UI tests run
the actual original timer, clock, converter and checklist inside the conversation
and capture light/dark views. The original-component fixture uses deterministic
supplied values, not live weather, finance or service data.

```sh
node --test ios/GenUIRuntimeTests/runtime.test.js
cd ios/PiRuntime && node --test test/genui-preview.test.js
```

Launch `-AppStoreScreenshotDemo -GenUIRichFixture -GenUIOriginalFixture
-ScreenshotScene chat`; add `-GenUIDarkFixture` for dark appearance.
