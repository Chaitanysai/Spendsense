# SpendSense — Enterprise Readiness Audit

**Date:** 2026-10-22
**Branch:** `chore/cleanup-root-files` @ `33166cb062690c2c4ffa7e520b7a1071c4ddbe93`
**Reported version:** `2.0.3+23` (**unchanged by this work**)
**Method:** source review across four read-only specialist lanes plus direct
verification. Findings are separated into **verified by probe** (a test was run),
**verified by source** (the line was read), and **estimated** (reasoning only).

> **Evidence discipline.** This audit was produced by specialist agents whose
> summaries are claims, not evidence. Three of their high-severity findings were
> re-tested directly; **one was wrong and has been corrected** (see §A.4). The
> distinction between verified and estimated is stated per finding.

---

## Baseline

| Check | Result |
| --- | --- |
| `flutter analyze` | **No issues found** (clean, before and after this work) |
| `flutter test` | **258 passed, exit 0** |
| Test files | 20 |
| Uncommitted changes | 69 modified/untracked paths — **all preserved, none reverted** |
| Git operations performed | none (no commit, branch, reset, clean, or stash) |

The working tree carries a large in-flight redesign (animation/glassmorphism
work: `fade_indexed_stack`, `pressable`, `glass_card`, `sound_*`, `update_*`,
`ota/`). This audit treats that as the current baseline and does not revert it.

---

## Architecture summary

- **Framework:** Flutter/Dart, Material 3, single `MaterialApp` with no router —
  `home: MainNavigationShell` (`lib/main.dart:76`).
- **State:** `provider` — `TransactionProvider` (ledger), `AuthProvider` (profile
  only), `PeriodProvider` (cycle maths), `ThemeProvider`, `UpdateProvider`,
  `SoundProvider`. No other state library.
- **Persistence:** `SharedPreferences` via `TransactionCacheService`, keyed
  `tx_<id>` + a `tx_cache_ids` index + `tx_rejected_ids` + `tx_cache_meta`.
  Budget is a separate `monthly_budget` double.
- **Dead persistence:** `CacheService` (prefs blob) and `DatabaseService`
  (SQLite) exist but are **imported by nothing**.
- **Money model:** `int amount` = whole rupees, no unit marker, no schema version.
- **Ingest:** `SmartParser` (local regex) → optional `GeminiService` (AI, only
  when local confidence < 0.8) → `TransactionProvider` → cache.
- **SMS:** `flutter_sms_inbox`, `READ_SMS` only, last 800 messages, scan window
  from a user-set start date.
- **OTA:** custom self-hosted update channel with **real** APK signer pinning.

---

## Readiness gaps by severity

### A. Financial correctness

| ID | Sev | Finding | Evidence | Verified by |
| --- | --- | --- | --- | --- |
| **F1** | **Critical** | `salaryDay` is collected, persisted, and displayed but **never used**. `salaryAlignedPeriod()` is `static` and hard-codes "the last calendar day" as the cycle boundary. A user who sets salary day = 25 gets a window anchored to the 31st, and every cycle total, budget figure, and insight is wrong. | `period_provider.dart:108-135` (no `_salaryDay` reference); `salaryAlignedPeriod` is `static` and cannot read it; `salary_day_prompt.dart:171` calls it with no `day` argument although its own `_periodPreview(int day)` takes one | **source** |
| **F2** | **Critical** | Home headline + budget gauge use the **salary-aligned cycle**; `BudgetMonitorService` uses the **calendar month** (`totalExpenses` → `expensesInPeriod(null)` → `_isLocalMonth`). The app can show "₹4,000 left" while notifying "Budget exceeded" about the same budget. | `home_screen.dart:351` and `:772` (period) vs `budget_monitor_service.dart:45` `provider.totalExpenses`; `transaction_provider.dart:93-100` calendar fallback | **source** |
| **F3** | **High** | Whole-rupee `int` with no unit marker; `fromJson` does `(json['amount'] as num?)?.toInt() ?? 0` — silently truncates paise **and** silently converts a missing/malformed amount to ₹0. | `transaction_model.dart:86` | **source** |
| **F4** | **High** | Local parser returns `double`, stores `.toInt()` → paise truncated at ingest. Add screen parses `double`; edit screen parses `int` and rejects `239.50` instead of truncating — so the two manual paths disagree. | `smart_parser.dart:153,179`; `add_transaction_screen.dart:235`; `transaction_details_screen.dart:345` | **source** |
| **F5** | **High** | AI amount validation is `double` equality against the **sanitized** string while the confirmed amount came from the **raw** string. `sanitizeSms` masks `\b\d{4,6}\b` → `***`, so a 4–6 digit amount (most real debits) is masked before the model sees it. The AI is validated against a value it was shown only as asterisks. | `gemini_service.dart:69`, `:93-95`, `:144`, `:221-225` | **source** |
| **F6** | High | "Monthly cost" on Recurring includes **income**: `detectRecurring(provider.transactions)` passes the full ledger and `merchantTx.fold` sums `tx.amount` for income rows. A salary becomes a subscription cost. Irregular merchants are also counted once regardless of frequency. | `recurring_detector_service.dart:102-104,125-147`; `recurring_screen.dart:21-23` | **source** |
| **F7** | Medium | Settings budget dialog reads `toStringAsFixed(0)` and writes `int.tryParse` — opening and saving silently rewrites a fractional legacy budget to a whole number. | `settings_screen.dart:442,452-455,468` | source |
| **F8** | Medium | Activity search matches the raw integer while the tile renders formatted Indian grouping (`₹1,23,456` typed as `1,23` finds nothing). Amount *sort* is correctly integer-based. | `activity_screen.dart:354-359` vs `:371-374` | source |
| **F9** | Medium | Manual edit can flip Expense→Income on a parsed row, reversing its sign across every total, with no confirmation. | `transaction_details_screen.dart:122-147,366-375` | source |
| **F10** | Medium | Detail screen renders the **edit buffer** not the stored amount, and with **no sign**, while the tile renders `− ₹450`. Same transaction reads as signed in one place, unsigned in another. | `transaction_details_screen.dart:321-322` vs `transaction_tile.dart:154` | source |

#### Findings tested and **not** reproduced (correcting the lane reports)

| Claim from a lane report | Probe result | Verdict |
| --- | --- | --- |
| **"Insights tab never rebuilds — displays stale financial figures"** (reported High, "blocks release") | Wrote a widget probe: seeded an empty ledger, opened Insights (showed ₹0), returned to Home, added a ₹4,321 transaction while Insights was hidden, returned. **Insights showed ₹4,321.** | **WRONG — not a defect.** `insights_screen.dart:31` subscribes via `TickerMode.valuesOf(context)`, which is restored on tab activation and does force a rebuild. No fix needed. |
| **"`'credit'` substring destroys the `Precision: Rs.500 debited …` debit"** (reported High, "blocks release") | Parser probe on `"Rs.500 debited from A/c XX1234. Instant Credit Card available."` → `amount=null`. The SMS is rejected. | **Partly right, wrong mechanism.** It is rejected at the `isDebitExpenseSms` gate (`smart_parser.dart:74`), so it lands in `tx_rejected_ids` **permanently** and can never be recovered — but a "Credit Card" mention is arguably out of scope for a *debit* parser. The real defect is the permanent-rejection funnel (R3), not the regex alone. |
| **"`_boundaries` `'ref'` truncates `Precision` merchants"** | Probe on `"Rs 450 debited at Preferred Car Rentals"` → `amount=450, merchant=Preferred Car Rentals` — **correct**. | **WRONG.** `'ref'` does not appear in "Preferred". A balance-first SMS (`Avl Bal … Rs 450 debited`) is rejected at the gate, not mis-parsed as the balance. |
| **"forceFullResync purges before it can rebuild"** | Probe could not complete (needs a platform binding for the SMS channel). The code path is nonetheless unambiguous: `clearAll()` at `:302` precedes any scan. | **correct by source**, not by probe. |

### B. Security and privacy

| ID | Sev | Finding | Evidence |
| --- | --- | --- | --- |
| **S1** | **Medium (investigated, see remediation-phase-2.md)** | Not tracked and never committed on any local ref; repo is public so residual uncertainty remains. A release keystore `android/app/upload-keystore.jks` **and** `android/key.properties` exist on disk. `.gitignore` covers both, but git-ignore does **not** untrack an already-committed file. Because the release cert is **pinned inside the app**, a leaked key is a stuck state, not a clean reset. | `android/app/upload-keystore.jks`, `android/key.properties` (contents never opened); `.gitignore:55-57`; pin at `update_config.dart:18-19` |
| **S2** | **High** | The full ledger **and the raw bank SMS body** are persisted in plaintext `SharedPreferences`. `originalSms` is written verbatim, so account suffixes, UTRs, merchants and any co-mingled OTP sit at rest in cleartext. | `transaction_cache_service.dart:71`; `transaction_model.dart:73`; `smart_parser.dart:160` |
| **S3** | **High** | `REQUEST_INSTALL_PACKAGES` is declared **unconditionally**, in every build, including any Play build that has no OTA channel. Self-updating APKs from Firebase Hosting is a restricted Play pattern. | `AndroidManifest.xml:28` |
| **S4** | Medium | Export copies the **entire ledger including `originalSms`** to the system clipboard, where other apps and vendor cloud-clipboard can read it, with no sensitive flag. | `settings_screen.dart:530`; `transaction_cache_service.dart:140-150` |
| **S5** | Medium | `--dart-define` API keys are compiled into the APK, contradicting the documented "keys never ship in the APK" claim. | `app_config.dart:37-47,54`; `main.dart:31-33` |
| **S6** | Medium | `debugPrint` interpolates merchant **and amount** for every AI parse, on the same log line as provider names. | `gemini_service.dart:111,183` |
| **S7** | Medium | There is **no authentication and no device-local app lock**. `LoginScreen` collects name+email, sets `loggedIn = true`, and is **never routed to** (`main.dart:76` goes straight to the shell). It is decorative UI implying a protection that does not exist. | `login_screen.dart:36-61,156-173`; `auth_provider.dart:13-14,58-79` |
| **S8** | Low | R8/minify/shrinkResources are **disabled** and no `proguard-rules.pro` exists. | `android/app/build.gradle.kts:70-78` |
| **S9** | Low | `docs/OTA_UPDATES.md` references `.github/workflows/android-release.yml` as a fail-closed cert-pin gate. The workflow **exists in the tree** but its claimed guarantees are unverified by this audit (not executed). | `.github/workflows/android-release.yml` |
| **Verified good** | — | OTA signature pinning is **real**: the downloaded APK's signer DER is hashed and compared to a compile-time constant, so a compromised manifest host cannot push arbitrary code. Host allowlist, HTTPS, path-traversal guard, native installer path check (`canonicalFile`), FileProvider scoped to `cache/updates/`, `allowBackup=false` + empty data-extraction rules, `RECEIVE_SMS` correctly absent, AI keys in genuine EncryptedSharedPreferences. | `update_service.dart:287-315`; `MainActivity.kt:73-136`; `AndroidManifest.xml:34-36`; `secure_storage_service.dart:6-10` |

### C. Reliability and data durability

| ID | Sev | Finding | Evidence | Verified by |
| --- | --- | --- | --- | --- |
| **R1** | **Critical** | `importFromJsonString(replace: true)` calls `clearAll()` **before** deserializing. One malformed element destroys the existing ledger. | `transaction_cache_service.dart:167-177` | **probe: `before=2 after=0`** |
| **R2** | **High** | `forceFullResync()` calls `clearAll()` and clears `_transactions` **before** scanning. `syncFromSms` can then abort silently (permission denied, plugin returns `[]` on any exception, or a caught throw), leaving the user with an empty ledger. Reachable from one tap on the scan-window sheet. | `transaction_provider.dart:302-310`; `sms_service.dart:65-68`; `transaction_provider.dart:208-213,286-287` | source (probe blocked by platform channel) |
| **R3** | **High** | A rejected SMS is suppressed **forever**: `clearAll()` never removes `tx_rejected_ids`, and `contains()` consults it. A debit the parser missed is invisible, unrecoverable, and not re-evaluated when the parser improves. | `transaction_cache_service.dart:39-40,93-104,106-115`; `transaction_provider.dart:241,273` | source |
| **R4** | **High** | No re-entrancy guard on `syncFromSms`. The only check is a caller-side `!provider.isSyncing`, which cannot cover the provider's own `forceFullResync` path. Two overlapping syncs can double-call the AI for the same SMS, and the **first to finish** clears `_isSyncing` while the second is still writing. | `transaction_provider.dart:197-201,288-291`; `activity_screen.dart:102` | source |
| **R5** | High | `put()` writes the payload then the index non-atomically; `loadAll()` only walks the index. A crash between the two **orphans the record forever** — invisible to the list *and to export*. No startup reconciliation. | `transaction_cache_service.dart:57-75` | source |
| **R6** | Medium | `TransactionProvider` has **no `dispose()`** and calls `notifyListeners()` unconditionally after async work. (`UpdateProvider` does this correctly — copy its `_disposed` pattern.) | `transaction_provider.dart:48-54,290`; `update_provider.dart:192-194` | source |
| **R7** | Medium | AI provider chain is 4 providers × 12s timeout, sequential, **per SMS**, with no cancellation, no circuit breaker, and no connectivity check. Three keys misconfigured ⇒ up to 36s per unparseable message with `_isSyncing` true throughout. | `gemini_service.dart:97-118,149` | estimate |
| **R8** | Low | Swallowed exceptions make the UI claim success: any query failure returns `[]` (indistinguishable from "no SMS") and the sync still completes normally. | `sms_service.dart:65-68`; `transaction_provider.dart:286-287` | source |
| **R9** | Low | `TransactionModel.fromJson` mints a **random** id when `id` is absent — which then becomes a storage key and can never dedupe against its source SMS. | `transaction_model.dart:85` | source |

### D. Performance (all figures **estimated**, none profiled)

| ID | Sev | Finding | Evidence |
| --- | --- | --- | --- |
| **P1** | High | O(n²) index write: `_flushIds()` serializes the **entire** id list on **every** new transaction, inside the sync loop. Plus a full `sort` and a `notifyListeners` per transaction. | `transaction_cache_service.dart:191-193`; `transaction_provider.dart:262-270` |
| **P2** | High | Whole ledger re-derived in `build()`: Home does ~15 full passes and 2 sorts **per notification**, ~40–60 times per sync (`_DailySpendCard` alone scans 7×). Activity re-filters+sorts on **every keystroke**. Settings rebuilds entirely on every sync just to render one date. | `home_screen.dart:67-81,1045-1050`; `activity_screen.dart:117,177`; `settings_screen.dart:93` |
| **P3** | Medium | N+1 startup read: one awaited `getString` per id, sequentially. | `transaction_cache_service.dart:57-67` |
| **P4** | Medium | `BackdropFilter` on the persistent nav bar (18σ) is composited over every tab, plus one per `GlassCard` (4–6 on Home). See §G for the redesign's change here. | `floating_nav_bar.dart:47-48`; `glass_card.dart:102-107` |
| **P5** | Medium | Every `RegExp` in `SmartParser` is constructed inline inside loops (three per currency match) instead of `static final`. | `smart_parser.dart:188-212` |
| **P6** | Low | `GoogleFonts.poppins` is resolved per `AppText.*` call in `build`, and Poppins is not declared as an asset, so the first cold/offline launch falls back. | `app_text_styles.dart:15-103`; `pubspec.yaml:46-49` |
| **Verified good** | — | Startup is **not** blocked: `main.dart` awaits nothing before `runApp`; providers load asynchronously behind a loading state. `ListView.builder` is used where it matters. | `main.dart:34-57` |

### E. UX, accessibility and design

| ID | Sev | Finding | Evidence |
| --- | --- | --- | --- |
| **U1** | **High** | Money colours fail contrast on light surfaces: `incomeGreen` **2.62:1** and `expenseRed` **3.30:1** against white — used for amounts at 14.5sp, so sub-AA at *any* size. | `transaction_tile.dart:157`; `home_screen.dart:875-894`; token values in `app_colors.dart` |
| **U2** | High | `AppErrorState` is defined but **used by no screen**. SMS permission denial is silent (`return` with no UI). No offline state anywhere. No retry surface. | `app_states.dart`; `transaction_provider.dart:208-213` |
| **U3** | Medium | `textTertiary` is **4.27:1** on the light background (fails AA body) and is the meta-text colour everywhere. | `app_colors.dart:162`; `transaction_tile.dart:137` |
| **U4** | Medium | Plain-white splash in **both** light and night (`values-night` reuses the same drawable) → white flash before the AMOLED UI, with no logo. | `res/drawable/launch_background.xml:4`; `values-night/styles.xml:7` |
| **U5** | Medium | Fixed-height containers clip at large text scale: Insights stat cards `height: 168`, chip strip `height: 36`, nav bar `height: 68`, buttons `54/50`. Existing tests only reach scale 1.6, not the 2.0 maximum. | `insights_screen.dart:58,483`; `app_button.dart:54,141` |
| **U6** | Medium | Sub-10sp text: 8.5sp "DEFAULT"/"REVIEW" badges, 9sp nav labels. | `appearance_screen.dart:291`; `transaction_tile.dart:120`; `floating_nav_bar.dart:130` |
| **U7** | Medium | Touch targets under 48dp: balance eye toggle 44×44, category chips 44. | `home_screen.dart:550-551`; `add_transaction_screen.dart:509` |
| **U8** | Medium | Four screens have **zero** `Semantics`: Insights, Cards, Recurring, Transaction details — including data-dense rows read as fragmented nodes. | grep across `lib/screens/` |
| **U9** | Low | Design-token drift: 6 hardcoded hex literals in `main.dart` plus 5 elsewhere that duplicate existing token values; off-grid `EdgeInsets` and ~42 `<6px` `SizedBox` gaps. | `main.dart:97,101,150,153,193,232`; `settings_screen.dart:342`; `insights_screen.dart:355` |
| **U10** | Low | Copy inconsistency: "Add expense" vs "Add transaction" vs "expense" for the same action; currency rendered three ways (`Formatters`, hand-rolled `₹{x}`, `₹ {x}`); three date formats. | `home_screen.dart:648`; `add_transaction_screen.dart:119,193`; `recurring_screen.dart:74`; `transaction_details_screen.dart:322` |
| **U11** | Low | `LoginScreen` is dead code (see S7). No onboarding or first-run flow exists. | `login_screen.dart` (unreferenced) |
| **Requires device** | — | Actual overflow at scale 2.0, TalkBack reading order, splash flash duration, and whether non-Emerald dark palettes look muddy — **not** validated; no emulator run was performed. | — |

---

## Migration blocker (explicit)

**The integer-paise migration is NOT authorized and has NOT been started.**

`plan.md` remains *planning only*, exactly as its own §3/§12 require. Its
factual §1 claims were re-verified and **all hold**; its line references are
stale in places. Nothing in `lib/models/transaction_model.dart`, the cache
format, or the budget storage was changed by this work, and **no v2 record can
be written** by the code as it stands.

`plan.md` §12 lists 7 open approval questions. Two sit upstream of them and must
be resolved first, because they are **unit-independent** and a paise migration
would carry them forward unchanged:

1. **F1** — the salary-day boundary is inert. Migrating to paise would faithfully
   migrate *wrongly-bounded* totals.
2. **F2** — two components disagree on what a "period" is.

---

## Adopted agent assets

See `docs/agent-research/github-agent-research.md` for the full research record,
attribution and rejections. Summary:

| Asset | Type | Source |
| --- | --- | --- |
| `.opencode/agent/financial-integrity-reviewer.md` | read-only subagent | Original; fail-closed principle attributed to `agent-wallet-sdk` (MIT) |
| `.opencode/agent/privacy-security-auditor.md` | read-only subagent | Original |
| `.opencode/agent/flutter-ux-accessibility-reviewer.md` | read-only subagent | Original |
| `.opencode/agent/performance-reviewer.md` | read-only subagent | Original |
| `.opencode/agent/release-readiness-reviewer.md` | read-only subagent | Dimensions adapted from `agents/02-code-review-agent` + `agents/15-unit-test-generator` (MIT) |
| `.opencode/skill/financial-integrity/SKILL.md` | skill | Original |

No code, dependency, script or credential import from either repository. The
`agent-wallet-sdk` payment SDK was **rejected outright** (upstream-paused for
security, and blockchain payment is out of scope for an expense ledger).
