# Phase 3: period correctness and remaining data-safety work

Date: 2026-10-22. Scope: Tasks A–D from the approved phase-3 brief, plus the
signing-key handling rules. No commit, push, deploy, branch switch, reset, clean
or stash. No dependency, version, OTA, signing-config or release-artifact change.
The paise migration was not started. All pre-existing uncommitted work was kept.

Final gates: `flutter analyze` clean, `flutter test` **440 passed**.

---

## Task A: period correctness

### Approved rule implemented

Salary day `N` (1..31) begins a cycle on day `N` of each month; in a shorter
month it clamps to that month's last day; the next cycle begins on the
corresponding clamped day of the next month. Consecutive cycles are therefore
exactly contiguous.

`PeriodMath` (`lib/utils/period_math.dart`) is now the single implementation:

| Function | Purpose |
| --- | --- |
| `clampStartDay(y, m, N)` | day N, or the month's last day; **throws** for N outside 1..31 |
| `salaryCycle({salaryDay, now})` | the cycle containing `now` |
| `previousSalaryCycle(...)` | the contiguous cycle before it |
| `calendarMonth(day)` | the separate "This month" period |
| `nextSalaryDate(N, now)` | next salary date, clamped |
| `addDays` / `dateOnly` / `containsLocalDate` | DST-safe, date-only boundary math |

`clampStartDay` clamps because `DateTime(2027, 2, 31)` silently *overflows* to
March 3. My first implementation did exactly that, and the tests caught it.

### The four remaining DST-unsafe sites, plus two more

| Site | Before | After |
| --- | --- | --- |
| `transaction_provider.dart` `expensesInPeriod` | `DateTime(...).add(Duration(days: 1))` | `PeriodMath.addDays` + `dateOnly` |
| `home_screen.dart` daily-spend card | `DateTime(y,m,d).subtract(Duration(days: 6-i))` | `PeriodMath.addDays(today, i-6)` |
| `activity_screen.dart` "This Week" preset | `today.subtract(Duration(days: weekday-1))` | `PeriodMath.addDays(today, -(weekday-1))` |
| `ai_service.dart` "yesterday" | `DateTime.now().subtract(Duration(days: 1))` | `PeriodMath.addDays(DateTime.now(), -1)` |
| `period_provider.dart` `previousPeriod` | (done in phase 2) | `previousSalaryCycle` |
| `activity_screen.dart` `_isWithinRange` | (done in phase 2) | `containsLocalDate` |

`grep` for `Duration(days:` across `lib/` now matches only the doc comments in
`period_math.dart`.

### Every consumer now names its period explicitly

| Surface | Period | Label |
| --- | --- | --- |
| Home headline, cycle pill | salary cycle (`PeriodProvider.currentPeriod`) | "this cycle" / "than last cycle" |
| Home budget card + gauge | salary cycle | "Monthly budget" |
| **Budget notification** | **salary cycle** (`provider.currentSalaryCycle`) — was calendar month | budget alert |
| Insights totals, change, top category, bubbles | calendar month (`PeriodMath.calendarMonth`, both months from ONE captured `now`) | **"This month"** (was mislabelled "This cycle") |
| Activity presets | today / this week / this month / last 3 months | labelled per preset |
| AI answers ("this month") | calendar month | "this month" |
| Cards, Recurring | all time | unchanged |

`TransactionProvider.expensesInPeriod(null)` still means the calendar month; it
is documented as such and the budget monitor no longer relies on it.

### Tests (Task A)

- `test/salary_cycle_test.dart` — **37 tests**: salary days **1, 28, 29, 30, 31**; February in leap and non-leap years; month-ends; year boundaries in both directions; clamping (Feb 31 → 28/29, Nov 31 → 30) and that the *next* cycle restores the requested day; exact start/end-day inclusion and the day after; a UTC instant judged by its local day; DST boundaries; `nextSalaryDate` clamping; out-of-range salary day throws; calendar month differs from the cycle when N=25.
- **Gap/overlap sweep**: for salary days 1, 15, 28, 29, 30, 31, every day from 2025-01-01 to 2030-12-31 — each day is in exactly one cycle, every day inside a cycle is contained, and each next cycle starts exactly the day after the previous end.
- `test/period_contract_test.dart` — **23 tests**, rewritten: the retired "CURRENT:" pins of the last-calendar-day algorithm were **removed** (they asserted the superseded rule), replaced by assertions of the approved rule and a 2026–2028 sweep over six salary days.

Mutation checks on `PeriodMath` (deliberately broken, then restored): removing
the clamp fails 12 tests; making the end day exclusive fails 14; making the
start day exclusive fails 10. The suite genuinely enforces the rule.

---

## Task B: import and resync safety

### Reproduced

`forceFullResync()` called `_cache.clearAll()` and `_transactions.clear()`
**before** scanning (`transaction_provider.dart`). A scan that returned nothing,
or threw, left an empty ledger. A related defect: `_loadFromCache()` only
assigned when the cache was non-empty, so a genuinely emptied ledger was
resurrected from stale memory on the next launch.

### Fixed

`resyncFromSms()` replaces the clear-then-scan flow:

1. **Scan first.** An empty inbox or a scan that throws returns immediately with
   the ledger untouched — an empty scan is not evidence of an empty ledger.
2. **Parse into staging**, keeping manual entries and preserving a user's own
   edits (category, exclusion, bank) on rows that already exist.
3. **Validate completeness**: staged must be non-empty, and
   `replaceAllWithIds(..., expectedIds:)` refuses unless the resolved id set
   matches exactly what the caller intended.
4. **One journalled activation** — the same mechanism the import uses (payloads
   written and read back, then a single index write). Failure before the switch
   rolls back; a crash is finished from the journal at next start.

`forceFullResync()` is retained as a thin delegate for existing callers.
`_loadFromCache()` now assigns unconditionally. Database writes go through a
single `_locked()` mutex so a sync cannot interleave with a user edit.

`importFromJsonString` and the resync now share one `_activationWrite`
implementation instead of two copies.

### Tests (`test/resync_safety_test.dart`, 7)

A resync whose scan returns nothing, or throws, leaves the ledger intact
(including after a restart); SMS rows are replaced while manual rows are kept;
repeating a resync is idempotent; **failure injected at every single write** in
both non-persistent and persistent (process-death) modes, proving the ledger is
the whole old one or the finished one, never a half-rebuilt mix, with
memory/disk agreement; a failed resync retried to completion creates no
duplicates.

One test initially demanded "memory equals disk" and failed legitimately: after
a crash the next start *completes* the staged journal by design. I corrected the
test to assert "no partial mix, converges on one complete state" rather than
weakening the code.

Remaining limitation: the resync path is exercised through an injected fetcher;
no device run.

---

## Task C: skipped-message recovery and retention

### What changed

`tx_rejected_ids` was a JSON list of bare ids: no reason, no timestamp, unbounded
growth (evicted 1,000-at-a-time past 5,000), and no way to diagnose a skip.
**All ids were re-marked every scan, so a stale marker could not be refreshed** —
which also made a time-based policy impossible.

New record shape, one entry per skipped message:

```json
{"id":"<sms id>","reason":"PROMO","firstSeen":"2026-10-22T09:30:00.000"}
```

- **Minimal by construction**: only the SMS id, a coarse reason *code*
  (`CREDIT`, `OTP_SECURITY`, `NOT_COMPLETED`, `PROMO`, `BALANCE_ONLY`, `UNKNOWN`,
  `NO_PARSE`) and a timestamp. No body, merchant, amount or account.
- **90-day retention** (approved): expired records are dropped at `init()` and
  before every write; re-marking a message **keeps its original `firstSeen`**, so
  repeated scans cannot extend the window.
- **Legacy upgrade**: the old bare-id list loads fine (reason `UNKNOWN`,
  first-seen now) and is rewritten in the new shape on the next write.
- **Recovery**: `clearRejected()` (drops metadata only) + `recheckSkippedMessages()`
  (clears, then rescans) + the Settings tile "Recheck skipped messages", now
  showing the count. Saved ids still block re-import, so retries cannot duplicate.
- **Logging**: removed the `SMS FILTER: ACCEPT` line that printed
  `amount`, `merchant`, `bank` and `reference` on **every parsed SMS**
  (`smart_parser.dart:170`). It now logs the confidence band only.

### Tests (`test/rejected_sms_retention_test.dart`, 13, plus 8 in `rejected_sms_test.dart`)

Exact stored keys are `{id, reason, firstSeen}`; no body/merchant/amount/account
appears in storage; default reason is a code; expiry at >90 days on init and
being persisted; boundary behaviour (±1 s around 90 days); re-marking does not
extend the window; explicit prune with a future clock; retry idempotency across
recheck/mark/save; `clearAll` removes both transactions and metadata (in memory
and on disk); `clearRejected` spares transactions; legacy bare-id list migrates;
malformed entries are ignored instead of crashing init; nothing sensitive is
logged.

Mutation checks: disabling expiry fails 3 tests; letting a re-mark reset the
window fails 1; not persisting the prune fails 1.

### Policy as documented, not invented

The format is backward-compatible (Superset of the old list; old entries still
parse), so no incompatible format was introduced. What is *deliberately not*
done, because it would: a per-message review list showing what was skipped
(needs either stored text — a privacy cost — or an inbox re-read, which is what
the recheck already does); automatic re-parse on parser-version change (needs a
parser-version column, which is safe to add later as another optional key
because unknown keys are ignored).

---

## Task D: reduce-only `originalSms` preparation

### Trace (write → store → read)

| Where | What it does |
| --- | --- |
| `smart_parser.dart:163` | **write**: new parsed record attached the full SMS |
| `gemini_service.dart:272` | **write**: AI-parsed record attached the full SMS |
| `add_transaction_screen.dart:244` | manual entry writes `''` |
| `transaction_model.dart:73` | serialized into every stored record and every export |
| `transaction_cache_service.dart` (validation list) | accepts `originalSms` as an optional string on import |
| `transaction_details_screen.dart` | **only UI read** — the "Original SMS" panel |
| `exportToJsonString` → `settings_screen.dart` | included in the export JSON (clipboard) |
| `cache_service.dart`, `database_service.dart` | dead stores, also carry the field |

### What this phase does

`lib/services/sms_content_policy.dart` declares `retainRawBodies = false`, and
both write sites now call `SmsContentPolicy.retainedBody(...)`. New records carry
`''`; the parser's and AI adapter's derived fields are untouched. The details
panel now distinguishes "manually added" from "not stored under the reduce-only
policy" and still renders **existing stored bodies unchanged**
(`SmsContentPolicy.preserve`).

### What this phase deliberately does NOT do

- No encryption, no re-encryption, no deletion or rewrite of existing records.
  Old bodies remain readable exactly as stored (`test/sms_body_retention_test.dart`
  proves the round-trip is unchanged).
- No change to the export format (it still contains whatever is stored).
- Not a claim that the ledger is encrypted. It is still plain text at rest.

Tests: `test/sms_content_policy_test.dart` (4) covers the switch in both
directions and the no-mutation guarantee; `test/sms_body_retention_test.dart` (4)
proves a newly parsed record has no body while amount/merchant/type are correct,
and that a legacy record keeps its body through `toJson`/`fromJson`.

---

## Signing key (B1): unchanged, kept separate

Not rotated; certificate pinning untouched; no secret displayed or broadly
searched. Facts from phase 2 still stand (both files untracked, 0 commits on any
ref, public repo). **Manual review still required** by a human:

1. Diff the three commits that touched `storePassword` in
   `android/app/build.gradle.kts` — `2322c87`, `ec1d994`, `f38ff15` — for any
   literal credential. Phase 2 checked only line *shape*, never values.
2. Confirm no other clone, backup or cloud-synced copy of `android/` holds the
   keystore.
3. Review the GitHub Actions `SIGNING_KEY` / password secrets for this repo.
4. Confirm whether `ota/public/releases/*.apk` were signed with this key
   (`apksigner`, not run here).

---

## Files changed in this phase

**Production (14):** `lib/utils/period_math.dart`, `lib/providers/period_provider.dart`,
`lib/providers/transaction_provider.dart`, `lib/services/transaction_cache_service.dart`,
`lib/services/budget_monitor_service.dart`, `lib/services/smart_parser.dart`,
`lib/services/gemini_service.dart`, `lib/services/ai_service.dart`,
`lib/services/sms_content_policy.dart` (new), `lib/screens/home_screen.dart`,
`lib/screens/insights_screen.dart`, `lib/screens/activity_screen.dart`,
`lib/screens/transaction_details_screen.dart`, `lib/widgets/salary_day_prompt.dart`.

**Tests (6 new / 3 rewritten):** `salary_cycle_test.dart` (new),
`resync_safety_test.dart` (new), `rejected_sms_retention_test.dart` (new),
`sms_content_policy_test.dart` (new), `sms_body_retention_test.dart` (new),
`period_contract_test.dart` (rewritten), `rejected_sms_test.dart` (updated for
the new format), `ledger_import_test.dart` (rebased on the shared activation).

---

## Unresolved risks and what still needs real-device validation

1. **No device or emulator run at all.** Everything is verified by unit and
   widget tests. Specifically unverified on hardware: the budget notification
   now using the salary cycle (needs the notification permission); "Recheck
   skipped messages" end-to-end (needs SMS permission); the resync against a real
   inbox; the "Original SMS" panel wording on a stored legacy record.
2. **AI path not exercised**: `gemini_service` requires network and keys; only
   its record-construction branch changed (one line), and no test drives it.
3. **Behavioural change for existing users**: anyone whose salary day is not the
   last calendar day now gets different (correct) cycle boundaries, so their
   historical "this cycle" totals will move. This follows from the approved rule,
   but it is a user-visible change and should be noted in release notes.
4. **Insights relabel** from "This cycle" to "This month" is a copy change only;
   the numbers were always calendar-month.
5. **B5 remainder**: `importFromJsonString(replace: false)` merge semantics are
   unchanged; only the destructive-before-validation path was fixed.
6. **Storage**: the ledger, including any legacy `originalSms` bodies, is still
   plaintext. Task D is reduce-only by design.
7. **Paise migration still not started** and still blocked on `plan.md` §12.
