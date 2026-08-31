# Design QA: temporary-chat toggle icon

- Source visual truth (inactive): `/var/folders/5w/7hrzp8fx3b9dh79n6jk19l980000gn/T/codex-clipboard-10e61496-3c13-47c7-9563-bc2843ebc3f6.jpg`
- Source visual truth (selected): `/var/folders/5w/7hrzp8fx3b9dh79n6jk19l980000gn/T/codex-clipboard-f3cdae53-19b0-4875-9975-f511ed46ae4c.png`
- Implementation screenshot (inactive): `/tmp/yamabiko-icon-qa-final.u02kON/69D11BE8-F226-4610-A00F-27D091FF5713.png`
- Implementation screenshot (selected): `/tmp/yamabiko-icon-qa-final.u02kON/46948E8C-BFB0-4F63-9FAD-3D7BBAE93190.png`
- Combined comparison: `/tmp/yamabiko-icon-qa-final.u02kON/reference-vs-implementation-final.png`
- Viewport: iPhone 17 Pro simulator, iOS 26.5, portrait, light appearance
- Component size: 45 × 45 pt; XCUITest element captures are 134 × 134 px at native 3× density
- Comparison normalization: each supplied reference was cropped to the same 134 × 134 px component bounds without scaling; the inactive and selected source/implementation pairs were inspected together
- States: empty normal chat and empty secret chat

## Required fidelity surfaces

- Typography and copy: the icon has no visible text. UI automation verifies the localized accessibility labels `シークレットチャットに切り替え` and `通常チャットに戻す`.
- Spacing and layout: the 21 pt mark is optically centered inside the 45 pt circular control. The source mark's one-pixel left/up optical offset is preserved at 3× density.
- Colors and visual tokens: the mark remains semantic primary color. The outer ring was tuned to the source's thin, restrained gray treatment while keeping dark-mode tinting isolated to the template mark.
- Image fidelity: both three-stroke marks are template assets mechanically extracted from the supplied visual truth. The selected state uses the supplied check shape rather than an overlaid SF Symbol or an approximate hand-drawn path.
- Copy and content: no additional menu or label is introduced by this icon change.

## Comparison history

1. P1: the initial implementation recreated the mark with a custom SwiftUI `Shape`; its three strokes, tail, and selected check did not match the supplied source. The approximation was removed.
2. P2: the first source-derived implementation rendered a 44 pt outer circle, producing a 132 px diameter against the source's approximately 135 px circle. The control was corrected to 45 pt.
3. P2: the first 45 pt capture left the mark one pixel right/down and rendered the outer ring too thick and light. The source's optical center was restored and the ring changed to a 0.45 pt inset stroke at 22% black.
4. Post-fix evidence: the final side-by-side comparison has identical dark-mark bounding boxes for both states (`x 36...96`, `y 37...94`) and no visible P0, P1, or P2 mismatch.

## Verification

- [x] Actual app-rendered inactive and selected states captured from the simulator
- [x] Reference and implementation inspected in one same-size comparison image
- [x] Toggle interaction and both accessibility labels verified by UI automation
- [x] All four primary-action state combinations verified by focused unit tests
- [x] iOS build and focused UI test passed with zero failures
- [x] `git diff --check` passed

## Follow-up polish

None required for this icon fix.

final result: passed

---

# Project information sources design QA

- Source visual truth: `/var/folders/5w/7hrzp8fx3b9dh79n6jk19l980000gn/T/codex-clipboard-f2b8d2ed-065f-474e-856b-177202bcd3a5.png`
- Implementation screenshot: `/Users/porari/.codex/visualizations/2026/08/31/01a05557-07ac-73f0-a21c-8dc768549f4b/project-workspace/implementation-final.png`
- Combined comparison: `/Users/porari/.codex/visualizations/2026/08/31/01a05557-07ac-73f0-a21c-8dc768549f4b/project-workspace/reference-vs-implementation-final.png`
- Viewport: iPhone 17 simulator, portrait, iOS 26.5, 402 × 874 pt
- Source pixels: 1170 × 2532; implementation pixels: 1206 × 2622; both are native iPhone captures
- Normalization: the source was proportionally fit and white-padded to the 1206 × 2622 implementation panel, then both panels were placed side by side without stretching
- CSS size / deviceScaleFactor: not applicable to this native SwiftUI implementation
- State: project detail, empty `情報源` tab selected, `追加` action enabled, bottom project composer visible

## Required fidelity surfaces

- Fonts and typography: native San Francisco typography with a semibold selected tab and bold capsule action.
- Spacing and layout rhythm: project header, two-tab segmented treatment, large empty canvas, centered add action, and persistent bottom composer follow the supplied hierarchy.
- Colors and visual tokens: semantic white background, secondary gray inactive text and selected-tab fill, and a black primary capsule match the reference while preserving YamabikoChat's existing blue project icon.
- Image and icon fidelity: no raster placeholders or recreated artwork are present. Existing SF Symbols are used for project and navigation controls.
- Copy and content: the visible empty state is intentionally limited to `追加`, matching the supplied reference. Added files are shown as a native list only after import.

## Findings

No actionable P0, P1, or P2 mismatch remains. The project name, status-bar state, bottom-composer capabilities, and existing YamabikoChat navigation chrome are product-owned differences rather than reference drift.

## Comparison history

1. Initial implementation added an explanatory document icon and sentence above the primary action. This was a P2 fidelity mismatch because the supplied empty state is deliberately sparse.
2. The icon and explanatory copy were removed, leaving only the black `追加` capsule.
3. The first corrected capture placed the action too high relative to the reference. The empty-state geometry was adjusted to 58% of its available content height.
4. The final combined comparison confirms aligned tab hierarchy, whitespace, action placement, and persistent bottom composer.

## Primary interactions verified

- The `チャット` and `情報源` tabs switch project-detail content.
- `追加` is visible, accessible, and hittable in the empty state.
- The file importer accepts multiple files.
- Imported files render in the project source list and can be removed.
- The bottom project composer remains visible in the information-sources state.

## Implementation checklist

- [x] Native project information-sources tab
- [x] Empty-state add action matching the reference
- [x] Multi-file import and file list
- [x] Deterministic UI automation capture
- [x] Source and implementation inspected in one combined comparison
- [x] Native iOS build and focused regression tests pass

final result: passed

---

# Design QA: selection-aware chat composer

- Source visual truth: `/var/folders/5w/7hrzp8fx3b9dh79n6jk19l980000gn/T/codex-clipboard-7890948e-581f-41e2-bcfb-c9d12a5084de.png`
- Implementation screenshot: `/Users/porari/kaihatu/ios/yamabikochat/design-qa-composer-implementation.jpeg`
- Combined comparison: `/Users/porari/kaihatu/ios/yamabikochat/design-qa-composer-comparison.png`
- Viewport: iPhone 17 simulator, portrait, iOS 27.0, software keyboard visible
- Source pixels: 1170 × 2532
- Implementation capture pixels: 456 × 972; device screen normalized from a 406 × 880 crop to 1170 × 2532 for comparison
- CSS size / deviceScaleFactor: not applicable to this native iOS implementation
- State: assistant text selected with “チャットで質問する”, long follow-up entered, composer focused, software keyboard visible

## Full-view comparison evidence

The combined comparison verifies the requested behavior rather than cloning unrelated ChatGPT chrome. In both states, the selected passage appears as a blue, single-line, truncated preview at the start of the composer; the editable follow-up begins beside it; subsequent lines reclaim the full composer width; the composer remains above the software keyboard; and the add, microphone, and send controls remain visible.

The reference uses ChatGPT dark mode and different conversation content, while YamabikoChat intentionally retains its own light theme, navigation, SF Symbols, and product copy.

## Focused composer comparison

The composer is large and readable in the normalized full-view comparison, so a separate crop was not needed. The critical first-line exclusion and full-width continuation are directly visible in `design-qa-composer-comparison.png`.

## Required fidelity surfaces

- Fonts and typography: native San Francisco typography, 16-point composer text, matching line height between the selected preview and editable text, one-line tail truncation for the preview, and natural multi-line wrapping for the question.
- Spacing and layout rhythm: the preview reserves at most half of only the first line; at least 120 points remain editable on that line; later lines span the full card; bottom controls and keyboard clearance remain intact.
- Colors and visual tokens: selection preview uses the existing YamabikoChat accent token; text, card background, separators, and send control continue to use semantic system colors. Theme differences from ChatGPT are intentional product identity, not drift.
- Image and icon fidelity: no raster placeholders or recreated artwork are present. Existing SF Symbols are used for the selection, add, microphone, and send controls.
- Copy and content: selected source text is preserved for submission and accessibility while its visual preview is normalized to one line; the editable suffix remains user-controlled.

## Findings

No actionable P0, P1, or P2 mismatch remains for the requested interaction.

## Comparison history

1. Earlier P1: the selection preview and editor were separate horizontal stack columns, so every wrapped question line remained squeezed into the right-hand column. Unbounded width proposals could also produce invalid measurement values.
2. Fix: the editor now owns the full composer width, with a TextKit exclusion path reserving only the first-line preview area; non-finite measurement proposals are rejected before UIKit sizing.
3. Post-fix evidence: the simulator screenshot shows the first line beginning beside the truncated selection and all following lines using the full card width with the software keyboard visible.

## Implementation checklist

- [x] Selection preview stays single-line and truncated.
- [x] First-line editor retains a usable minimum width.
- [x] Subsequent lines wrap across the full composer.
- [x] Non-finite layout proposals cannot create invalid geometry.
- [x] Composer controls remain visible above the software keyboard.
- [x] Native iOS build succeeds.

## Follow-up polish

None required for this fix.

final result: passed

---

# Design QA: reasoning-effort slider

- Source visual truth: `/var/folders/5w/7hrzp8fx3b9dh79n6jk19l980000gn/T/codex-clipboard-b883615e-c73d-441e-b352-9065a8625cc5.png`
- Implementation screenshot: `/Users/porari/.codex/visualizations/2026/08/28/01a0467c-1533-7b80-aa87-003e67489601/reasoning-effort/reasoning-effort-slider-smooth-medium.png`
- Full normalized comparison: `/Users/porari/.codex/visualizations/2026/08/28/01a0467c-1533-7b80-aa87-003e67489601/reasoning-effort/reference-vs-smooth-implementation.png`
- Focused normalized comparison: `/Users/porari/.codex/visualizations/2026/08/28/01a0467c-1533-7b80-aa87-003e67489601/reasoning-effort/reference-vs-smooth-implementation-focused.png`
- Viewport: iPhone 17 simulator, portrait, iOS 26.5, dark appearance, software keyboard visible
- Source pixels: 1170 x 2532; implementation pixels: 1206 x 2622; both are native 3x-density iPhone captures
- Normalization: full captures were proportionally scaled and padded to equal 585 x 1266 panels before horizontal comparison; focused crops were normalized to equal 585 x 325 panels
- CSS size / deviceScaleFactor: not applicable to this native SwiftUI implementation
- Captured state: standard single-model chat, `gpt-5.6-terra`, exact effort `medium`, composer focused, software keyboard visible, effort panel open

## Primary interactions verified

- With no focused composer or software keyboard, the reasoning-effort meter is absent.
- Focusing the composer and showing the software keyboard reveals the meter for a supported model.
- Tapping the meter opens the slider without dismissing the keyboard.
- During a drag, the thumb and selected fill follow the finger continuously instead of jumping between stops.
- Crossing a stop previews its exact label and triggers selection feedback; the supported discrete value is committed only when the drag ends.
- The slider selects only values supported by the active model/provider contract.
- Moving from `medium` to `ultra` updates the exact English value and persists it through the existing Pi Agents configuration path.
- The full-screen transparent dismissal target closes the panel without adding a second execution or fallback path.

## Required fidelity surfaces

- Fonts and typography: native San Francisco typography; centered semibold model-and-effort label; model and provider values remain exact and are not translated by the app.
- Spacing and layout rhythm: label and wide capsule sit immediately above the software keyboard; the chat remains visible through a short bottom gradient; the composer is visually replaced only while the panel is open.
- Colors and visual tokens: semantic dark-mode colors, white selected fill, black thumb, muted stop dots, and restrained material blur match the reference hierarchy while remaining adaptive.
- Image and icon fidelity: no bitmap substitutes are used. The composer trigger is a dynamic SF Symbol gauge whose needle reflects the current discrete value.
- Copy and content: the captured label is `GPT-5.6-Terra medium`; localized upstream values, such as an OpenRouter-provided `中程度`, are preserved verbatim rather than normalized or translated.

## Findings

No actionable P0, P1, or P2 mismatch remains. The reference has three illustrative stops, while the implementation correctly renders all six authoritative `gpt-5.6-terra` effort values; therefore `medium` appears at the second stop rather than the center. Conversation content, navigation chrome, and keyboard version remain YamabikoChat/iOS-owned surfaces rather than cloned reference content.

## Comparison history

1. Initial capture: `reasoning-effort-slider-medium.png`. P1 mismatch: the light appearance and opaque white panel did not match the dark, floating reference treatment.
2. First correction: switched the deterministic fixture to dark appearance and removed the enclosing card. Capture: `reasoning-effort-slider-medium-dark.png`.
3. Second capture review found a P2 mismatch: full-screen material obscured too much conversation context. The material was constrained to a short bottom gradient.
4. Third capture review found a P2 mismatch: composer controls remained visible behind the slider. The composer is now visually hidden with opacity while retaining its first-responder state, so the keyboard does not collapse.
5. Post-fix evidence: the final full and focused comparisons show a floating label and capsule over a dark gradient, with the software keyboard retained and exact model effort visible.
6. Motion refinement: the original implementation derived the thumb position directly from the persisted discrete selection, causing visible jumps and synchronous preference writes while dragging. The thumb/fill now use a continuous clamped drag fraction, labels preview only at stop boundaries, persistence occurs once on release, and the thumb settles to the selected stop with a short smooth animation. The refreshed full and focused comparisons confirm no resting-state visual regression.

## Verification

- [x] Focused reasoning policy/repository/view-model tests pass for Codex, SuperGrok, Gemini, OpenRouter, and models.dev.
- [x] Discrete ordering, exact-label preservation, focus/keyboard gating, track mapping, and continuous between-stop drag-fraction tests pass.
- [x] UI automation verifies hidden-before-focus, visible-with-keyboard, panel presentation, a real drag from `medium` to `ultra`, exact final label, and retained keyboard.
- [x] Native iOS simulator build succeeds with code signing disabled.
- [x] Full-view and focused source/implementation comparisons were inspected together.

## Follow-up polish

None required for this feature.

final result: passed

---

# Speech recording bar design QA

- Source visual truth: `/var/folders/5w/7hrzp8fx3b9dh79n6jk19l980000gn/T/codex-clipboard-82dae369-21b1-43ce-a5db-48cc6a497f6e.png`
- Implementation screenshot: `/tmp/yamabiko-speech-recording-ui-final-v2.png`
- Focused comparison: `/tmp/yamabiko-speech-ui-comparison-final.png`
- Viewport: iPhone 17 simulator, 402 × 874 pt
- Source pixels: 1170 × 287 px
- Implementation pixels: 1206 × 2622 px at 3× (402 × 874 pt)
- Focused crops: source 970 × 160 px; implementation 1126 × 180 px
- Density normalization: component proportions were compared using native-pixel focused crops, vertically stacked on a shared 1126 px canvas without stretching either crop.
- State: active speech recording with representative waveform activity and enabled send action. The simulator cannot initialize `SFSpeechRecognizer`, so the screenshot uses a DEBUG-only presentation argument while rendering the production SwiftUI component.

## Full-view comparison evidence

The implementation screenshot shows the recording bar in its real bottom-composer position on the iPhone 17 viewport. It respects the existing chat screen's 14 pt horizontal margins and bottom safe area. No clipping, overlap, or persistent-control overflow is visible.

## Focused comparison evidence

The focused comparison places the supplied reference above the rendered implementation. The pill silhouette, control order, centered waveform, dark palette, circular controls, stop glyph, and white send button follow the reference. A focused comparison was required because the reference contains only the recording control rather than a complete app screen.

## Required fidelity surfaces

- Fonts and typography: no visible text exists in the reference or implementation component. Accessibility labels supply the semantic names without adding visible copy.
- Spacing and layout rhythm: the 56 pt pill, 34 pt visual circles inside 44 pt tap targets, 8 pt edge padding, and expanded waveform closely match the source proportions.
- Colors and visual tokens: dark charcoal fill, subtle light border, translucent secondary controls, white glyphs, and white primary action match the source hierarchy in both light and dark app contexts.
- Image quality and asset fidelity: the reference contains no raster imagery or brand assets. All controls use native SF Symbols; the waveform is live audio data rendered as vector capsules and remains sharp at every scale.
- Copy and content: there is no visible component copy. Voice actions have localized accessibility labels.

## Findings

No actionable P0, P1, or P2 differences remain.

- P3: The reference has a slightly more dimensional surface highlight than the app's flatter system-aligned charcoal treatment. This is acceptable because the implementation keeps the existing YamabikoChat visual language and contrast behavior.

## Comparison history

1. Initial implementation screenshot: `/tmp/yamabiko-speech-recording-ui.png`
   - P2: circular controls occupied too much of the pill height.
   - P2: waveform was visually too short relative to the available center span.
2. Fixes applied:
   - Reduced the bar from 64 pt to 56 pt.
   - Kept 44 pt accessible tap targets while reducing visible circles to 34 pt.
   - Increased waveform bar width and spacing to use the center span.
3. Post-fix evidence:
   - `/tmp/yamabiko-speech-recording-ui-final-v2.png`
   - `/tmp/yamabiko-speech-ui-comparison-final.png`
   - The earlier P2 proportion and waveform-span differences are resolved.

## Primary interactions verified

- Cancel stops recognition and restores the input text that existed before recording.
- Stop ends recognition while retaining the transcription.
- Send ends recognition and sends the current transcription.
- Live waveform history stays at a fixed size and clamps audio levels to the display range.
- Accessibility identifiers and labels are present for all three actions.

## Implementation checklist

- [x] Recording-only composer state
- [x] Live microphone waveform
- [x] Cancel, stop, and send semantics
- [x] Accessible 44 pt tap targets
- [x] Build and focused regression tests
- [x] Simulator visual comparison

final result: passed
