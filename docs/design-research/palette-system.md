# 2026 premium palette system

Four six-colour palettes, wired through `AppPalette → AppColors → ThemeData →
every screen`. Premium Blue is the new default; the eight earlier identities
remain selectable so existing users keep their stored choice.

## The palettes

| Palette | Brand / deep | Highlight | Surfaces |
|---|---|---|---|
| **Premium Blue** (default) | `#5483B3` steel blue / `#021024` deep midnight | `#C1E8FF` ice blue | light `#F2F8FF`; dark `#021024` → `#052659` → `#0A3468` |
| **Deep Navy** | `#253745` navy / `#06141B` | `#CCD0CF` cool grey | light `#F2F5F6`; dark `#06141B` → `#11212D` → `#253745` |
| **Soft Pastel Teal** | `#5D6B6B` slate teal / `#384A4A` | `#F7CBCA` soft pink | light `#F1F7F7`; dark `#0E1818` → `#1B2A29` → `#243635` |
| **Plum & Blush** | `#854F6C` mauve / `#190019` plum | `#DFB6B2` dusty blush | light `#FFF7F2`; dark `#190019` → `#2B124C` → `#522B5B` |

The six supplied colours per set map to: `deep`, `brand`, `mid`, `bright`,
`accent`/`lime`, and the light neutral surfaces/borders. Two extra tints are
derived only where a surface/step is needed (for example a deeper `darkSurface`
derived from the palette's navy or plum).

## What is palette-driven

- **Canvases and surfaces**: light background, light surface/muted, borders,
  dark canvas, dark card, raised dark surface, dialog/sheet overlay.
- **Brand ramp and every gradient**: primary fill, hero/balance ramp, selected
  nav chip, action gradients, ring arc, FAB, logo glow.
- **Glass**: the premium palettes set `glass: true`, so cards are translucent
  and the tinted dark canvas shows through; legacy AMOLED palettes stay opaque.
- **Highlights**: the cycle pill, today's bar and category bars use the
  palette's highlight/`lime`; the ink on that highlight is derived from the
  palette's `deep` so pink/ice/blush pills never keep an emerald-green label.
- **Category hues**: the semantic base hues are pulled 18% toward the active
  brand at read time — still distinguishable, but no longer a fixed rainbow.
- **Background glows**: brand, accent and highlight (not a fixed amber).
- **Shadows**: tinted with the palette's deep stop in light mode.
- **Typography**: neutral ink (near-black in light, near-white in dark) so it
  reads on pastel off-whites, navy, ice and plum without hue clashes.

## What stays fixed — on purpose

Money semantics and warning are functional, not brand decoration:

- `expenseRed` `#F0577B` always means money out.
- `incomeGreen` `#12B76A` always means money in.
- `danger` `#DC2626` is destructive.
- `warning` `#F0B429` is attention/over-budget/due-soon in every palette.

Without those invariants, "red means money out" would change meaning when the
user switches themes.

## Where it lives

| File | Role |
|---|---|
| `lib/utils/app_palette.dart` | The 12 immutable palettes, gradient derivation, default/reset target. |
| `lib/utils/app_colors.dart` | Mirrors the active palette; neutral text tiers; highlight ink; warning token; surface/glass/hero helpers. |
| `lib/main.dart` | Builds `ThemeData`/`ColorScheme` from the active tokens (surfaces, text, inputs, chips, snackbars, overlays). |
| `lib/utils/category_style.dart` | Blends category data hues toward the active brand. |
| `lib/screens/appearance_screen.dart` | Palette picker (automatically shows the four new sets first). |

## Verification

The redesign branch adds `test/premium_palette_pages_test.dart`, a sweep that
boots **19 screens** under **each of the 4 new palettes × light/dark** (152
screen renders). It seeds a real ledger and planner, loads the bundled Poppins
fonts (so layout is measured with the shipping face, not the test Ahem face),
mocks connectivity/permissions, and fails on any layout exception, overflow,
missing provider or plugin crash.

`tool/palette_gallery_test.dart` renders the same matrix to
`build/palette_gallery/<palette>/<light|dark>/<screen>.png` for visual review.

## Gallery

Side by side: [light](./palette-gallery/all-palettes-light.jpg) ·
[dark](./palette-gallery/all-palettes-dark.jpg).

Contact sheets (all 19 screens, 4 × 5 grid):

| Palette | Light | Dark |
|---|---|---|
| Premium Blue | [sheet](./palette-gallery/premium_blue-light.jpg) · [home](./palette-gallery/premium_blue-light-home.png) | [sheet](./palette-gallery/premium_blue-dark.jpg) · [home](./palette-gallery/premium_blue-dark-home.png) |
| Deep Navy | [sheet](./palette-gallery/deep_navy-light.jpg) · [home](./palette-gallery/deep_navy-light-home.png) | [sheet](./palette-gallery/deep_navy-dark.jpg) · [home](./palette-gallery/deep_navy-dark-home.png) |
| Soft Pastel Teal | [sheet](./palette-gallery/soft_pastel_teal-light.jpg) · [home](./palette-gallery/soft_pastel_teal-light-home.png) | [sheet](./palette-gallery/soft_pastel_teal-dark.jpg) · [home](./palette-gallery/soft_pastel_teal-dark-home.png) |
| Plum & Blush | [sheet](./palette-gallery/plum_blush-light.jpg) · [home](./palette-gallery/plum_blush-light-home.png) | [sheet](./palette-gallery/plum_blush-dark.jpg) · [home](./palette-gallery/plum_blush-dark-home.png) |

## On device

The separate `com.example.spendsense.preview` package boots the whole app with
the demo ledger. Switch palettes and light/dark in **Settings → Appearance**;
the choice applies to every screen immediately. Read SMS is revoked for that
package so no real messages are imported.

Build: temporarily set the preview `applicationId` and matching
`google-services.json` client (see the home redesign document), then
`flutter run -t tool/preview_app.dart -d <device>` and revert the two config
files.
