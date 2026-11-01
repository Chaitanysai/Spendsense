# SpendSense — Design Standard

The rules every screen is measured against. This file is normative: a change that
breaks one of these is a regression, not a preference. It describes what the app
*should* be, so where code disagrees with this document, the code is the bug.

**Mode: Operate.** The user is tracking their own money on one phone. Success is
finishing a task quickly and trusting the numbers. Expression lives in precision —
this is not a surface for delight, novelty, or brand theatre.

---

## 1. Space

One scale, one inset. Everything is a multiple of 4.

| Token | dp | Use |
|---|---|---|
| `xs` | 4 | icon-to-label inside a stack, tight pair |
| `sm` | 8 | gap between related controls |
| `md` | 12 | row vertical padding, icon-to-text |
| `lg` | 16 | card inner padding, gap inside a group |
| `xl` | 20 | page inset, prominent card padding |
| `xxl` | 24 | gap between sections |
| `xxxl` | 32 | major separation |

**Page inset is 20dp on every screen, including Home.** `AppSpacing.homePage` is a
deprecated alias for `AppSpacing.page` and must not acquire its own value. A screen
that needs more room nests an `lg` inside the standard inset. Two different gutters
on adjacent screens is the single largest source of "the alignment is off".

**Rhythm:** more space above a group heading than below it (`xxl` above, `sm` below).
Sections are separated by `xxl`; rows inside a section by a 1dp divider, never by
space alone.

## 2. Icon wells

One well, one glyph, one target.

| Metric | dp | Token |
|---|---|---|
| Well (any shape) | 40 | `AppSpacing.wellSize` |
| Glyph inside well | 20 | `AppSpacing.wellGlyph` |
| Interactive minimum | 48 | `AppSpacing.wellTouchTarget` |

- Build every leading glyph with `IconWell(icon:, color:)` (`lib/widgets/icon_well.dart`).
  Do not hand-roll a container plus a raw `Icon` — that is how the wells drifted to
  34/38/40/44/48 across screens.
- A well is smaller than the 48dp target, so any row or slot holding one must reserve
  at least `wellTouchTarget` of height. A well is never itself the target.
- Wells are a tint of the icon's own colour: 12% light, 22% dark. Never paint the glyph
  in its own untinted colour on that plate.
- Do not place two targets closer than 8dp.

## 3. Colour and contrast

- Body and label text: **≥ 4.5:1**. Large text (≥ 18.66dp bold or ≥ 24dp): ≥ 3.0:1.
- Glyphs are held to the text floor (4.5:1), not the large-text floor.
- Any glyph on a tint of its own colour goes through `AppColors.inkOn(tint, tinted, base)`.
  Never ink-on-own-tint by hand.
- Text brand colour is `AppColors.brandInk` on the canvas and
  `AppColors.brandWellInk` on a brand capsule. The difference is load-bearing: using
  `brandInk` on a capsule is what made three of four dock icons disappear.
- `AppColors.azure` and `brandBright` are **palette roles**, not fixed hues. In Paper,
  `azure == mid == #2B36FF`. Anything using them must resolve contrast per palette and
  be checked in light *and* dark.
- Money semantics are fixed across all palettes and never follow the theme:
  expense `#F0577B`, income `#12B76A`, plus `danger`.

## 4. Dark theme

Dark is a first-class scheme, never an inversion.

- Every raised surface must be **lighter than the canvas** and carry the white lift
  (`raised 6%` / `flat 3.5%`). AMOLED palettes opt out of the lift, not of the
  distinction.
- Glass: `GlassCard` (blur 14, `glassFill`, white hairline, top sheen) only where
  `AppColors.isGlassCanvas` is true (`isDark && palette.glass`).
- A "glass" card with an opaque fill and nothing behind it is not glass. Verify the
  `BackdropFilter` has translucent fill *and* content under it.
- Dark tiles must not render as flat black blocks.

## 5. Type

- Sizes come from roles, not from per-screen literals. If a widget needs a size, add a
  role to `AppText`; do not write `fontSize: 8.5` at the call site.
- The five bundling presets (standard/dotMatrix/cleanSans/modernSans/geist) change the
  family, never the size roles.
- Text must survive **font scale 1.3** without clipping or overflow. Reserve label
  boxes at the *effective* scale (`MediaQuery.textScalerOf(context).scale(1)`), not at 1.0.
- Numerals in money columns use tabular figures so amounts do not jitter.

## 6. Motion

- One entrance primitive: `PageEntrance`. One counter: `AnimatedAmount`.
- Every duration goes through `AppMotion.respect(context, d)` so the OS
  "remove animations" setting collapses it to zero.
- One authored moment per screen. No entrance on every section.

## 7. Lists and rows

- Row = `[well 40] [12] [title / subtitle] [chevron]`, vertical padding `md`.
- Title one line, ellipsis. Subtitle at most two lines, ellipsis.
- Chevron only where the row navigates; no chevron on a read-only row.
- Dividers sit between rows and are inset to the text edge, never through the well.

### 7a. The Home action dock

Four slots inside one capsule. Measured geometry (`home_action_dock.dart`):

| Element | Value |
|---|---|
| Capsule padding | 5 |
| Slot padding | `sm` horizontal and vertical |
| Well | 40 circular, `sm` icon-to-label gap |
| Glyph | 20 |
| Label | 11pt, `height: 1.15`, **two lines reserved in every slot** |
| Slot min height | 48 (`wellTouchTarget`) |

The two-line reservation is load-bearing: `Add expense` wraps on a 411dp phone
while `Activity` does not, so an unreserved label box made one slot taller and
dropped its glyph below its neighbours. Measured before/after at 411dp: label
boxes `{22.0, 11.0}` → `{26.0, 26.0}`. Do not "simplify" the `SizedBox` away.

Glyph tops across slots may differ by 1dp. That is the Material icon's own ink
box (`north_east_rounded` vs `south_west_rounded`), not layout — do not chase it.

## 8. Forms

- Primary action is always reachable: the keyboard must never cover it (inset the
  submit area by `viewInsets.bottom`).
- Amount is the most prominent field on a transaction screen; one visual weight above
  everything else.
- Group fields by what they are (amount / category / when / note), one group per card.
- Targets follow §2. No cramped rows.

## 9. Copy

- Controls name their action ("Export JSON backup", not "Export").
- Errors name the problem and the recovery.
- Empty states say what the surface is for and the one thing to do next.

## 10. Verification

A change is done when all of these hold:

1. `dart analyze lib test tool` → no issues.
2. `flutter test --no-pub` → all pass (baseline: 1006).
3. Screenshots captured **from a device or emulator** (never a browser) at native
   resolution, light and dark, for every screen that changed.
4. Font scale 1.3 captured for every screen that changed.
5. Contrast measured, not eyeballed — `test/support/contrast_audit_test.dart` sweeps
   every palette and both themes and asserts the minimum ratio.
6. Alignment measured with `tester.getRect()`/`getTopLeft()`, not by eye.
