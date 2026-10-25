# SpendSense — Public-Release Roadmap

**Companion to** `docs/product-readiness/enterprise-readiness-audit.md`.
Every item below traces to a verified finding in that document. Effort figures
are **estimates**, not commitments.

**Release posture today: NOT READY.** Six items block a public release.

---

## Blocking work — must complete before any public release

### B1 · Verify the signing key is not committed — **Medium (investigated 2026-10-22: not tracked, never committed; see remediation-phase-2.md)**
- **Evidence:** `android/app/upload-keystore.jks` and `android/key.properties`
  exist on disk. `.gitignore` covers both but cannot untrack an already-committed
  file. The release cert is pinned in-app, so a leak is a stuck state.
- **Impact:** total compromise of the update channel and of any future
  Play-signed lineage.
- **Fix:** run exactly one command, outside this audit:
  `git ls-files --error-unmatch android/app/upload-keystore.jks android/key.properties`
  - Non-zero for both → untracked, downgrade to Medium; add a CI guard.
  - Zero (listed) → **treat the key as compromised**: rotate, ship a final
    update signed with the old key that pins the new one (the app already
    documents this at `docs/OTA_UPDATES.md:286-290`), then purge history.
- **Effort:** 30 min to verify; 1–2 days if rotation is needed.
- **Tests:** add a CI step failing on any tracked `*.jks`/`*.keystore`/`key.properties`.
- **Blocks release:** yes, until verified.

### B2 · Render the ledger unreadable at rest — **High**
- **Evidence:** `transaction_cache_service.dart:71` writes JSON to plaintext
  `SharedPreferences`; `originalSms` is stored verbatim (`transaction_model.dart:73`).
- **Impact:** rooted/forensic/backup access yields the complete financial history
  with raw bank SMS text. A "finances" listing with plaintext bank SMS is a
  disclosure and store-review problem.
- **Fix:** encrypt the store (SQLCipher, or AES-GCM with the key in the Android
  Keystore).**Do not** reuse the dead `DatabaseService` as-is — it is unencrypted
  and unversioned. Stop persisting `originalSms` past parse time (store a hash
  plus extracted fields) and exclude it from export.
- **Dependency:** couples to the money migration — both touch the same store. Land
  the encryption envelope **first**, with a tested v1→v1 migration, so the paise
  migration later only changes field semantics, not the container.
- **Effort:** 4–6 days.
- **Tests:** round-trip every field; open an existing v1 store and prove no data
  loss; assert the on-disk file contains no plaintext merchant or SMS body.
- **Blocks release:** yes.

### B3 · Fix the cycle boundary (`salaryDay` inert) — **Critical**
- **Evidence:** `period_provider.dart:108-135` — `salaryAlignedPeriod` is
  `static` and hard-codes the last calendar day; `_salaryDay` is never read.
- **Impact:** every cycle total, budget figure and insight is wrong for anyone
  whose salary day is not the last of the month. The app asks for the salary day
  and then ignores it.
- **Fix:** make the range take `salaryDay` (instance method reading the provider,
  or an explicit parameter), handle months shorter than the salary day
  (clamp to last day), and thread it through `nextSalaryDate` too.
- **Effort:** 1 day.
- **Tests:** salary day 1/25/31; February (28 and 29); day-of-month == salary day
  and == salaryDay − 1; assert the union of consecutive periods is contiguous and
  non-overlapping.
- **Blocks release:** yes.

### B4 · One period definition, shared by UI and notifications — **Critical**
- **Evidence:** `home_screen.dart:351,772` use the cycle;
  `budget_monitor_service.dart:45` uses the calendar month.
- **Impact:** the dashboard and the budget notification contradict each other
  about the same budget.
- **Fix:** have `BudgetMonitorService` consume `expensesInPeriod(currentPeriod)`
  from the same `PeriodProvider`; delete or explicitly rename the `period == null`
  calendar fallback.
- **Dependency:** after B3 (needs a correct period first).
- **Effort:** half a day.
- **Tests:** a transaction in the straddle window between two cycles must affect
  the dashboard and the notification identically.
- **Blocks release:** yes.

### B5 · Stop destructive-write-before-validate — **import half FIXED 2026-10-22 (86 tests); forceFullResync half still open**
- **Evidence:** `transaction_cache_service.dart:167-177` clears before
  deserializing (**probe: `before=2 after=0`**); `transaction_provider.dart:302-310`
  clears before scanning.
- **Impact:** one malformed import or one tap on the scan-window sheet can delete
  the user's entire history.
- **Fix:** parse and fully validate first, then clear, then write, with a rollback
  snapshot. For resync: stage into a temporary namespace and swap only after the
  scan returns non-empty; surface an error if a non-empty ledger would be replaced
  by an empty scan.
- **Effort:** 2 days.
- **Tests:** invalid payload must leave the prior ledger byte-identical (the probe
  from this audit is a ready-made regression test); rescan with permission denied
  and with a failing SMS channel must both preserve the ledger.
- **Blocks release:** yes.

### B6 · Make rejected SMS recoverable — **PARTLY FIXED 2026-10-22 (recheck + clearAll); reason codes and retention need a schema decision**
- **Evidence:** `tx_rejected_ids` survives `clearAll()`
  (`transaction_cache_service.dart:106-115`) and gates `contains()` (`:39-40`).
- **Impact:** a debit the parser missed is permanently invisible, with no UI to
  discover it, and stays lost when the parser improves.
- **Fix:** store rejections with a parser/schema version and re-evaluate on
  version bump; clear them in `clearAll()`; add a user-visible "skipped messages"
  surface.
- **Dependency:** interacts with the unit migration — a rejected record must
  record which unit/schema it was rejected under.
- **Effort:** 1–2 days.
- **Tests:** reject → bump parser version → rescan → the message is reconsidered;
  clear-all removes the rejection set.
- **Blocks release:** yes (user data silently lost).

### B7 · Remove `REQUEST_INSTALL_PACKAGES` from Play builds — **High**
- **Evidence:** `AndroidManifest.xml:28`, declared unconditionally.
- **Impact:** restricted Play pattern; trains users to approve unknown sources.
- **Fix:** move the permission into a non-Play flavour manifest, or drop it and
  distribute updates through Play / browser download.
- **Effort:** half a day.
- **Tests:** `apkanalyzer` on both flavours confirms the permission is present
  only in the direct-distribution variant.
- **Blocks release:** yes, for Play.

---

## High priority — before or immediately after public release

| ID | Item | Effort | Notes |
| --- | --- | --- | --- |
| H1 | Re-entrancy guard on `syncFromSms` (`transaction_provider.dart:197`) | 0.5 d | `Future<void>? _syncInFlight`; `forceFullResync` must await it. |
| H2 | Startup reconciliation for orphaned `tx_<id>` records | 1 d | `prefs.getKeys()` sweep on `init()`; also makes the index derivable. |
| H3 | Money contrast: `incomeGreen` 2.62:1, `expenseRed` 3.30:1 on white | 0.5 d | Darken light-mode money tokens to ≥4.5:1; verify against every palette. |
| H4 | Wire `AppErrorState` + permission-denied + offline states | 2 d | Defined but unused. Add to Home/Activity/Insights/Cards. |
| H5 | AI validation: stop masking amounts, compare integers | 2 d | Couples to the paise migration — do the integer comparison there, but fix the *masking* now (send structured fields, not the raw SMS). |
| H6 | `double`→`int` truncation at ingest (F3/F4) | **part of migration** | Cannot be fixed piecemeal — this **is** the paise migration. Gated on `plan.md` §12. |
| H7 | Recurring "monthly cost" includes income | 0.5 d | Filter `type == expense`; handle irregular frequency honestly. |
| H8 | O(n²) `_flushIds` + per-transaction notify | 1 d | Batch writes, single sort, throttled notification. |
| H9 | Clipboard export of full ledger + raw SMS | 0.5 d | Write a file via SAF / share sheet instead; strip `originalSms`. |
| H10 | `--dart-define` key fallback in release builds | 0.5 d | Return `''` in `kReleaseMode`. |
| H11 | Strip merchant/amount from `debugPrint` | 0.5 h | `gemini_service.dart:111,183`. |
| H12 | `TransactionProvider.dispose()` | 0.5 h | Copy `UpdateProvider`'s `_disposed` guard. |
| H13 | Enable R8 + `proguard-rules.pro` | 1 d | Keep `FileProvider`, `MainActivity`, notification receivers; smoke-test on device. |
| H14 | Night-mode splash (no white flash) | 0.5 d | `values-night` launch background + logo layer-list. |

---

## Medium — quality and polish

- Period-safe text scaling: replace fixed heights at `insights_screen.dart:58,483`,
  `app_button.dart:54,141`; extend the text-scale test to 2.0 (currently 1.6).
- N+1 startup read (`transaction_cache_service.dart:57`) — batch or move to one blob.
- Build-time derivation instead of per-`build` recomputation (`home_screen.dart:67-81`);
  throttle Activity search (`activity_screen.dart:177`).
- Hoist `SmartParser`'s `RegExp`s to `static final`.
- Add `Semantics` to Insights, Cards, Recurring, Transaction details.
- Touch targets: eye toggle 44→48, category chips 44→48.
- Raise the type floor: 8.5sp badges → ≥10sp; nav labels 9 → 10 (done in this pass
  for the nav bar specifically).
- `textTertiary` light mode 4.27:1 → darken toward ~`#5A695F`.
- Budget dialog round-trip (`settings_screen.dart:442`) — stop rewriting a
  fractional budget to a whole number on open/save.
- Type-flip confirmation on manual edit (F9).
- Detail screen: show the **stored** amount and its sign (F10).
- Activity amount search against formatted values (F8).
- Delete dead `cache_service.dart` / `database_service.dart` (and then the
  `sqflite` dependency, unless it becomes the encrypted store).
- iOS `key.properties`/keystore note: the repo has `ios/`, `macos/`, `linux/`,
  `windows/` targets — decide explicitly whether they are supported, and either
  configure or remove them from the release surface.

---

## Low — hygiene

- Token drift: replace the 6 hex literals in `main.dart` and the 5 elsewhere with
  named tokens; promote the text tiers in `app_colors.dart:155-162` to named tokens
  (they are the root cause of the drift).
- Off-grid spacing: `~42` sub-6px `SizedBox` gaps and `EdgeInsets.fromLTRB(12,0,12,10)`.
- Copy: settle on one action name ("Add transaction" vs "Add expense"), one
  currency formatter, one date format.
- Delete or route `LoginScreen` (dead UI implying auth that does not exist).
- Offline `connectivity_plus` check before an AI sync.

---

## Ordering rationale

1. **Signing key (B1)** first — it is a 30-minute verification that could change
   everything downstream, and it gates the update channel itself.
2. **Correctness of boundaries (B3 → B4)** before any money-format work. A paise
   migration performed on top of an inert salary-day boundary would enshrine the
   wrong window at a higher precision.
3. **Durability (B5, B6)** before new features. A user who loses their ledger once
   does not come back, regardless of how good the navigation looks.
4. **Encryption (B2)** before the money migration, so the container changes once.
5. **The paise migration** only after `plan.md` §12's seven questions are answered
   *and* B3/B4 land.
6. Then accessibility and performance, then store preparation.

---

## What this pass deliberately did **not** do

- Did not start the paise migration or write any v2 record.
- Did not bump the version, commit, push, deploy or publish OTA.
- Did not change `pubspec.yaml` dependencies.
- Did not touch manifests, signing config, credentials, or `ota/` artifacts.
- Did not revert or overwrite any pre-existing uncommitted work.
- Did not fix persisted-financial-meaning, auth-boundary or release-compat
  defects — those are documented above and deferred to explicit migration and
  release phases.
