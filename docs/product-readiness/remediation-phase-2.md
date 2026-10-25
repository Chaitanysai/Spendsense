# Release-blocker remediation, phase 2

Date: 2026-10-22. Scope: B1, B5, B6, F1/F2, S2 from `enterprise-readiness-audit.md`.
No commit, push, deploy, branch switch, reset, clean, stash, dependency change,
version change or OTA change was made. Existing uncommitted work was kept.

## B1. Signing-key exposure

### Evidence checked (no file contents, passwords, aliases or keys were read or printed)

| Check | Result |
| --- | --- |
| `git ls-files --error-unmatch android/app/upload-keystore.jks` | exit 1 (not tracked) |
| `git ls-files --error-unmatch android/key.properties` | exit 1 (not tracked) |
| Commits touching either path, all 16 refs (`git log --all -- <path>`) | 0 and 0 |
| Any `.jks/.keystore/.p12/.pfx/.pem/key.properties` name ever added, deleted or renamed in any ref | none |
| Reflog entries naming such a file | none |
| Stash (1 entry, pre-existing): tracked paths | 18, none keystore-like; no untracked-files parent |
| Remote branches containing history | `origin/main`, `origin/chore/cleanup-root-files`, `origin/docs/readme-refresh` |
| GitHub repo `Chaitanysai/Spendsense` | public, 0 forks, 0 stars, last push 2026-10-21 |
| Ignore rules | `android/.gitignore:12` (`key.properties`) and `:14` (`**/*.jks`) match both files |
| Files on disk | both exist (2752 and 96 bytes); contents not opened |

### Conclusion

The two files were never committed on any local ref, so the keystore is not in
the Git history this clone can see. That does not prove it was never exposed.
The repository is public, so any commit that did reach it would be world-readable.

Things I checked that came back clean:
- Three commits changed the text `storePassword` in `android/app/build.gradle.kts`.
  I compared the shape of the added lines (lengths and structure only; values
  not printed). They are environment/properties lookups, null checks, identifier
  assignments, and quoted strings that look like Gradle error text. This is a
  structural check, not proof. A human should diff those three commits
  (`2322c87`, `ec1d994`, `f38ff15`) for literals.
- The one committed release APK (`release/spendsense-v1.0.4+4-release.apk`,
  53 MB, commit `2166a9b`) is in published history on all three remote branches
  and was removed from the tree in `25779e3`. I scanned its blob for PEM
  private-key headers (0), JKS magic bytes (0) and PKCS#12 markers (0).
  The string `PRIVATE KEY` appears 15 times with no `BEGIN` header; that is
  consistent with library string tables but I did not inspect the matches.
  Signed APKs carry the certificate, which is public by design.

### Remaining uncertainty (cannot be closed from this repository)

- Other clones, backups or cloud-synced copies of `android/` on this or other machines.
- GitHub Actions logs and the contents of the `SIGNING_KEY` secret the workflow decodes into `android/app/upload-keystore.jks`.
- Whether the APK in `ota/public/releases/` was signed with this key (needs `apksigner`, which I did not run).
- File modification times cannot be used to date exposure; timezone is unknown.

### Required decisions (none taken)

1. Owner confirms the key was only ever on trusted machines. If not, treat it as compromised.
2. If rotation is needed: the certificate is pinned in `lib/config/update_config.dart` and
   `tool/generate_ota_manifest.dart`, so rotation needs a bridge release signed by the
   old key (procedure in `docs/OTA_UPDATES.md`). Do not delete the old key first.
3. Add a CI guard that fails if any `*.jks`, `*.keystore` or `key.properties` becomes tracked.
4. Decide whether to purge the 53 MB APK from history (rewrites history; needs its own approval).

Audit finding S1 is downgraded from Critical (unverified) to Medium (not tracked; residual uncertainty above).

## B5. Destructive import

Reproduced (test, synthetic data): `replace: true` with one malformed element took
a 2-record ledger (ids `keep-1`, `keep-2`, total 333) to 0 records. The test failed
with `Expected: ids=[keep-1, keep-2], total=333 / Actual: ids=[], total=0`.

A second defect was found while designing the fix: the record id becomes the
storage key (`tx_` + id), so an imported id of `cache_ids`, `rejected_ids` or
`cache_meta` would overwrite the ledger index, the skipped-message set or the
sync metadata. These ids are now rejected.

### Policy (documented in `TransactionCacheService`)

| Rule | Behavior |
| --- | --- |
| Validation | whole file validated first; no I/O before it passes |
| Envelope | `{version?, count?, transactions:[...]}` or a bare list |
| Version | absent, `2`, `"2"`, `"2.0"`, `2.0` accepted; anything else rejected |
| Record | id: non-empty string, max 200 chars, not reserved. amount: integer 1..1,000,000,000,000 (a whole-number double such as `450.0` is accepted as 450; fractional rejected). type: `expense` or `income`. date: parseable. Optional fields must have the right type |
| File | duplicate ids, `count` disagreeing with records, empty payload in replace mode rejected |
| merge (default) | upsert by id, imported wins |
| replace | ledger becomes exactly the imported set |
| Retry | both modes idempotent |
| Errors | `LedgerImportException(code, message, recordIndex)`; fixed wording, never echoes record contents |

### Activation

SharedPreferences cannot change several keys atomically. A validated import is
written as one journal key (`txj_import_journal`, outside the `tx_` namespace),
payloads are written and read back, and the visible ledger switches in a single
write of the id index. A failure before that write is rolled back. A crash is
completed from the journal at next start. If cleanup of replaced payloads fails
after the switch, the new ledger stays live and the next start finishes cleanup.

### Tests (`test/ledger_import_test.dart`, 86 tests)

- Reproduction of the audit case.
- 31 rejection cases x merge and replace, each proving ids, total, and every persisted byte are unchanged, including after a restart.
- Success semantics, idempotent retries, restart persistence, export-then-replace round trip.
- A failure injected at every single write of an import (both modes): all-or-nothing, memory and disk agree.
- A process death at every write (all later writes fail too), then restart: the ledger is exactly the old one or the finished one, never partial, and a healthy retry converges.

Mutation checks (production code deliberately broken, then restored): no rollback
fails 2 tests; clearing before validating fails 36; removing the reserved-id guard fails 6.

Limits: the test seam is `writeHook` on the service; the UI path
(`settings_screen.dart`) now shows the specific rejection reason, but there is no widget
test for that dialog. Import still arrives as pasted text, not a file.

## B6. Skipped SMS

### Why they were unrecoverable

- `markRejected` adds an SMS id to `tx_rejected_ids`, and `contains()` treats that set as "already handled".
- `clearAll()` removed saved transactions but not `tx_rejected_ids` (audit R3 confirmed by reading `transaction_cache_service.dart`). Changing the scan date calls `forceFullResync()` then `clearAll()`, so skipped ids survived every rescan.
- There was no other way to clear them.
- Skipped messages are those that fail `SmartParser.isDebitExpenseSms` (line 237) or pass it but yield no parse (line 273). One lane report claimed a low-confidence debit with no AI key is rejected; that is wrong. In that case the local result is saved with `needsReview: true` (line 258).

### Implemented

- `clearAll()` now also clears the skipped set, in memory and on disk.
- `clearRejected()` forgets only skipped ids and returns the count; saved ids keep blocking re-import, so rechecks cannot duplicate.
- `rejectedCount`, `TransactionProvider.skippedMessageCount`, and `recheckSkippedMessages()` (clears, then rescans).
- Settings, Data and backup: "Recheck skipped messages" tile with count and a confirmation dialog.
- Logging: removed merchant and amount from two `debugPrint` lines in `transaction_provider.dart` and `gemini_service.dart` (they printed financial data). `sms_service.dart:66` logs only the exception.
- Retained per skipped message: the id only. No body, no reason.

### Not implemented (needs a storage-schema decision)

- Recording a rejection reason per message. The set is a JSON list of ids; per-id reasons need a new shape and a migration for existing lists. `debitSmsRejectionReason()` already yields codes (`CREDIT`, `OTP_SECURITY`, `NOT_COMPLETED`, `PROMO`, `BALANCE_ONLY`, `UNKNOWN`) that could be stored as `{id: code, at: date}`. I did not create that format.
- A per-message review list. Showing what was skipped needs either stored text (privacy cost) or re-reading the inbox. The current recheck re-reads the inbox, so no text is retained.
- Retention. Current behavior: the set is capped at 5000; when exceeded, the oldest 1000 are dropped silently. Proposed policy for approval: store `{id, code, firstSeen}`, expire after 90 days, drop on `clearAll`, never store text.
- Parser-version stamping so a parser upgrade auto-rechecks (needs the same schema).

Tests: `test/rejected_sms_test.dart` (8 tests): clearAll forgets skipped ids across restart, clearRejected scope and count, no-op on empty, no duplicate after recheck and retry, saved ids still block, skipped still permanent without a recheck, only ids persisted, nothing sensitive printed. Mutation check (clearAll keeps skipped ids) fails 1 test.

Not verified: the end-to-end recheck needs the SMS permission and platform channel, so `recheckSkippedMessages()` and the Settings tile have no test and no device run.

## F1/F2. Period correctness

No behavior was changed. The product rule is not established, so I added a shared
boundary helper and characterization tests only.

### Added

- `lib/utils/period_math.dart`: `dateOnly`, `addDays` (calendar arithmetic, immune to daylight-saving shifts that `Duration(days: n)` causes on a local date), `containsLocalDate` (local date, start day inclusive, end day inclusive, time of day ignored).
- `period_provider.dart` `previousPeriod` and `activity_screen.dart` `_isWithinRange` now use it. Results are identical outside daylight-saving zones.
- `test/period_contract_test.dart` (27 tests): helper boundaries; ten pinned current ranges (names start `CURRENT:`); a sweep of every day from 2026-01-01 to 2028-12-31 showing the current period contains today, the previous period is contiguous with it, and start is before end (no violations); a test that `setSalaryDay(25)` does not change `currentPeriod`.

### Current behavior pinned (not endorsed)

| Today | Period start | Period end |
| --- | --- | --- |
| 2026-10-12 | 2026-09-30 | 2026-10-30 |
| 2026-10-31 | 2026-10-31 | 2026-11-29 |
| 2027-02-28 | 2027-02-28 | 2027-03-30 |
| 2028-02-29 | 2028-02-29 | 2028-03-30 |
| 2026-01-15 | 2025-12-31 | 2026-01-30 |

### Findings still open (decisions needed, nothing changed)

1. `salaryDay` is stored and shown but never used. The preview in `salary_day_prompt.dart:171` calls `salaryAlignedPeriod()` without the selected day.
2. Definitions in use today:
   - Salary cycle: Home "Total spent this cycle", cycle pill, Home budget card.
   - Calendar month: Insights ("This cycle" heading, month-over-month text), budget notifications (`totalExpenses`), AI answers, Activity "This Month", default SMS scan start.
   - All time: Home "Spending by category", Cards, Recurring.
   - Rolling 7 days: Home bar chart.
3. Remaining daylight-saving-unsafe `Duration(days:)` arithmetic: `transaction_provider.dart:105`, `home_screen.dart:1044`, `activity_screen.dart:45`, `ai_service.dart:35`. `transaction_provider.dart` was not touched for this; changing them needs the rule first.

Decisions: (a) what salary day N means (period starts on day N; short-month clamping); (b) which screens follow the cycle versus the calendar month; (c) whether the budget is per cycle or per calendar month; (d) timezone: use device local time, or fix IST.

## S2. Ledger protection design (design only)

### Actual risk

- Live store: `TransactionCacheService` over SharedPreferences, one JSON string per transaction (`tx_<id>`) plus index keys, in the app's private data directory.
- It holds full `TransactionModel` JSON: amount, merchant, category, date, bank, `account`, `reference`, and the full raw SMS body (`originalSms`).
- Not encrypted by this app. Android's app sandbox and file-based device encryption protect it from other apps and from a locked device. They do not protect it from root, a forensic image of an unlocked device, a malicious component running as the app's UID, or a debuggable build.
- `allowBackup=false` and empty extraction rules remove cloud/transfer copies (verified in the manifest).
- Copies elsewhere: the Export dialog puts the full ledger, including `originalSms`, on the system clipboard (`settings_screen.dart:530`).
- Profile name, email and photo are also plaintext in SharedPreferences.
- Dead stores `CacheService` and `DatabaseService` are unimported but define unencrypted schemas.
- `originalSms` has exactly one UI read: the "Original SMS" panel in `transaction_details_screen.dart:244`. `account` and `reference` are exported but never displayed.

### What is not available

- `shared_preferences` has no encryption. `crypto` (already a dependency) provides hashing, not ciphers.
- No cipher or SQLCipher package is declared. Any real encryption needs a new dependency, so it is blocked on your approval.
- `flutter_secure_storage` 9.2.4 (resolved) uses `encryptedSharedPreferences: true` and `resetOnError: false` (the default, confirmed in the package source). `SecureStorageService` swallows every error, so a Keystore failure returns null. A ledger key must not use that wrapper unchanged: a null read would look like "no key" and a new key would orphan the data.

### Proposed strategy (not started)

1. Reduce first, no new dependency: stop persisting `originalSms` after parsing (keep a hash and the extracted fields), strip it from export, change the details panel to "source message not stored". Decision needed: this changes a visible feature and the export format.
2. Replace the clipboard export with a user-initiated file save; make a decision on where it is stored.
3. Encrypt the container. Options, each needs a new dependency: (a) authenticated encryption (AES-256-GCM) of each record with a random data key held in `flutter_secure_storage`; (b) an encrypted SQLite store. Preference: (a), smaller change and keeps the current key layout.
4. Migration, reusing the journal mechanism that now exists in the import path:
   - add a reader that understands both plaintext and encrypted records, before any writer exists;
   - write encrypted copies under a new namespace and verify each by decrypt-and-compare;
   - switch the visible index in one write, keep the plaintext copy for a retention window, then remove it in a separate, approved release;
   - never generate a new key if encrypted data exists; if the key is unreadable, fail closed and keep the app read-only with an export prompt;
   - require a user-initiated recovery export (file, not clipboard) before the first encrypted write.
5. Tests required before enabling: open an existing plaintext store with no loss; interrupt at every write; key-unavailable path; downgrade attempt; on-disk scan proving no merchant or SMS text remains in the encrypted namespace.

### Blockers and decisions

- Approval to add one cryptography dependency (or accept the reduce-only step).
- Product decision on `originalSms` removal and the export format.
- Interaction with the paise migration: do the container change first so field semantics change once.
- Downgrade policy: an older build cannot read the encrypted namespace.
- The live ledger was not touched: nothing was deleted, encrypted or migrated.
