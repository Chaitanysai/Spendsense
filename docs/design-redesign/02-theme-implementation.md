
---

# Theme system as implemented

**Status:** implemented. This section records what the code actually does. The
proposal above is kept unchanged as the historical design direction.

## Where the theme system lives

| Concern | File |
|---|---|
| Palette definitions and the ordered set | `lib/utils/app_palette.dart` |
| Active tokens, contrast maths, glass recipe, semantic roles | `lib/utils/app_colors.dart` |
| Selection, mode, persistence | `lib/providers/theme_provider.dart` |
| Theme picker UI | `lib/screens/appearance_screen.dart` |

A palette is a `const AppPalette`: one Primary ramp (`brand`, `mid`, `bright`,
`deep`), one highlight (`accent`, optional `lime`), one warm money cue
(`warm`), a light surface stack (`background`, `surface`, `surfaceMuted`,
`borderLight`) and a dark surface stack (`darkBackground`, `darkSurface`,
`darkSurfaceAlt`, `borderDark`). `glass: true` means the dark surfaces are
designed for their role and are used verbatim; without it they are tinted from
the brand ramp at read time.

`AppColors.applyPalette` mirrors the active palette into static fields so that
every existing `AppColors.brand` / `AppColors.heroGradient` call site follows a
theme change without threading a palette through the widget tree.

## Theme inventory

Nineteen palettes ship, in this display order:

| # | id | Label | Light canvas |
|---|---|---|---|
| 1 | `premium_blue` | Premium Blue *(default, reset target)* | `#F2F8FF` |
| 2 | `paper` | Paper | `#E7E5E0` |
| 3 | `deep_navy` | Deep Navy | `#F2F5F6` |
| 4 | `soft_pastel_teal` | Soft Pastel Teal | `#F1F7F7` |
| 5 | `plum_blush` | Plum & Blush | `#FFF7F2` |
| 6 | `midnight` | Midnight | `#F4F5F5` |
| 7 | `royal_blue_cream` | Royal Blue + Light Cream | `#F8F3F0` |
| 8 | `wine_sand` | WineRed, UnlightSand | `#F5EBD0` |
| 9 | `orange_milk` | Orange + milk | `#FDFDF1` |
| 10 | `plum_milk` | Plum + milk | `#FFF3E6` |
| 11 | `midnight_indigo_vanilla` | Midnight, Indigo, Vanilla | `#EEEBDA` |
| 12 | `cherry_alabaster` | Cherry and alabaster | `#F3F3E7` |
| 13 | `emerald` | Emerald | `#F7F9F8` |
| 14 | `ocean_blue` | Ocean Blue | `#F3F6FD` |
| 15 | `warm_amber` | Warm Amber | `#FFF9F0` |
| 16 | `forest_green` | Forest Green | `#F2FBF5` |
| 17 | `royal_purple` | Royal Purple | `#F8F5FE` |
| 18 | `rose` | Rose | `#FFF5F7` |
| 19 | `teal` | Teal | `#F0FBFA` |

Rows 1-6 are the 2026 premium set, 7-12 are the product-owner palettes added
in this pass, and 13-19 are the original identities. Premium Blue stays first
because `AppPalette.byId` falls back to it and `resetToDefaults` restores it.

## The six product-owner palettes

The brief supplied one Primary and one light neutral per theme. Both are used
verbatim: `brand` **is** the Primary and `background` **is** the neutral. Every
other stop is derived so the pair reads as a designed world.

Names are reproduced exactly as supplied, including `WineRed, UnlightSand` —
enforced by `test/product_palettes_test.dart`.

| id | Label | Primary | Light neutral | Highlight `accent` | Warm cue `warm` |
|---|---|---|---|---|---|
| `royal_blue_cream` | Royal Blue + Light Cream | `#014BAA` | `#F8F3F0` | `#F5C86B` gold | `#E8963C` amber |
| `wine_sand` | WineRed, UnlightSand | `#7F011F` | `#F5EBD0` | `#EBD08B` antique gold | `#E39A45` burnt amber |
| `orange_milk` | Orange + milk | `#EC5E27` | `#FDFDF1` | `#9FDDEC` ice blue | `#F0B23E` golden amber |
| `plum_milk` | Plum + milk | `#381932` | `#FFF3E6` | `#F1D3A0` champagne | `#E0A05E` honeyed copper |
| `midnight_indigo_vanilla` | Midnight, Indigo, Vanilla | `#282B4A` | `#EEEBDA` | `#EFE0AE` vanilla gold | `#E7A85E` apricot |
| `cherry_alabaster` | Cherry and alabaster | `#890149` | `#F3F3E7` | `#9FE0BC` mint | `#EFA35A` apricot |

Full ramps, light surfaces and dark glass surfaces are declared in
`lib/utils/app_palette.dart`; that file is the single source of truth.

Each is `glass: true` on a hue-tinted near-black canvas (never the shared
AMOLED `#000000`), so the theme is visible in dark mode and not only in light.
Dark card chroma is held around 10-15% so cards read as dark glass rather than
saturated paint slabs.

### One palette depends on a derived fill

White on Orange + milk's raw `#EC5E27` measures 3.39:1 — under AA. The supplied
Primary is kept verbatim as `brand`; filled buttons use the existing
`filledBrand` derivation (darkened toward `deep` until white clears 4.5:1),
which yields `#C54C1E` at 4.77:1. This is the same mechanism every bright
palette already uses (Emerald, Ocean Blue, Warm Amber). It is expected
behaviour, not a compromise.

## Light and dark

Every palette pairs a light surface stack with a dark one, so all nineteen work
in both brightnesses. Appearance is `ThemeMode.light`, `.dark` or `.system`
under `Appearance → Appearance`; `system` follows the platform.

Switching brightness never changes the selected palette, and the palette is
stored independently of the brightness (`palette_id` vs `theme_mode`), so a
selection survives a restart in either mode. Both behaviours are covered by
`test/product_palettes_test.dart`.

## Semantics that deliberately do not vary

These stay identical in every palette so financial meaning never changes with
a theme:

| Role | Value |
|---|---|
| Expense / money out | `AppPalette.expenseRed` `#F0577B` |
| Income / money in | `AppPalette.incomeGreen` `#12B76A` |
| Error / danger | `AppPalette.danger` `#DC2626` |
| Warning | `AppColors.warning` `#F0B429` |

Status is never communicated by hue alone: amounts carry a sign and an icon,
and chart slices carry labels and direct values.

## Accessibility and contrast

Contrast is measured, not eyeballed. The derived stops are computed:

- `balanceTop`, `actionTop` and `filledBrand` darken `mid`/`brand` toward `deep`
  only as far as white text needs for 4.5:1.
- `brandInkFor` becomes readable *text* ink rather than a fill colour.
- `resolveInk` and `inkOnWash` walk a preferred colour toward white or black
  until the real composited backdrop clears the bar.

Every palette is swept in both brightnesses by:

| Test | Contract |
|---|---|
| `theme_tokens_contrast_test.dart` | text ≥ 4.5:1, icons and nav ≥ 3:1, accent containers, switch, FAB |
| `dark_surface_tones_test.dart` | card separates from canvas (ΔL\* > 2), card chroma < 22%, border visible |
| `glass_overlays_test.dart` | dialogs, sheets and nav over every palette |
| `icon_legibility_test.dart` | icon wells and plate tints |
| `filled_contrast_test.dart` | white ink on every filled brand stop |
| `settings_icon_contrast_test.dart` | settings row glyphs |
| `product_palettes_test.dart` | the six supplied names and hex values are exact |

Measured worst cases across the six new palettes, both modes: primary text
15.2:1, secondary text 7.5:1, brand ink 5.3:1, nav selected 4.6:1, FAB ink
4.6:1, `onDanger` 4.83:1. The tightest figures are the existing `resolveInk`
0.05-step quantisation shared by every palette in the app, not a property of
the new set.

Not verified by automation: TalkBack, large system text, reduced motion and
high-contrast modes on a physical device.
