# YamabikoChat Web Pages

Static pages for App Store Connect and in-app legal links.

## Pages

| Page | File | App Store Connect field |
|------|------|-------------------------|
| Marketing | `index.html` | Marketing URL (optional) |
| Privacy Policy | `privacy.html` | **Privacy Policy URL** (required) |
| Support | `support.html` | **Support URL** (required) |
| Terms of Use | `terms.html` | In-app link (recommended) |

## Publish with GitHub Pages

1. Push this `docs/` folder to GitHub (`ios` branch or `main`).
2. Repository **Settings → Pages**
3. Source: **Deploy from a branch**
4. Branch: the branch you use (e.g. `ios`) / folder: **`/docs`**
5. Save and wait for the site URL (typically `https://porarrirr.github.io/yamabikochat/`)

## URLs to register

After Pages is live:

- Marketing: `https://porarrirr.github.io/yamabikochat/`
- Privacy Policy: `https://porarrirr.github.io/yamabikochat/privacy.html`
- Support: `https://porarrirr.github.io/yamabikochat/support.html`
- Terms: `https://porarrirr.github.io/yamabikochat/terms.html`

Update `ios/YamabikoChat/Shared/AppConstants.swift` if you use a custom domain.
