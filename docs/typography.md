# Typography

## Status of the requested NDot faces

**NDot-55 and NDot-57 are not bundled.** They are proprietary typefaces owned by
Nothing Technology Limited. The research leads supplied (nothing.wiki,
Nothing's brand reference, the community thread) describe and preview the faces
but do not grant a redistribution licence. Shipping the files inside a
third-party APK would be a licence violation, so the exact fonts were **not**
integrated and nothing here claims they were.

What is implemented instead is the full typography *system*: centrally resolved
families, locally bundled files, correct weight registration, and a
display/body split. Swapping in NDot later is a three-line change once a
licence exists:

1. Drop the licensed files into `assets/fonts/`.
2. Declare them under `flutter: fonts:` in `pubspec.yaml`.
3. Point a `FontPreset` at the new family names.

## Bundled families

All files are licensed under the **SIL Open Font License 1.1**; the licence text
for each family is checked in under `assets/fonts/licenses/`. Sources are the
`google/fonts` repository (the canonical OFL distribution).

| Family | File | Weights | Role |
| --- | --- | --- | --- |
| Poppins | `Poppins-{Regular,Medium,SemiBold,Bold}.ttf` | 400/500/600/700 | Default body and display |
| DotGothic16 | `DotGothic16-Regular.ttf` | 400 | Dot-matrix display (technical preset) |
| Space Grotesk | `SpaceGrotesk-Variable.ttf` | variable `wght` | Technical preset body |
| Inter | `Inter-Variable.ttf` | variable `opsz,wght` | Clean-sans preset |
| Outfit | `Outfit-Variable.ttf` | variable `wght` | Modern-sans preset |

Variable families get an explicit `FontVariation('wght', …)` so `w600` renders
semibold instead of being synthesised.

## Why fonts previously failed to apply

`AppTypography` called `GoogleFonts.getFont(...)`, and `google_fonts` **fetches
the file from fonts.gstatic.com on first use**. On a cold or offline start the
fetch fails (or races the first frame), the style falls back to the platform
face, and the user sees the wrong font despite having selected a preset. The
`debugSkipFontLoading` test seam hid this in tests.

The rewrite removes the runtime fetch entirely: every family is declared in
`pubspec.yaml` and resolved with a plain `TextStyle(fontFamily: …)`. No network
access is required at runtime, and tests exercise the real bundled faces.

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
