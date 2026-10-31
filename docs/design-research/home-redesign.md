# Home screen redesign — GO Club × Suno

Status: implemented on this branch, verified with `dart analyze` and the Flutter
widget suite. Preview renders: [home-dark.png](./home-dark.png) ·
[home-light.png](./home-light.png).

## Brief and method

The brief was to redesign SpendSense Home using the Appllama MCP and skills, with
GO Club and Suno as the reference set.

**What was actually available.** The Appllama skills were loaded from
`Appllama/appllama-skills` (`appllama-usage` v1.1.0 and
`appllama-app-design-skill` v1.3.0) and their research/quality bar was followed.
The MCP endpoint (`https://mcp.appllama.io/mcp`) is gated by an Appllama Pro
account: an `initialize` request without a member token returns
`401 invalid_token` ("Authentication required"), and this harness had no
Appllama credential or `appllama_*` tools. The research therefore used the same
method against public evidence:

- the Appllama app library pages and the skills' documented playbooks;
- the shipped iOS screenshot sets for GO Club (10 screens) and Suno (8 screens);
- dominant-colour sampling of those screens to check the actual temperature
  rather than trusting category assumptions.

When the MCP is connected, the next pass should use `search_apps` →
`list_app_screens` on both apps and capture 20–30 screens before changing the
design again. The screen ids are durable; this document records the patterns the
current design is built on.

## What the references actually do

### GO Club: one number, one geometry, one dock

Observed across the App Store set (electric blue/orange marketing frames,
white/near-black app surfaces; source:
<https://apps.apple.com/us/app/go-club-steps-water/id6739782103>):

- The home screen answers a single question. One large metric, one circular
  progress geometry, a small label above it and a three-stat strip below.
- The stats strip is quiet: uppercase micro-labels, tabular values, one hairline
  between cells. It never competes with the hero.
- Actions live in a floating dock at the thumb, not in a grid of cards.
- Labels are tiny and letterspaced; values are enormous and tight. The contrast
  between those two registers is the hierarchy.
- Surfaces are calm; the saturated colour is spent on the progress object and
  one or two pills, not on every card.

### Suno: black canvas, editorial scale, horizontal rails

Observed across the App Store set (near-black `#1E1919` surfaces, coral
`#F14B3B` accent; source:
<https://apps.apple.com/us/app/suno-ai-songs-music-lyrics/id6480136315>):

- A true near-black canvas makes colour and type feel deliberate.
- Display type is oversized, tightly tracked, and left-aligned; the eye lands on
  the words before the components.
- Content is organised as horizontal rails of cards with the next card peeking,
  which advertises the scroll without an instruction.
- Rows inside a rail are flat and grouped; the list is one surface with
  hairline rhythm, not a stack of tiles.
- One warm accent carries "live"/"new"/"primary"; everything else is neutral.

### What was adopted — and what was refused

| Reference move | SpendSense translation |
|---|---|
| GO Club's single hero metric | Salary-cycle spending is the one number. Ring is 252dp, amount is 40sp, budget caption and cycle delta sit inside it. |
| GO Club's three-stat strip | `Left` / `Per day` / `Days left`, or `Activity` / `Top category` / `Days left` when no budget exists. |
| GO Club's floating action dock | One glass command dock with four real actions; 2 × 2 at large text. |
| Suno's near-black canvas | Keeps the existing AMOLED dark mode; the redesign stops tinting the hero card and lets the canvas be the stage. |
| Suno's editorial type | Greeting + name at 34sp, w800, −0.03em; section titles at 21sp. |
| Suno's horizontal rail | Category rail: 1–2 categories are a static row; 3+ become a peeking rail; max 6 cards. |
| Suno's flat list | Recent transactions are one grouped surface with hairlines and flat rows. |
| Suno's single warm accent | The lime delta pill is the only saturated pill; the ring carries the brand ramp. |
| **Refused:** album-art imagery | A ledger has no artwork; inventing cover art would be decoration. Category glyphs are data encoding. |
| **Refused:** orange/coral palette | SpendSense owns a switchable palette system; importing Suno's hue would break every theme and money-semantic colour. Temperature and contrast were borrowed, not the hue. |
| **Refused:** fixed bottom dock | The shell already owns a floating five-tab bar and an Add FAB; a second fixed dock would stack two thumbs. The action dock scrolls with the header. |

## Screen specification

Top to bottom, in the order a new user reads it:

1. **Greeting** — "Good morning," in secondary text, name in 34sp display
   weight. Avatar sits in the brand/lime ring at the top right, with the tune
   icon beside it for dashboard editing. A meta row carries sync state
   ("Synced 2h ago"), "Welcome back" and the date. No eyebrow above the
   headline.
2. **Cycle hero** — a 252dp ring on the canvas (no card behind it):
   - track: theme border, 78% of the arc width; arc: brand → brandBright,
     returning to its start colour at 100% so the seam is invisible;
   - lit head dot with a radial halo at the current position;
   - centre: "Total spent this cycle" eyebrow, currency amount, "of ₹50,000
     budget", cycle-over-cycle lime pill;
   - over budget: the arc is full and the tone switches to `expenseRed`; it
     never wraps past its start;
   - three-stat strip in a single bordered capsule;
   - no budget: neutral ring, "No budget set", and a 44dp "Set a budget" CTA;
   - privacy: the eye masks the amount, the budget caption, the cycle delta and
     both money stats; only "Days left" (and, without a budget, activity and top
     category) stay legible. The spoken label becomes "Balance hidden.".
3. **Command dock** — Add expense (filled primary), Add income, Sync SMS,
   Activity. One surface, dividers, 44dp+ targets.
4. **Editable sections** — Monthly budget (`BudgetSummary` preserved), Spending
   by category (rail), Last 7 days (seven bars, today in lime), Recent
   transactions (grouped flat feed, max 20).
5. **Edit dashboard** — opened from the tune icon beside the avatar; unchanged
   behaviour once open: reorder, hide via Settings, cancel vs done. Only the
   surface styling follows the new card language.

### Large text

At an effective scale above 1.35 the ring is replaced by a compact card: same
amount, same caption, a linear budget bar, and the stat strip becomes rows. This
keeps the figure legible at 2× instead of shrinking it inside a circle. The
action dock becomes 2 × 2, the category rail's static threshold stays at two
cards, and the recent feed rows grow naturally.

### Motion

- Ring fills once from zero on first build (900ms, `emphasized`), then tracks
  value changes from its current position.
- Amount counts up via the existing `AnimatedAmount`; no re-count on tab return.
- Reduce Motion collapses the ring and count-up to their end states.
- No new per-scroll animation; the seven-day bars keep their existing one-shot
  fill, and no list row animates on recycle.

### Colour and elevation

- One accent family: brand → brandBright, with lime reserved for the cycle delta,
  today's bar and the avatar ring. Category hues appear only as glyph tints and
  4dp data bars.
- Cards declare either a border or a shadow, not both where the card is a data
  surface. The command dock and navigation are the only floating chrome.
- Radii follow the existing scale (cards 24, hero/compact 30, pills 999).

## Implementation map

| File | Responsibility |
|---|---|
| `lib/widgets/cycle_ring.dart` | Single CustomPainter dial; track, sweep-gradient arc, lit head; no blur mask. |
| `lib/widgets/cycle_hero.dart` | Presentational hero: amount, privacy, delta, stats, compact mode, no-budget CTA. |
| `lib/widgets/home_action_dock.dart` | One-surface action dock; responsive 4 × 1 / 2 × 2. |
| `lib/widgets/category_rail.dart` | Static row for ≤2 categories, peeking rail for 3+, empty state. |
| `lib/widgets/section_header.dart` | Added `large` variant used only by Home. |
| `lib/widgets/transaction_tile.dart` | Added `flat` variant for the grouped recent feed. |
| `lib/screens/home_screen.dart` | Greeting, hero wiring, dock, sections, grouped feed, edit mode. |
| `tool/home_preview_test.dart` | Deterministic 390 × 844 dark/light preview renderer. |
| `tool/preview_app.dart` | On-device whole-app preview entry point with an in-memory demo ledger; separate app id. |

## Device verification — OnePlus 7T (HD1901), Android 16

The real `HomeScreen` was run on the connected phone through
`tool/preview_app.dart`, installed under the separate id
`com.example.spendsense.preview` so the user's installed 2.0.4 app and its data
were never touched. Device: 1080 × 2400 at 420dpi (411 × 914dp), Impeller
Vulkan.

Checked on hardware:

- hero amount, budget caption, delta and three-stat strip;
- eye toggle — amount, budget caption, delta and money stats mask, "Days left"
  stays readable;
- Add expense dock → shared sheet → save; the hero updated from ₹26,856 to
  ₹27,106 and "Left" from ₹23,144 to ₹22,894, so the read/write loop is live;
- category rail peeks the third card; weekly bars and day selection; grouped
  recent feed; edit mode opens from the header tune icon and cancels cleanly;
- the floating Add button steps away on scroll, exactly as the production shell
  does (the preview shell mirrors it);
- logcat showed no `RenderFlex overflowed` or Flutter exception during the
  flows. Debug and profile builds both launched and rendered.

Screenshots: [device-home-dark.png](./device-home-dark.png),
[device-home-privacy.png](./device-home-privacy.png),
[device-home-sections.png](./device-home-sections.png),
[device-home-recent.png](./device-home-recent.png),
[device-add-sheet.png](./device-add-sheet.png),
[device-edit-dashboard.png](./device-edit-dashboard.png).

The preview is a separate package so it can be launched from the app drawer as
"SpendSense Preview" without touching the release install. It now boots the
**whole app** (all five tabs and their routes) with the seeded in-memory ledger,
so every page can be opened on hardware. SMS access is revoked for the preview
package; this keeps real bank messages out of the demo database. Palette and
light/dark are switched live in **Settings → Appearance**.

To rebuild it, set `applicationId` to `com.example.spendsense.preview` in
`android/app/build.gradle.kts`, add the matching package to
`android/app/google-services.json`, then run:

```bash
flutter run -t tool/preview_app.dart -d <device-id>
```

Revert those two build-config edits afterwards; they are deliberately not
committed. The palette gallery at
[`palette-gallery/`](./palette-gallery/) shows all four premium palettes in both
themes across all 19 screens.

## Verification

- `flutter analyze` (project command) — no issues, including `tool/`.
- `flutter test --no-pub` — 923 passing, 0 failing. The one previously failing
  test (`update_config_test`, an uncaught service exception stranding `_busy`)
  exposed a real provider bug and is fixed in this change.
- Widget coverage of this screen includes: empty ledger, ledger read failure,
  SMS not configured, 320dp width, 2× text, all palettes and both themes,
  reduced motion, quick-action entry into the shared form, eye toggle, and the
  seven-day card's day selection.
- Preview renders were generated from the real widgets with bundled fonts; they
  are checked in under `docs/design-research/`.

## If the MCP is connected next

1. `get_credits`, then `search_apps` for "habit tracker" and "music creation" to
   confirm GO Club/Suno are still the right benchmark set.
2. Walk `list_app_screens` for both, screenshots included; compare the ring
   weight, the stat strip's type sizes, and Suno's rail spacing against this
   implementation.
3. `search_screens(mode="semantic", ...)` for "budget progress ring" and
   "horizontal category cards" to test the two original moves against 10+ more
   shipping examples.
4. Re-run the preview harness; one batch of fixes, one confirmation round.
