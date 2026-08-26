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
