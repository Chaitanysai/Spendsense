# Security validation phase 4 — encrypted ledger, device fault injection, release readiness

**Date:** 2026-10-24 (IST) · **Source:** working tree on `chore/cleanup-root-files` @ `33166cb` + uncommitted changes · **App:** 2.0.3+24 (debug, installed on OnePlus 7T HD1901, Android 16/API 36)

## Verdict: **PASS WITH BLOCKERS** (security validation passed; production remains NO-GO)

Everything executable in this phase passed: 512/512 automated tests (including 18 new
security tests), a demonstrated crash-recovery defect was found and fixed with
before/after evidence, and on-device fault injection (ciphertext tamper, key-material
corruption) confirmed fail-closed behaviour with byte-exact recovery. The blockers are
release-level, listed in §6 — the most important being that no release artifact contains
the current security-hardened source.

---

## 1. Baseline (Phase 1)

- Branch `chore/cleanup-root-files`, HEAD `33166cb`, all pre-existing uncommitted changes
  and untracked files preserved. `pubspec.yaml` stays at the approved `2.0.3+24`.
- Prior evidence reviewed: `docs/product-readiness/*` (gate/remediation reports),
  `build/development/evidence-20261024/RESULTS.md` (this morning's update-persistence run).
- Coverage mapping of the seven required security categories against the existing 23
  focused tests found gaps in: invalid key *values* (vs missing/unreadable),
  key-creation failure paths, MAC/nonce/envelope tamper variants, tampered index,
  import-journal version/phase handling, migration journals that over-report progress,
  interrupted activation at index commit, and re-init idempotency.

## 2. Automated security tests (Phase 2) — all PASS

New suite `test/encrypted_ledger_security_test.dart` (18 tests, isolated fixtures:
mock `SharedPreferences`, fake `LedgerKeyStore`s, `writeHook` fault injection):

| Group | Test | Result |
|---|---|---|
| key material | invalid base64 key value fails closed and preserves records | PASS |
| key material | wrong-length key fails closed and preserves records | PASS |
| key material | empty key value fails closed and preserves records | PASS |
| key material | createKeyIfMissing does not overwrite an existing key | PASS |
| key material | createKeyIfMissing surfaces key-store write failures | PASS |
| ciphertext tampering | single-byte ciphertext flip fails authentication | PASS |
| ciphertext tampering | replaced authentication tag fails decryption | PASS |
| ciphertext tampering | tampered nonce fails decryption | PASS |
| ciphertext tampering | envelope with non-string nonce is rejected | PASS |
| ciphertext tampering | tampered encrypted index fails closed and preserves payloads | PASS |
| ciphertext tampering | tampered record payload fails closed and preserves the ledger | PASS |
| import journal | malformed import journal fails closed | PASS |
| import journal | unsupported version fails closed | PASS |
| import journal | unsupported phase fails closed | PASS |
| interrupted migration | migration resumes from a journal that over-reports converted records | PASS |
| interrupted migration | plaintext reconciliation journal claims are revalidated | PASS |
| interrupted migration | interrupted activation at index commit is completed on restart | PASS |
| interrupted migration | repeated initialization is idempotent | PASS |

### 2.1 Defect found and fixed (the one production-code change)

`test/ledger_import_test.dart` (a pre-existing untracked suite, not part of the
validated 23) failed 5–6 tests per run before this phase. Diagnosis with a minimal
reproducer produced two findings:

1. **Production defect (demonstrated):** when a *replace* import crashed between the
   index commit and the committed-journal write, restart replayed the `pending`
   journal, committed the new index, but never removed the superseded payloads. The
   orphan then failed `_validateIndexConsistency` on every subsequent start —
   `LedgerMigrationException(index_inconsistent)` forever (fail-closed, no data loss,
   but the app could never initialize again).
   **Fix:** `_recoverJournal` now applies the journal's `remove` list after a
   recovered `pending` replace-commit, exactly as the `committed` path already did
   (`lib/services/transaction_cache_service.dart`, +4 lines, commented).
   Before: reproducer printed `restart threw: LedgerMigrationException(index_inconsistent)`;
   after: restart completes and the ledger loads. All 86 tests in the suite now pass.
2. **Test defect:** `_snapshot` masked `txe_*` values but not `tx_cache_ids_v2` /
   `tx_money_migration_v2` — encrypted envelopes whose nonces rotate on every write
   by design (fresh-nonce is itself a security requirement). Byte-idempotency
   assertions were impossible by construction. Fixed to mask all encrypted envelopes
   (test-only change).

A minor wart documented, not changed: a malformed *outer* import-journal envelope
surfaces as `FormatException` rather than `LedgerMigrationException`
(`_readJournal` decodes before validating). It still fails closed; the new test
accepts both and this should be normalised in a future cleanup.

## 3. Device validation (Phase 3) — OnePlus 7T, debug app 2.0.3+24

Device tests are **real on-device fault injection against the installed app's actual
encrypted ledger**, each guarded by hash-verified backups taken first (on-device
`sha256sum` matched host copies before any mutation; restore verified by hash after):

| # | Scenario | Result |
|---|---|---|
| D1 | Keystore integration inspection | PASS — ledger AES key is wrapped inside `FlutterSecureStorage.xml` under androidx-security keysets (`__androidx_security_crypto_*__`, Keystore-protected); no key material extracted or printed |
| D2 | Ledger persistence across restart and across the 2.0.3+23→+24 update | PASS — verified earlier today (see `RESULTS.md`): `PackageManager … Retain data and using new`, ₹239.50 visible after update, force-stop and relaunch |
| D3 | **Ciphertext tamper on device**: one base64 character of the live record's ciphertext flipped (`S→A`, same length) | PASS (fail closed) — app ran, init completed (`📦 Local DB init — 1 txs`), record load failed; **disk state byte-identical after the run** (tampered file hash unchanged; keys file unchanged) — nothing wiped, nothing re-encrypted |
| D4 | **Key-material corruption on device**: one character of the wrapped key entry value flipped in `FlutterSecureStorage.xml` | PASS (fail closed) — init did not complete; **no ledger wipe, no silent key replacement** (both file hashes unchanged after the run) |
| D5 | Byte-exact restore after D3 and D4, relaunch, UI verification | PASS — after each restore (hashes `7f3b5ea4…` / `274bf86c…` matched the originals), the synthetic ₹239.50 transaction reappeared on screen (OCR evidence: `tamper-A-restored.png`, `tamper-B-restored.png`) |

**Device UX finding (report, not fixed):** in both D3 and D4 the app showed its normal
empty dashboard ("Add or sync transactions to see spending") with no error state or
log line — the load/init failure is swallowed by the fire-and-forget
`TransactionProvider._initialization` future (`transaction_provider.dart:71`).
Data integrity is intact (fail-closed on disk), but a user with a corrupted ledger
sees what looks like an empty app rather than a diagnostic. Recommend an error banner
state in a future phase; not changed here (production change beyond the demonstrated
defect).

Not executable on device: deleting the actual Android Keystore master key (requires
root) — covered instead by the injectable-`LedgerKeyStore` unit tests (missing,
unreadable, invalid, empty). Instrumentation-test infrastructure
(`integration_test`) does not exist in this project; adding it was out of scope.

## 4. Release-readiness checks (Phase 4) — nothing deployed

| Check | Result |
|---|---|
| Release signing config | PASS — `build.gradle.kts` uses env/`key.properties` credentials, never falls back to the debug key, and fails release builds loudly when incomplete. `android/key.properties` exists with all four fields (field names only inspected; values never read) |
| Release artifact identity | PASS — `app-release.apk` (2026-10-22 19:08) is `com.example.spendsense` 2.0.3+23, signed by release cert SHA-256 `42c8f876…cb20d367` |
| Cert pinning | PASS — `UpdateConfig.pinnedSigningCertSha256` equals the release signer digest |
| OTA manifest consistency | PASS — `ota/public/manifest.json` `sha256` (`3248a573…`) equals both `app-release.apk` and the staged `ota/public/releases/spendsense-2.0.3+23.apk`; manifest `signingCertSha256` equals the pinned cert |
| Downgrade/rollback policy | PASS (code + tests) — `UpdatePolicy.decide` offers an update only when the manifest build is strictly newer; `minimumSupportedVersion` by name drives required vs optional; download verified by chunked SHA-256 with constant-time comparison; installer invoked only after verification. Covered by `update_manifest_test.dart` / `update_service_test.dart` (in the 512) |
| Release artifact freshness | **FAIL (blocker)** — the newest release artifact (2.0.3+23, 2026-10-22) predates all ledger-security work (integer paise, AES-256-GCM ledger, journals, recovery). No release-signed artifact of the current source exists |
| OTA manifest freshness | **BLOCKER** — manifest advertises 2.0.3+23; a future release of 2.0.3+24 must regenerate it (by design, `tool/generate_ota_manifest.dart`) |

## 5. Validation commands executed (with outcomes)

| Command | Outcome |
|---|---|
| `flutter test test/financial_integrity_fix_test.dart test/encrypted_ledger_migration_test.dart` | exit 0 — 23 passed |
| `flutter test test/encrypted_ledger_security_test.dart` | exit 0 — 18 passed |
| `flutter test` (full suite, all files) | exit 0 — **512 passed, 0 failed** |
| `flutter analyze` | exit 0 — no issues |
| `flutter build apk --debug` | exit 0 (artifact of the earlier phase; no new build needed this phase) |
| Device: `run-as` backup/restore with `sha256sum` verification | all hashes matched at every step |
| `keytool`/`aapt`/`apksigner` artifact inspection | as tabulated in §4 |

## 6. Blockers, manual interventions, and risks

1. **No release artifact contains the current source** (stale 2.0.3+23 release).
   Clearing requires an authorized release build with production credentials —
   explicit authorization needed; none performed here.
2. **OTA manifest must be regenerated** for any future version; currently consistent
   with the staged 2.0.3+23 only.
3. **Corrupted-ledger UX gap** (§3 finding): no user-visible error on ledger
   load/init failure. Data-safe; should be fixed before public release.
4. **Prior gate matrix items still NOT EXECUTED** (salary-cycle boundaries, budget
   notifications, SMS permission flows, full-resync on device, large-text/accessibility,
   offline startup — per `release-candidate-gate.md` §2.1–2.8). Untested is not failed,
   but they gate release.
5. Manual interventions available only to the device owner: none pending for the
   security validation itself (phone was unlocked by the owner before D3–D5; no lock,
   credential, or auth bypass was attempted at any point).
6. Device backups of the pre-test ledger remain in
   `build/development/evidence-20261024/device-*.bak` (hash-verified); the live ledger
   was restored and re-verified on screen at the end of testing.

## 7. Files changed in this phase

| File | Change | Why |
|---|---|---|
| `test/encrypted_ledger_security_test.dart` | new (18 tests) | fill mapped coverage gaps with isolated fixtures |
| `lib/services/transaction_cache_service.dart` | +4 lines in `_recoverJournal` | fix demonstrated orphan-payload crash loop after interrupted replace-import |
| `test/ledger_import_test.dart` | `_snapshot` masking (test-only) | mask all encrypted envelopes so idempotency assertions are possible |
| `docs/product-readiness/security-validation-phase-4.md` | new | this report |
| `build/development/evidence-20261024/*` (gitignored) | evidence artifacts | device screenshots/OCR, hash-verified backups, tamper scripts |

No commits, pushes, installs, uninstalls, data clears, key replacements, production
signing, OTA activation, or deployment occurred. `pubspec.yaml` remains at the
approved `2.0.3+24`; versionName was never changed.

**Production status: NO-GO** — unchanged, pending the blockers in §6.
