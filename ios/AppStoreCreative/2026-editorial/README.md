# YamabikoChat — Editorial AI / 2026

## Research and art direction

Reviewed 2026-10-08. iOS/iPadOS 27 introduces creative assets for product page headers and search results; custom product pages themselves predate iOS 27.

- [Apple asset best practices](https://developer.apple.com/app-store/asset-best-practices/): clear focal point, central safe area, legible short text, authentic app experience. No unverified recognition, pricing, URLs or other marketplace branding.
- [Apple creative asset specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications): header PNG 3840 × 1646; search image 3:2, 1920 × 1280 to 3840 × 2560; no alpha channels.
- [Apple custom product pages](https://developer.apple.com/app-store/custom-product-pages/): independently configurable campaign pages and review.
- [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).
- [DevScope, July 2026](https://devscope.love/articles/app-store-screenshot-design-patterns/): one idea per image, large high-contrast type, consistent palette, specific real content. This is qualitative design guidance, not proof of conversion uplift.
- [2026 typography trends](https://www.creativebloq.com/design/fonts-typography/breaking-rules-and-bringing-joy-top-typography-trends-for-2026): distinctive typography and craft.
- [2026 graphic design trends](https://www.creativebloq.com/design/graphic-design/texture-warmth-and-tactile-rebellion-the-big-graphic-design-trends-for-2026): tactile materials and human expression.

Swiss International Typographic Style supplies the flush-left grotesk type, alignment, restrained palette and negative space. Editorial Design supplies the masthead, typographic hierarchy, rule and pacing. Cut-paper speech silhouettes express dialogue; charcoal, ivory and burnt orange follow the existing app icon. Creative artwork is not presented as an app screenshot. Existing approved app screenshots are inherited by copying the released 0917 product page.

## Deliverables

- `header-3840x1646.png`: product page header, opaque PNG.
- `search-1920x1280.png`: search results creative, opaque PNG.
- `header-master.png`, `search-master.png`: original built-in ImageGen output.
- `prompts.json`: exact generation prompts and workflow.

Built-in ImageGen was used, without API/CLI fallback. Masters were resampled with macOS sips solely to the required upload dimensions; the header upload is upscaled from the generated master, not native 3840-pixel generation. No generated app UI is used. Image dimensions and absence of alpha were checked with sips.

## App Store Connect

App: YamabikoChat - APIキーで使うAIチャット (6771687018).

Reference name: YamabikoChat — Editorial AI / 2026.

Custom page editor: https://appstoreconnect.apple.com/apps/6771687018/distribution/productpages/a7a0800e-ebdd-48ee-8fcf-42c410ede1c7

Product page ID: a3c43a4d-eb72-424b-a751-e94da4ab48db.

Completion status is recorded in `connect-status.md` after upload and review submission verification.
