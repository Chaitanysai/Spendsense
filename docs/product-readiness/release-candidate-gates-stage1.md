# Release-candidate gates — Stage 1 completion (UX surfacing + outstanding gate checks)

**Date:** 2026-10-24 (IST) · **Source:** working tree on `chore/cleanup-root-files` + uncommitted changes · **Baseline:** `security-validation-phase-4.md` (same day)

## Verdict: PASS WITH BLOCKERS — all executable Stage-1 gates now PASS with evidence; release blockers remain release-level (see §6)

Final validation: **526/526 tests passed** (full `flutter test`), **`flutter analyze`: no issues**.

---

## 1. Corrupted-ledger UX (the phase-4 blocker) — FIXED + regression-tested

**Change (production):**
- `lib/providers/transaction_provider.dart`: `_init()` now catches ledger
  initialization/load failures into `ledgerInitError` (never an empty-success);
  `retryLedgerInit()` re-attempts after repair; all mutation entry points
  (`addTransaction`, `updateTransaction`, `updateCategory`, `toggleExclude`,
  `syncFromSms`, `resyncFromSms`) are safe no-ops while the ledger is
  unavailable, so a broken store can never be half-written.
- `lib/screens/home_screen.dart`: an error state renders an explicit
  "Couldn't load your ledger" card (with the error type and a Try again
  action) instead of the empty-dashboard copy; the hero line shows the same
  error headline; the SMS-start-date prompt is suppressed during errors.

**Regression tests** (`test/ledger_error_surfacing_test.dart`, 5, all PASS):
- provider records init failure as error, not empty success; transactions
  stay empty; mutations no-op; sync completes without throwing
- retry after store repair clears the error and loads (empty ≠ error)
- widget: init failure renders the error card, never 'Nothing found'/'No
  transactions yet'; 'Try again' keeps the error surfaced while still broken
- widget: genuinely empty ledger still renders 'Nothing found', never the error
- widget: populated ledger renders neither state

Test-infrastructure note: the app shell builds every tab; ActivityScreen's
initState triggers a startup SMS sync whose permission request never settles
in tests. The tests mock the permission channel (denied) so the sync
terminates deterministically — the same flow the real device exercises.

## 2. Outstanding gate-matrix checks — all executed

| Gate (from release-candidate-gate.md) | Evidence | Result |
|---|---|---|
| 2.1 Salary-cycle boundaries / calendar-month label | `salary_cycle_test`, `salary_day_settings_test`, `period_contract_test`, `task3_financial_test` — 81 tests | PASS |
| 2.2 Budget notifications use the selected salary day | **NEW** `budget_notification_test.dart` (4) — thresholds 60/80/100%, silence <50%, and a direct proof that pre-cycle spending does not count (salary cycle, not calendar month). Notifications channel faked; exact titles captured | PASS |
| 2.3 SMS permission denial, recheck, duplicate prevention | Automated: `sms_content_policy_test`, `rejected_sms_test`, `rejected_sms_retention_test`, `sms_pipeline_test`, `sms_body_retention_test`, `transaction_provider_lifecycle_test` — 77 tests. Device: `READ_SMS` is `granted=false, USER_FIXED` on the OnePlus; explicit launch under that state loads the ledger (`📦 Local DB init — 1 txs`), keeps the process healthy, shows no prompt, and leaves the ledger byte-identical (hash `7f3b5ea4…` before and after). Granting on this phone was deliberately NOT tested: it would sync the owner's real inbox (personal data, non-synthetic) | PASS (denied path live-verified; granted path covered by automated suites only) |
| 2.4 Full resync: success/empty/failed/interrupted | `resync_safety_test.dart` (7 named scenarios: empty scan, throwing scan, SMS-rows-replaced/manual-kept, idempotent repeat, every interruption point all-or-nothing, retry to completion without duplicates, restart visibility) + `ledger_import_test.dart` (86) | PASS |
| 2.5 Import failure preserves the ledger | `ledger_import_test.dart` (86, incl. failure-after-every-single-write sweeps) | PASS |
| 2.7 Large text / accessibility | **NEW** `accessibility_large_text_test.dart` (4): dashboard with data and empty at 1.3× and 2.0× text scale, zero layout exceptions. **Found and fixed a real defect:** the category-bubble percentage column overflowed its fixed circle by 17 px at 2.0× (`category_bubble_cluster.dart`); the icon+percentage group now scales down (`FittedBox`) instead of overflowing — the app's established pattern for amount text | PASS (after fix) |
| 2.8 Offline startup / error recovery | **NEW** `offline_startup_test.dart` (1): app starts with every network channel unmocked, renders the dashboard, ledger loads with no error. Update-failure paths already unit-tested (`update_service_test`: networkError/timeout, unconfigured no-op, bad-hash deletion, wrong-cert rejection) | PASS |

## 3. Files changed in this stage

| File | Change | Why |
|---|---|---|
| `lib/providers/transaction_provider.dart` | ledger error state, retry, mutation guards | stage-1 item 1 |
| `lib/screens/home_screen.dart` | error card, hero headline, prompt suppression | stage-1 item 1 |
| `lib/widgets/category_bubble_cluster.dart` | `FittedBox` around bubble icon+percentage | demonstrated 2.0× overflow defect |
| `pubspec.yaml` | +1 dev-dependency (`flutter_local_notifications_platform_interface ^8.0.0`) | lint hygiene for the test import (transitive package made explicit; test-only) |
| `pubspec.lock` | regenerated for the dev dependency | automatic |
| `test/ledger_error_surfacing_test.dart` | new, 5 tests | stage-1 item 2 |
| `test/budget_notification_test.dart` | new, 4 tests | gate 2.2 (had zero coverage) |
| `test/accessibility_large_text_test.dart` | new, 4 tests | gate 2.7 |
| `test/offline_startup_test.dart` | new, 1 test | gate 2.8 |

No commits, pushes, installs, uninstalls, data clears, key changes, production
signing, or OTA actions. The installed device app remains 2.0.3+24 with the
synthetic ₹239.50 ledger, hash-verified unchanged at the end of testing.

## 4. Validation commands

- `flutter test` (full suite) — exit 0, **526 passed / 0 failed** (was 512 before this stage: +5 error-surfacing, +4 budget, +4 accessibility, +1 offline)
- `flutter analyze` — exit 0, no issues (6 initial lint infos in new tests fixed)

## 5. Device state after testing

OnePlus 7T, `com.example.spendsense` 2.0.3+24, process healthy; ledger prefs
hash `7f3b5ea4…` and secure-storage hash `274bf86c…` identical to the session
baseline; `READ_SMS` left exactly as found (denied, user-fixed). No device
residue.

## 6. Remaining release blockers (unchanged from phase 4, plus none new)

1. No release artifact contains the current source (stale 2.0.3+23 release);
   requires an authorized release build.
2. OTA manifest must be regenerated for the next release.
3. ~~Corrupted-ledger UX~~ — **cleared by this stage**.
4. Gate items outside Stage-1 scope that remain NOT EXECUTED on hardware:
   real-inbox sync under a GRANTED SMS permission (needs a device whose inbox
   may be read or explicit owner authorization to use personal data), and
   physical-device large-text spot check (covered by widget tests instead).
5. Original-SMS panel wording (gate 2.6) was not re-listed in the stage-1
   scope; it remains covered only by existing `sms_body_retention_test`
   semantics if applicable — flagged for the next gate review.

**Production status: NO-GO** — unchanged, pending an authorized release build
of the current source and the remaining release-level gates.
