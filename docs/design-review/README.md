# SpendSense UI/UX pass — design system, analytics, motion

**Branch:** `design/premium-ui`
**Base:** `release-44` (`e931105`, version 2.0.19+44)
**Scope:** UI only. No signing, OTA, Firebase or backend changes.

This folder holds the visual evidence captured while the work was verified on a
OnePlus 7T (1080×2400, Android 16 / API 37). The app was installed as an upgrade
over the existing build, so the device's encrypted ledger was preserved.

---

## 1. Design language

One surface grammar across the dashboard: a quiet canvas, one accent, hairline
structure, and data drawn only in two shapes — a **line/area** for time and
**bars** for composition.

### Tokens

| Token group | Location | Notes |
| --- | --- | --- |
| Palettes (12, incl. the 2026 premium set) | `lib/utils/app_palette.dart` | unchanged; the redesign consumes these |
| Colour read-point | `lib/utils/app_colors.dart` | added `chartGrid`, `chartLine`, `chartArea`, `categoryTrack`, `skeletonBase`, `skeletonHighlight`, `navPillGradient`, `onNavPill` |
| Spacing / radius | `lib/utils/app_spacing.dart` | unchanged scale |
| Motion | `lib/utils/app_spacing.dart` | added `shimmer`, `tooltip`, `theme` durations, and `AppSpring.nav` / `AppSpring.thumb` spring descriptions |
| Typography | `lib/utils/app_typography.dart` | default face is now **Inter** (bundled, OFL); Poppins stays selectable as "Poppins (classic)"; Geist/Paper, Outfit and Dot-matrix unchanged |

The new colour helpers are all theme-derived; none of the components introduced
here hardcode a hue. The navigation pill and the theme thumb deliberately invert
on dark palettes (lit fill, dark ink) because several palettes ship a `brand`
that is within a few points of their card surface — a brand-on-brand pill had no
edge.

### Typography

Inter is the default because it is a neutral grotesque designed for small UI
text and tabular figures, and it is already bundled (no runtime fetch). Money
always resolves through `AppText.amount`, which pins tabular figures and the body
face. Poppins, Outfit, Geist and DotGothic16 remain one tap away in
Settings → Appearance.

---

## 2. What changed

### Last 7 days — `lib/widgets/spending_week_card.dart` (new)

- One answer at a time: the selected day's total, its share of the week, and the
  shape of the whole week.
- Custom-painted area + line chart: hairline grid, Catmull-Rom curve, dots that
  appear as the drawing head passes them, a gliding selection ring and an
  inverted value bubble that names the day.
- Entrance: the line draws left → right in 600 ms (`AppMotion.chart`), points
  appear in its wake, the figure counts up in 250 ms.
- Interaction: tap **or drag** across the plot selects a day; the 7 weekday
  cells are a second target; every day carries its own semantics label with the
  full date and amount.
- Data changes animate from the currently painted values (a sync landing mid-view
  never snaps the line back to zero).
- Empty week keeps the header and shows a labelled empty plot.
- Comparison line is bounded and honest: a dominant day reads "94% of this
  week"; other days are compared with the **daily** average (zeros included);
  zero days read "Nothing spent on this day"; a single-spend week reads "First
  spending this week".

### Spending by category — `lib/widgets/category_breakdown_card.dart` (new) + `category_spending_bars.dart`

- One card: cycle total, category count, a stacked composition strip, then ranked
  rows (icon, label, amount, share, proportional bar).
- The strip includes **every** category, with a 3 dp floor per segment so a 0.4%
  category is still visible; widths are normalised back to the track.
- Tapping a row selects it: the row gains a tinted plate and the other strip
  segments dim to 45%. Tapping again clears.
- Long lists are not truncated: the first 5 rows show, "+N more categories" plus
  **Show all** reveals the rest from the same data (and "Show less" collapses).
- With a single category the strip is hidden (it would duplicate the only row).
- `CategoryRail` (the old horizontal carousel) was removed — it was the only
  consumer of the data and the unified card replaces it.

### Bottom navigation — `lib/widgets/floating_nav_bar.dart`

- One spring-driven indicator: `tap → spring → stretch → slide → contract →
  settle`.
- Position is tracked in **slot units**, so rotation and width changes cannot
  strand the pill between destinations.
- Width is derived from the spring's own velocity (and scales with travel
  distance), so it stretches in flight and contracts on arrival; a second tap
  retargets the same spring from the current position *and* velocity, which makes
  rapid taps continuous rather than queued.
- Reduced motion snaps instead of travelling.
- Selection stays multi-channel: pill, glyph ink, label weight, semantics
  `selected`.
- The pill is the lit object in dark mode and the brand object in light mode,
  with ink chosen for each.

### Home theme switch — `lib/widgets/theme_toggle.dart` (new)

- Sun/moon track with a spring thumb; the thumb is the brightest object in dark
  mode and the darkest in light mode.
- Tap writes an explicit `ThemeMode` through `ThemeProvider` (persisted to the
  same `theme_mode` key already used by Settings). `system` remains available in
  Settings → Appearance and is untouched.
- 44 dp touch target, `toggled` semantics, tooltip, button cue.

### Loading states — `lib/widgets/app_states.dart`

- `SkeletonBox` now carries a travelling sheen (gradient sweep) plus a slight
  breath on the base, on a 1.5 s cycle; reduced motion freezes it.
- Skeleton tint is the local text ink at 8% over the current surface, so it works
  on white cards, tinted dark cards and coloured surfaces alike.
- New contextual skeletons: `SpendingWeekSkeleton` and
  `CategoryBreakdownSkeleton`, both matching the real cards' geometry.
- New `ContentReveal`: 250 ms fade + 4 px→0 blur when the real content replaces
  a skeleton.
- Skeletons are bound to a reachable state: ledger still loading, or the first
  SMS scan running over an empty ledger. A background re-sync over existing rows
  never replaces data with placeholders.

### Wiring — `lib/screens/home_screen.dart`

- Category card and week card replace the rail and the old fl_chart card.
- Theme switch sits beside the dashboard-edit control in the header.
- Old private chart class and its helpers removed (~270 lines).

---

## 3. Reference adaptation

BoardUI was studied as research only; nothing was copied or installed.

| Reference | Taken | Adapted |
| --- | --- | --- |
| Earnings chart card | KPI hierarchy (headline figure → supporting stat → plot), count-up on change, delta chip, hairline plot guides | Flutter `CustomPainter` instead of Recharts; an area+line rather than pill bars, so time and composition are drawn in different shapes |
| Stage bars card | Ranked horizontal bars, leading icon, value + percentage share, one grouped surface | Added the stacked composition strip and selection (dimming) so a thin slice stays identifiable; every category remains reachable via Show all |
| Color picker | Swatch selection ring, inset hairline on light colours, 150 ms hover/press scale | Not a user-facing feature: used as the rule for the new category/nav/skeleton tokens (derived, contrast-checked) |
| Color language | Two-tier architecture: primitives + semantic tokens; dark mode remaps at the root | Already present as `AppPalette` → `AppColors`; extended with analytics/nav/skeleton semantics |
| Skeleton | 8% ink tint, 2 px leading sheen, content cross-fade on load, `aria-hidden`/busy | `SkeletonBox` sheen + `ContentReveal`; `Semantics` excludes the placeholder, loading regions stay labelled by the section header |
| Switch | Track/thumb proportions, embossed thumb, 200 ms travel | Sun/moon theme control with spring travel and mode-aware inversion; icon inside the thumb |
| Typography | Inter, 4 weights, composite size/leading/tracking roles, positive tracking on captions | `AppText` roles already encoded this; Inter is now the default face, money pinned to tabular figures |

`npx boardui@latest skill` was **not** run. The npm package (`boardui@0.5.9`) is a
CLI that copies shadcn-style React components into a web project; it would add
`react-aria-components`, `recharts` and a registry dependency to a Flutter app
and modify project configuration. Pro components (chart card, stage bars) are
licence-gated and ship no source. Figma MCP was not used — no design file exists
for SpendSense, so there was nothing to extract tokens from.

---

## 4. Verification

### Automated

- `flutter analyze` — no issues.
- `flutter test` — **1066 tests pass** on the rebased branch (full suite, run
  twice; the second run after the final delta-line change).
- New behavioural tests in `test/premium_analytics_test.dart`:
  - nav settles centred on the tapped destination,
  - the pill is wider in flight than at rest and contracts on arrival,
  - a mid-flight second tap retargets and settles on the new tab,
  - reduced motion places the pill without travelling,
  - the theme switch writes and persists `theme_mode` and flips the app theme,
  - Show all reveals every category, selection dims the other segments,
  - the week card reports a tapped day immediately under reduced motion,
  - the empty week shows the empty state instead of an empty plot.
- Updated existing tests that encoded the previous nav design
  (`press_feedback_test`, `glass_overlays_test`) and the previous typography
  default (`typography_assets_test`, `typography_dashboard_test`).

### Visual (device, OnePlus 7T)

| Evidence | File |
| --- | --- |
| Categories, dark, 4 real categories | `home-dark-categories.png` |
| Weekly card, dark | `home-dark-weekly.png` |
| Weekly card, light, 430 dp | `home-light-weekly.png` |
| Categories, light, 360 dp | `home-light-360dp.png` |
| Nav at rest / 40 ms / 100 ms / settled | `nav-rest.png`, `nav-stretch-40ms.png`, `nav-slide-100ms.png`, `nav-settled.png` |
| Chart mid-draw (200 ms) and settled | `chart-drawing-200ms.png`, `chart-settled.png` |
| Skeleton sheen after 700 ms | `skeleton-shimmer.png` |

Checked on device: theme switch flips instantly with no flicker and persists
across a force-stop + relaunch; tapping a chart day moves the marker, bubble and
header figure together; the category card lays out at 360 dp and 430 dp with no
overflow; the dashboard renders in landscape as well.

### Not visually captured

- The loading→content transition on a device: the installed ledger already holds
  transactions, so the skeleton state is not reachable without clearing app data
  (which would destroy the user's encrypted ledger). The sheen is verified by
  rendered frames (`skeleton-shimmer.png`) and the skeletons are exercised by the
  every-screen render sweep across four palettes × two themes.
- The loading→error path: the ledger error state is covered by existing
  `ledger_error_surfacing_test`, not re-captured.

---

## 5. Known issues

1. **Expense red on white.** `AppPalette.expenseRed` (`#F0577B`) is ~3.3:1 for
   the 13 px transaction amounts in light mode. Pre-existing, and changing it
   affects every money-out surface in the app; left as-is rather than silently
   shifting the semantic colour.
2. **Transaction meta line at 360 dp.** The date in `TransactionTile` ellipsizes
   ("Nov 0…") at the narrowest width with 5 rows. The date is secondary and the
   row is not clipped mid-glyph; a two-line meta row would be the follow-up.
3. **Duplicate cycle total.** The hero, budget card and category card each show
   the cycle spend. They answer different questions (position, limit, category
   sum) but it is three figures with the same value on one screen.
4. **Landscape.** The dashboard keeps its portrait composition in landscape;
   cards become very wide. No breakage, but no tablet-specific composition yet.
