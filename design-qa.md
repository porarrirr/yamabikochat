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
- Implementation screenshot: `/Users/porari/.codex/visualizations/2026/08/28/01a0467c-1533-7b80-aa87-003e67489601/reasoning-effort/reasoning-effort-slider-medium-final.png`
- Full normalized comparison: `/Users/porari/.codex/visualizations/2026/08/28/01a0467c-1533-7b80-aa87-003e67489601/reasoning-effort/reference-vs-implementation.png`
- Focused normalized comparison: `/Users/porari/.codex/visualizations/2026/08/28/01a0467c-1533-7b80-aa87-003e67489601/reasoning-effort/reference-vs-implementation-focused.png`
- Viewport: iPhone 17 simulator, portrait, iOS 26.5, dark appearance, software keyboard visible
- Source pixels: 1170 x 2532; implementation pixels: 1206 x 2622; both are native 3x-density iPhone captures
- Normalization: full captures were proportionally scaled and padded to equal 585 x 1266 panels before horizontal comparison; focused crops were normalized to equal 585 x 325 panels
- CSS size / deviceScaleFactor: not applicable to this native SwiftUI implementation
- Captured state: standard single-model chat, `gpt-5.6-terra`, exact effort `medium`, composer focused, software keyboard visible, effort panel open

## Primary interactions verified

- With no focused composer or software keyboard, the reasoning-effort meter is absent.
- Focusing the composer and showing the software keyboard reveals the meter for a supported model.
- Tapping the meter opens the slider without dismissing the keyboard.
- The discrete thumb selects only values supported by the active model/provider contract.
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

## Verification

- [x] Focused reasoning policy/repository/view-model tests pass for Codex, SuperGrok, Gemini, OpenRouter, and models.dev.
- [x] Discrete ordering, exact-label preservation, focus/keyboard gating, and track mapping tests pass.
- [x] UI automation verifies hidden-before-focus, visible-with-keyboard, panel presentation, exact `medium` label, `ultra` selection, and retained keyboard.
- [x] Native iOS simulator build succeeds with code signing disabled.
- [x] Full-view and focused source/implementation comparisons were inspected together.

## Follow-up polish

None required for this feature.

final result: passed
