# SpendSense redesign implementation report

**Source:** `47f60b60ab7aae4ea94ad434f4adaa925d1904e2` (`2.0.23+48`)  
**Branch:** `feat/spendsense-premium-redesign`  
**Scope:** presentation-only changes in the isolated redesign worktree.

## Implemented

- Replaced the ambient canvas glows with the active theme's plain canvas. All existing `AppPalette` identities, light/dark modes, and persisted theme selection remain in use.
- Replaced routine translucent/glass card rendering with opaque, outlined theme surfaces. Preserved the shared card API and tap feedback.
- Kept palette-led gradient hero surfaces while removing decorative orbs and glow shadows.
- Changed primary buttons to a solid theme-safe fill and secondary buttons to a neutral outlined surface.
- Restyled the five-destination navigation as an opaque outlined surface. Kept its selection semantics, spring travel, interruptible taps, and reduced-motion behavior.
- Tightened shared corner radii, raised typography roles, and improved transaction amount and review-badge legibility.
- Reworked Insights' monthly overview into one neutral summary surface with spending, top category, and comparison details.
- Added title and context to the Cards empty state and ensured its content clears the bottom navigation.
- Constrained the authentication panel to 520 logical pixels on wide screens.
- Changed the dashboard budget hero to its linear progress presentation in landscape so the spending headline fits the shorter viewport.

Shared components propagate the visual system across Home, Activity, Add Transaction, Budgets, Bills, Recurring, Insights, Cards, Summary, Settings, Appearance, Typography, Sound, Assistant, Assistant Privacy, AI Settings, Authentication, Email Import, Update, transaction details, sheets, and loading/empty surfaces. Screen-specific behavior and financial content remain owned by their existing screens and providers.

The implementation does not change providers, financial calculations, persisted ledger data, authentication flows, SMS/Gmail processing, permission requests, endpoint/model configuration, navigation routes, or update behavior. The existing four audit/design/reconciliation documents remain preserved.

## Tests added

- `test/auth_wide_layout_test.dart` checks the authentication form width at a 2,400×1,080 landscape viewport.
- `test/cycle_hero_responsive_test.dart` checks the dashboard's linear progress layout at the same viewport.

No commit, push, merge, deployment, or OTA publication was performed.

---

# Continuation pass — six themes and theme-leak removal

**Scope:** additive theme work on top of the redesign above. No providers,
financial calculations, persisted ledger data, authentication, SMS/Gmail
processing, routes or update behaviour were changed.

## Six product-owner palettes

Added to `lib/utils/app_palette.dart` and to `AppPalette.all` (13 → 19):

| id | Label | Primary | Light neutral |
|---|---|---|---|
| `royal_blue_cream` | Royal Blue + Light Cream | `#014BAA` | `#F8F3F0` |
| `wine_sand` | WineRed, UnlightSand | `#7F011F` | `#F5EBD0` |
| `orange_milk` | Orange + milk | `#EC5E27` | `#FDFDF1` |
| `plum_milk` | Plum + milk | `#381932` | `#FFF3E6` |
| `midnight_indigo_vanilla` | Midnight, Indigo, Vanilla | `#282B4A` | `#EEEBDA` |
| `cherry_alabaster` | Cherry and alabaster | `#890149` | `#F3F3E7` |

Names and both supplied colours are verbatim; `test/product_palettes_test.dart`
asserts them. Every other stop — the ramp, the highlight, the warm money cue,
the light surface stack and the dark glass stack — is derived so each pair
reads as one designed world. All six are `glass: true` on a hue-tinted
near-black canvas, so the theme is visible in dark mode too.

"Midnight" in the supplied name is **not** the existing `midnight` palette;
that is a separate identity (`#05261C` emerald-black) and was left untouched.

## Theme-leak removal

`lib/screens/launch_screen.dart` painted Premium Blue's ramp as literal hex
(`#021024` / `#052659` / `#0A3468`) on every launch, so every other theme
flashed navy before its own world appeared. The canvas, glows and ring now
derive from the active palette, with each stop held dark enough for the white
wordmark to clear 4.5:1. The footer caption's ink was raised from 0.38 to 0.62
white alpha, which had measured ~3.4:1.

This was the only hardcoded brand colour found outside the palette layer.
Remaining literals were reviewed and kept deliberately:
`lib/utils/category_style.dart` (category hues are data encoding, already
tinted toward the active brand at read time) and `lib/widgets/theme_toggle.dart`
(a control that depicts the light/dark *icons*, not the theme).

## Appearance screen

`lib/screens/appearance_screen.dart` renders the theme list in three sections —
Premium, Additional, Classic — derived from `AppPalette.all` order alone, with
unknown ids falling into the last section so a future palette can never be
dropped. Each row now previews the palette's own ramp beside its own canvas and
highlight, and labels wrap to two lines so the longer supplied names are not
clipped. Grouping is presentation only: no new palette field, no second
registry, and `setPalette` / sound / DEFAULT chip behaviour is unchanged.

## Tests added

- `test/product_palettes_test.dart` — exact names and hex, tinted glass dark
  canvases, selection persisted across restart, palette preserved when the
  appearance mode changes, invariant money semantics.
- `test/appearance_palette_list_test.dart` — all 19 palettes listed exactly
  once, the three sections present, tapping applies and persists, long labels
  render fully at 1.0x and 1.3x text scale, no overflow while scrolling at 1.6x.
- `test/launch_screen_test.dart` — added a sweep proving every palette paints
  its own launch canvas with an AA-legible wordmark.
- `test/appearance_test.dart` — palette count 13 → 19 and the six labels added
  to the existing `containsAll` guard. No assertion was weakened.

## Whole-repository formatting

`dart format --set-exit-if-changed lib test` reported 61 files already
off-standard before this pass. They were formatted so the format gate is clean
and idempotent (245 files, 0 changed on a second run). This is whitespace and
trailing-comma normalisation only; there is no behaviour change in those files.
