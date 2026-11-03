# SpendSense OTA source reconciliation

**Purpose:** identify the source tree and commit associated with Android OTA build `2.0.23 (build 48)` and compare it with the original local checkout.  
**Scope:** read-only Git/release investigation; no source, app code, product behavior, branch, tag, or worktree was changed. This report is an additional document; the three existing design audit documents are preserved.

## Finding

The OTA publish run identifies **`47f60b60ab7aae4ea94ad434f4adaa925d1904e2`** (`release: bump to 2.0.23+48 (#46)`) as the commit used to publish build 48.

This is supported by the public GitHub Actions API record for [OTA Publish run 41602950945](https://github.com/Chaitanysai/Spendsense/actions/runs/41602950945): event `workflow_dispatch`, branch `release/2.0.13+38`, head SHA `47f60b60ab7aae4ea94ad434f4adaa925d1904e2`, completed successfully on 2026-11-03, with both **Build manifest and validate** and **Publish to Firebase Hosting** successful. The source `pubspec.yaml` at that commit declares `2.0.23+48`.

The exact published Git commit is therefore identifiable, rather than inferred from the current tracking branch or a version tag.

### Equivalent sibling release commit

There is also commit **`b9b65fb194700c8c15380288601b7235bd9834b8`** (`release: bump to 2.0.23+48`) on `release-48` / `origin/release-48`. It was created from parent `e097e9d42b8773a02efe0d4fd0027b36df8568dc`, as was the published commit. Both commits have the same Git tree:

`118b4914e34c3b557e477d491929f3a9166e5e18`

So both identify identical source content, but the successful OTA run names `47f60b6…` as its source commit. The OTA workflow is gated to `main` or branches matching `release/*`; the `release-48` branch name does not match that release-ref condition. Treat `47f60b6…` as the canonical provenance commit for build 48.

## Git and worktree evidence

- Original checkout: `E:\Projects\Spendsense-dsh`, branch `release/2.0.13+38`, HEAD `9b9f6bd33cc3ee0e6c9c42d20a669c5825b61315`, tagged `v2.0.13+38`; `pubspec.yaml` is `2.0.13+38`.
- At inspection, local `origin/release/2.0.13+38` pointed to `47f60b6…`; local `origin/release-48` pointed to `b9b65fb…`. The original checkout reported 34 commits behind its tracking ref.
- `v2.0.23+48` has no matching local Git tag. The branch refs and the successful OTA run provide the release evidence instead.
- Local remotes are `origin` and `entire`. No fetch, pull, merge, rebase, reset, checkout, or branch switch was performed for this investigation.
- `git worktree list` showed several existing worktrees. The existing `release-48` worktree at `E:\Projects\Spendsense-dsh\.agents\worktrees\security\hardening` is at `b9b65fb…`, but has **21 modified screenshot files** under `docs/design-review/glass-refine/screens/`. They are preserved and that worktree is not safe to use as a clean redesign workspace.
- The primary checkout has the three untracked design audit documents created in the prior task. They remain untouched by this reconciliation. Other worktrees are on unrelated revisions or have local changes; none is both clean and already at the canonical published commit.

## Difference from the original checkout

Base: `9b9f6bd…` (`2.0.13+38`)  
Target source: `47f60b6…` (`2.0.23+48`)  
Net repository diff: **90 files changed, 5,342 insertions, 1,912 deletions**. Both release commits discussed above resolve to the same target tree.

### Product UI changes

The relevant visual/product changes accumulated in these PRs/commits:

- **Paper theme and typography (#21, `3b94d09`)** — adds the Paper palette and bundled Geist fonts/preset, and a Paper-aware settle-in treatment.
- **UI craft and account flows (#25, `b1a886c`)** — reshapes Add Transaction, Appearance, Settings, and Transaction Details; adds `AmountHeroField`, `CategoryChipPicker`, and `IconWell`; refines the Home action dock; adds in-app account deletion. These changes carry behavior and privacy copy that must be preserved.
- **Premium analytics and navigation (#34, `7a94517`)** — adds `SpendingWeekCard`, `CategoryBreakdownCard`, and the Home theme toggle; replaces the old `CategoryRail` and old weekly chart composition; adds ranked category bars and “show all” behavior; changes the bottom-navigation indicator to a spring interaction; adds contextual skeletons and content reveal states. `docs/design-review/README.md` documents the design decisions and reports device captures at 360/430dp, landscape, and a OnePlus 7T.
- **Contrast and surface refinement (#42, `b797995`)** — expands semantic color helpers, improves icon/ink legibility on tinted surfaces, adjusts dark-glass and overlay behavior, and adds screenshot/contrast coverage across palettes and screens.
- **Transaction source indication (#44, `8638582`)** — adds a source glyph to transaction rows so SMS and other transaction sources are distinguishable.
- **Email sync result feedback (#45, `e097e9d`)** — improves the Gmail import screen's sync results and status feedback. The email-import feature and screen were added earlier in the range, so the build 48 baseline includes a real Gmail/email flow absent from the original checkout.

### Screens changed

These screen files differ between `9b9f6bd…` and the build 48 tree:

- Modified: `activity_screen.dart`, `add_transaction_screen.dart`, `ai_settings_screen.dart`, `appearance_screen.dart`, `assistant_screen.dart`, `bills_screen.dart`, `cards_screen.dart`, `home_screen.dart`, `insights_screen.dart`, `launch_screen.dart`, `recurring_screen.dart`, `settings_screen.dart`, `transaction_details_screen.dart`, `typography_screen.dart`, and `update_screen.dart`.
- Added: `email_import_screen.dart`.
- Relevant providers/configuration also changed: `auth_provider.dart`, `transaction_provider.dart`, and `main.dart`.

### Shared widgets changed

- Added: `amount_hero_field.dart`, `category_breakdown_card.dart`, `category_chip_picker.dart`, `icon_well.dart`, `spending_week_card.dart`, and `theme_toggle.dart`.
- Removed: `category_rail.dart` (its Home role was replaced by the category breakdown card).
- Modified: `app_button.dart`, `app_sheet.dart`, `app_states.dart`, `assistant_cards.dart`, `budget_summary.dart`, `category_bubble.dart`, `category_spending_bars.dart`, `cycle_hero.dart`, `floating_nav_bar.dart`, `glass_card.dart`, `home_action_dock.dart`, `page_entry.dart`, `profile_avatar.dart`, `quick_action_tile.dart`, `salary_day_prompt.dart`, `section_header.dart`, `sms_import_prompt.dart`, and `transaction_tile.dart`.

### Theme and design-system changes

- The palette set grows from **12 to 13** with **Paper**. All existing palette IDs remain; keep them and their persisted values intact.
- Inter becomes the default typeface; Poppins remains available as “Poppins (classic)”. The target also retains the Dot-matrix, Outfit/Modern Sans, and Geist (Paper) options. Tabular monetary figures remain intentional.
- `app_colors.dart` adds theme-derived roles for charts, category tracks, navigation, skeletons and icon ink; it also refines dark surfaces and glass/overlay colors.
- `app_spacing.dart` adds shimmer/tooltip/theme timing and spring definitions used by navigation and the theme-switch thumb.
- `app_text_styles.dart` and `app_typography.dart` update hierarchy/preset handling. `main.dart` and shared widgets apply the refreshed theme and component states.
- The product still has light/dark/system behavior and per-palette identities. Build 48 is not the old twelve-palette snapshot described by the earlier local-only audit.

## Recommended safe redesign base

Base redesign work on **`47f60b60ab7aae4ea94ad434f4adaa925d1904e2`** in a **new isolated worktree and new branch**. That preserves canonical OTA provenance, leaves the original `2.0.13+38` checkout and its three audit documents untouched, and avoids the existing `release-48` worktree with user-modified screenshots. Do not reuse or clean that dirty worktree. No new worktree or branch was created during this report.

## Verification and remaining limit

Verified locally: commit ancestry and tree IDs, branch/ref/tag inventory, reflogs, commit log and diff name/stat lists, `pubspec.yaml` versions, worktree list/status, and the original checkout's unchanged HEAD/status. Verified remotely: the successful workflow run SHA, branch, event and job conclusions. No application tests were run because no application code was changed.

The only evidence not directly inspected is the installed APK's own embedded build provenance. The successful OTA publish run ties the hosted build 48 publication to `47f60b6…`; a device-side package hash/signature comparison would be an additional artifact-level confirmation, not needed to resolve the repository source commit.
