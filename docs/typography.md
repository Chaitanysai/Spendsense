# Typography

SpendSense uses a small, locally bundled type system. Every family is declared
in `pubspec.yaml` and resolved with a plain `TextStyle(fontFamily: …)`; no font
is fetched at runtime, so the chosen face renders on a cold or offline start.

Proprietary display faces (including Nothing's NDot family) are not bundled
because their licences do not permit redistribution. Adding a licensed family is
a three-step change: place the files in `assets/fonts/`, declare them under
`flutter: fonts:`, and point a `FontPreset` at the new family.

## Bundled families

All files are licensed under the **SIL Open Font License 1.1**; the licence text
for each family is checked in under `assets/fonts/licenses/`. Sources are the
`google/fonts` repository.

| Family | File | Weights | Role |
| --- | --- | --- | --- |
| Poppins | `Poppins-{Regular,Medium,SemiBold,Bold}.ttf` | 400/500/600/700 | Default body and display |
| DotGothic16 | `DotGothic16-Regular.ttf` | 400 | Dot-matrix display (technical preset) |
| Space Grotesk | `SpaceGrotesk-Variable.ttf` | variable `wght` | Technical preset body |
| Inter | `Inter-Variable.ttf` | variable `opsz,wght` | Clean-sans preset |
| Outfit | `Outfit-Variable.ttf` | variable `wght` | Modern-sans preset |

Variable families get an explicit `FontVariation('wght', …)` so `w600` renders
semibold instead of being synthesised.

## Rules

- One central resolver (`AppTypography`) owns family selection; widgets do not
  hardcode families.
- **Money always uses the body face.** `AppText.hero`, `AppText.display` and
  `AppText.amount` pass `display: false`. Dot-matrix and decorative faces
  frequently lack the rupee sign and lining figures, so a large balance would
  render tofu or misaligned digits. Body faces (Poppins, Inter, Outfit, Space
  Grotesk) carry `₹`.
- Display faces are limited to headings, branding and compact prominent labels;
  body copy, forms, dialogs, bills and settings stay in the body face.
- No artificial letter-spacing is added to emulate a typeface; the small
  positive tracking on overline labels is a hierarchy device, not font
  imitation.
- Dynamic type is preserved: user scale multiplies the system scale and is
  clamped to `FontScale.min..max`.
