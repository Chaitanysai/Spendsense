# SpendSense — Premium Gradient + Glass Redesign (Design Specification)

Date: 2026-10-16
Author: implementation session (design-intelligence substitute for REA)
Status: approved by human partner, implementation in progress

## 0. Provenance & honesty statement

The intended `REA` (reverse-engineering-analysis) skill is **not installed** on this
machine. The installed equivalent used instead is `ui-ux-pro-max`
(design-intelligence database) run against domains: product, style, color,
typography, chart, ux, and the Flutter stack.

The Dribbble reference
(`https://dribbble.com/shots/27766370-Personal-Finance-Expense-Tracker-Mobile-App`)
could **not** be inspected programmatically: direct fetch and the oEmbed endpoint
both returned `HTTP 202` with an empty body (bot protection). The reference is
therefore described from the supplied screenshot description in the task brief.

Consequence: **no value below is presented as an extracted fact about the
reference.** Every concrete number (hex colour, point size, ms timing, blur sigma)
is a *design decision* made to reproduce the described visual language. Items
marked **[inferred]** are visual traits named in the brief but not measurable
without the image; the values assigned to them are still decisions.

## 1. Intent

Redesign the existing, functional SpendSense Flutter expense tracker so it
visually follows the reference's premium gradient-and-glass design language,
while preserving every existing behaviour: real transaction data and
calculations, SMS permission + SmartParser + AI fallback + duplicate prevention,
local persistence and offline operation, add/edit/delete, category behaviour,
search/filters/date ranges/budgets/recurring/Insights, and review of uncertain
transactions.

## 2. Non-goals

- Not a prototype or mockup: no hardcoded/fake transaction data.
- No new design/REA packages installed during this task.
- No dependency upgrades.
- No Google Cloud services.
- No removal of existing functionality to simplify layout.
- Full security-review phase is out of scope unless a security issue blocks
  safe implementation.
- No commits/pushes/deployments; no credentials written into `.env`/assets.

## 3. Visual language (from the brief)

- Premium **crimson → vermilion → warm-orange** gradient. **[inferred]** direction,
  stops and saturation.
- Translucent, **glass-like banking cards**. **[inferred]** blur/opacity.
- **Oversized balance typography**. **[inferred]** exact size/weight/tracking.
- **Circular, bubble-like spending visualizations**. **[inferred]** chart geometry.
- **Rounded white transaction and expense panels**. **[inferred]** radius.
- **Floating bottom navigation**. **[inferred]** height/inset/elevation.
- Layered gradients, soft highlights, subtle shadows, smooth transitions.
  **[inferred]** shadow spread, highlight placement.

## 4. Design tokens

### 4.1 Colour (light-first; dark adapted)

Decision. Brand ramp (crimson → warm orange):

| Token            | Hex       | Use                                   |
|------------------|-----------|---------------------------------------|
| `crimsonDeep`    | `#7A0F2B` | gradient deep stop, dark accents      |
| `crimson`        | `#C81E3A` | primary, balances, selected states    |
| `crimsonBright`  | `#E23A2E` | gradient mid stop, expense amounts    |
| `vermilion`      | `#F0432B` | CTA / gradient mid                    |
| `orange`         | `#FF7A1A` | gradient end stop, highlights         |
| `amber`          | `#FFB020` | restrained highlight, warnings        |

Neutrals (light): background `#FDF7F5` (warm off-white), surface `#FFFFFF`,
surfaceMuted `#F6EDEA`, border `#EFE1DD`, textPrimary `#1A1113`,
textSecondary `#7C6B6E`.

Neutrals (dark): background `#14100F`, surface `#1E1817`, surfaceAlt `#271F1E`,
border `#3A2E2C`, textPrimary `#F7F0EE`, textSecondary `#B9A8A5`.

Semantic (kept for comprehension, not brand): `incomeGreen #12B76A`,
`expenseRed #E23A2E`, `danger #DC2626`.

Decision: income stays green and expense stays red/orange so direction remains
readable — brand crimson is not used to imply income.

### 4.2 Gradients

- `heroGradient`: `#C81E3A → #E23A2E → #FF7A1A`, topLeft→bottomRight.
- `flameGradient` (CTAs): `#E23A2E → #FF7A1A`.
- `amberGradient` (accents): `#FF9A2B → #FFB020`.
- `glassSheen`: white `0.28 → 0.0` diagonal overlay for frosted highlights.

### 4.3 Glass recipe

Decision, tuned for readability (avoid the low-contrast failure mode the
`ui-ux-pro-max` Glassmorphism entry warns about):

- Light: fill `white @ 0.62`, border `white @ 0.75` (1px), blur sigma `14`.
- Dark: fill `white @ 0.07`, border `white @ 0.12` (1px), blur sigma `16`.
- Body text on glass is never placed below 4.5:1; dense financial text goes on
  solid white panels instead of glass.
- Blur is applied to **cards and the nav bar only**, never full-screen (the
  brief and the skill both flag full-screen blur as expensive).

### 4.4 Radii / spacing / motion (decisions)

- Radii: `sm 12`, `md 18`, `lg 24`, `xl 30`, `pill 999`.
- Spacing scale: `4, 8, 12, 16, 20, 24, 32` (base 4).
- Motion: fast `150ms`, base `250ms`, slow `400ms`; curves
  `easeOutCubic`, entrance `Curves.easeOutCubic`; balance/chart `600ms`.
- Respect reduced motion: when `MediaQuery.disableAnimations` is true, entrance
  and count-up animations collapse to their end state instantly.

### 4.5 Typography

Decision: keep **Poppins** (`google_fonts`, already a dependency — no new deps).
Amounts use tabular figures (`FontFeature.tabularFigures`) so live-updating
numbers don't jitter. Scale: display 40/800 (-1 tracking) for the hero balance;
h1 28/700; h2 22/700; title 16/700; body 14/400; label 12/600; overline
10/700 uppercase (+1.2 tracking).

### 4.6 Cards, charts, icons

- Category visualisation: circular donut (fl_chart, already a dependency) plus
  circular category "bubbles" — a colour-filled circle with a Material icon and
  percentage. **Decision:** emoji category glyphs are replaced with Material
  icons via a single category-style map (the skill flags emoji-as-icon).
- Charts: donut for part-to-whole (≤6 slices, labels with %), 7-day bar strip
  for daily spend; both animate in (`TweenAnimationBuilder`, 600ms).
- Navigation: floating glass bottom bar, capsule, safe-area aware, with an
  elevated gradient centre action. All six existing destinations are retained
  (no functionality removed); the centre "Add" action opens the Add screen as a
  pushed route so its success `pop()` behaves correctly.

## 5. Screens

Home/dashboard, Activity/transaction history, Insights & AI, Add transaction,
Recurring, Settings, AI provider settings, Transaction details, Login. All keep
their existing data sources, providers and logic; only presentation changes.

## 6. Responsiveness & states

Galaxy S24 first (≈360×780 dp logical); also support smaller widths and larger
text scale. Loading uses skeletons, empty states are illustrated with an action,
errors are surfaced with retry. Scroll performance: blur limited to small
surfaces; long lists use `ListView.builder`.

## 7. What is left to the builder

Exact blur/timing/palette above are the builder's calls and may be tuned; layout
composition per screen is the builder's call. Accessibility (contrast, focus,
reduced motion, min tap targets ≥48dp) is required.
