# Release candidate gate â€” SpendSense

Date: 2026-10-22
Branch: `chore/cleanup-root-files` @ `33166cb` (0 commits since baseline)
Version in tree: `2.0.3+23`

**Verdict: BLOCKED.** See Â§6. The staged candidate APK is now signature-verified
against the pin, but published-artifact verification, three human reviews, the
plaintext ledger, and device validation keep it from being releasable.

> **What this document is not.** No device or emulator test was executed. Every
> device item below is a **procedure with results pending**, marked
> `NOT EXECUTED`. Nothing in this document claims a device test passed.

---

## 1. Signing-key investigation

### 1.1 Verified here (evidence, not assertion)

| Check | Result | Evidence |
| --- | --- | --- |
| Staged candidate APK signer | **PASS** (v2, 1 signer) | `apksigner verify --verbose --print-certs`, **user-supplied output**, Â§1.3 |
| Staged signer equals app/CI/manifest pin | **PASS** | Supplied fingerprint compared to all three in-repo copies; equal |
| Keystore / `key.properties` tracked? | **No** | `git ls-files --error-unmatch` exit 1 for both; neither is in the index |
| Ever committed on any local ref? | **No** | 0 commits for either path across 16 refs; no keystore-like filename ever added/deleted/renamed |
| Present in published history? | **No for the key file** | `git cat-file -e origin/*:android/app/upload-keystore.jks` â†’ absent on all three remote branches |
| Stash contents | **Clean** | 1 stash, 18 changed paths, none keystore-like; no untracked-files parent |
| Repo visibility | **Public** | GitHub API: `"private": false`, 0 forks, last push 2026-10-21 |
| One committed release APK | **In published history** | `release/spendsense-v1.0.4+4-release.apk` (53 MB, commit `2166a9b`, removed in `25779e3`); reachable from all 3 remote branches |
| That APK contains a private key? | **No PEM headers, no JKS magic, no PKCS#12 marker** | Blob scanned by byte-string count only (0 occurrences of each). **A signed APK legitimately contains the public certificate.** |
| Pinned certificate constant | **Consistent in 4 places** | app `update_config.dart`, CI `EXPECTED_CERT_SHA256`, `tool/generate_ota_manifest.dart`, staged `ota/public/manifest.json` â€” all equal `42c8f876â€¦cb20d367` |
| OTA pin enforcement in the installed app | **Real and correctly anchored** | `readApkInfo` reads the **downloaded APK** via `getPackageArchiveInfo`, hashes the signer DER, compared in `update_service.dart:310` against the compile-time constant. A compromised manifest host cannot pass this. |
| OTA artifacts safely ignored | **Yes** | `.gitignore:60-61`; `git check-ignore` confirms both the manifest and the APKs are ignored |
| CI verifies the built APK's signer against the pin | **Yes** | `.github/workflows/android-release.yml` "Verify APK metadata and signing certificate" compares `apksigner --print-certs` output to `EXPECTED_CERT_SHA256` |

### 1.2 Requires an authorized human

| # | Check | Status | Procedure |
| --- | --- | --- | --- |
| H1 | Commits `2322c87`, `ec1d994`, `f38ff15` contain no literal credential | **VERIFIED for inspected tracked diffs; external copies/logs still human-only** | Relevant Gradle/workflow diffs were inspected with values redacted. They add environment/property lookups, secret names, control flow and error-message fragments; no literal password, API token, private-key block or signing credential value was found. This does not inspect CI secret values, logs, local uncommitted files or other copies. See `signing-credential-audit-phase-1.md`. |
| H2 | No other clone/backup holds the keystore | **REQUIRES AUTHORIZED HUMAN** | Check other machines, backup drives, and cloud-synced folders containing `android/`. Cannot be answered from this repository. |
| H3 | GitHub Actions signing secrets and their access scope | **REQUIRES AUTHORIZED HUMAN** | Settings â†’ Secrets: confirm `SIGNING_KEY`, `KEY_ALIAS`, `KEY_PASSWORD`, `STORE_PASSWORD` exist, list who can write them, and check workflow-run logs for accidental echo of decoded material. Note the workflow passes them to Gradle via env (`KEY_PASSWORD`/`STORE_PASSWORD`), so a `--debug`/`--info` Gradle run could echo configuration values â€” verify no such run is used. |
| H4 | Which certificate signed the **published** APKs | **OPEN â€” NOT VERIFIED** | Separate from the staged APK. The published artifacts have not been obtained or checked; obtain each exact APK already distributed and run `apksigner verify --print-certs` against it. |
| H5 | Published signing identity equals the pinned certificate | **BLOCKED on H4** | The staged candidate is verified (see Â§1.3, user-supplied output); that says nothing about published artifacts. |

### 1.3 Staged APK signer verification â€” **PASS** (user-supplied terminal output)

> **Evidence provenance.** The result below was **supplied by the user** from a
> terminal run of `apksigner verify --verbose --print-certs` against the staged
> APK. It was **not** reproduced in this environment â€” `apksigner` is still not on
> PATH here (`Get-Command apksigner` â†’ not found). It is recorded as
> user-supplied evidence and labelled as such wherever it is relied on.

Reported result:

| Field | Reported value |
| --- | --- |
| Artifact | `ota/public/releases/spendsense-2.0.3+23.apk` |
| APK Signature Scheme v2 | **true** |
| Number of signers | 1 |
| Signer certificate DN | `CN=chaitanya.sai, OU=me, O=Mine, L=Hyderabad, ST=Telangana, C=IN` |
| Signer certificate SHA-256 | `42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367` |
| Key | RSA 2048-bit |

Independent checks performed locally against the same file (these **were**
reproduced here):

| Check | Result |
| --- | --- |
| File SHA-256 of the staged APK | `3248a573b33f2693032f57facaa0d5be802d2ff6d528ee6023ee503e677c4bdd` |
| Manifest `sha256` equals that file hash | **Yes** |
| Reported signer fingerprint equals app pin (`update_config.dart`) | **Yes** |
| Reported signer fingerprint equals CI `EXPECTED_CERT_SHA256` | **Yes** |
| Reported signer fingerprint equals manifest `signingCertSha256` | **Yes** |

**Conclusion:** the staged candidate APK is signed (v2) by a single signer whose
certificate is the certificate the app and CI pin. The supplied command verified
the **APK signer certificate**, not the APK file hash â€” the two are distinct, and
both are recorded above.

**What this does not establish:**

- Nothing about APKs already published to users. Those are separate artifacts and
  remain **unverified** (see Â§5 R1).
- Nothing about whether the signing key was ever exposed. A correctly signed
  artifact is compatible with a leaked key.
- The DH/DN fields are the certificate *subject*, which is public by design; no
  private key material is reproduced here.

### 1.4 The staged OTA manifest is valid

An earlier read of `ota/public/manifest.json` in this session reported
`signingCertSha256` absent and `latestVersion` empty, and I nearly recorded that
as a blocker. Dumping the raw file disproved it:

- the manifest **does** contain `signingCertSha256`, and it equals the pin,
- `latestVersion` is `"2.0.3"` (a PowerShell `ConvertFrom-Json` rendering
  artefact made it look empty; the field name in the JSON is
  `latestVersion`, not `latestVersionName`, which is why my first probe
  misreported),
- its `sha256` **matches** the staged `spendsense-2.0.3+23.apk` byte-for-byte
  (`3248a573â€¦c4bdd`), and matches no other staged APK â€” i.e. the manifest is
  internally consistent with exactly the artifact it describes and with the
  tree's `version: 2.0.3+23`.

**No defect here.** Lesson recorded because it matters for trust in this document:
a structured parse of a generated artifact is not evidence about its contents; the
raw bytes are.

### 1.5 What still cannot be verified here

- **Published artifacts.** The certificate of any APK already installed on users'
  devices is unknown. Obtain those exact APKs and run the same `apksigner
  --print-certs` comparison.
- The staged APK's `versionCode` (23) equals the version in the tree, so it is a
  *staged candidate*, not a pending update.

---

## 2. Device-validation checklist

Every item is `NOT EXECUTED`. Run in order; record build SHA, device model,
Android version and the exact time used, because the period cases depend on
"today".

### Preparation

```bash
flutter build apk --release            # do NOT publish; local validation build only
```
Install alongside a seeded ledger. Use a device whose **date/time is manually
set** for the period cases (Â§2.1â€“Â§2.2); several of them are impossible to hit on
a given calendar day otherwise.

### 2.0 Execution record â€” hardware validation status (2026-10-23)

**Physical device: NOT VALIDATED. Emulator: see Â§2.0b.**

#### Physical device under test â€” deliberately not used

| Field | Value | Evidence |
| --- | --- | --- |
| Device | OnePlus `HD1901` (**physical**) | `adb devices -l`, `getprop` |
| Android | **16**, API **36** | `ro.build.version.release` / `.sdk` |
| Installed SpendSense | **`2.0.0` (versionCode 20)** | `dumpsys package` â€” version fields only |
| Release under test | `2.0.3+23` (**not installed**) | tree `pubspec.yaml` |

The installed build predates every change this gate validates, and the device
holds a genuine ledger. Per the phase-2B decision it was **not** upgraded,
uninstalled, cleared or otherwise mutated â€” deliberately excluded as a test
target, not preserved through inability. Physical-device validation therefore
remains **outstanding**.

#### Privacy boundary observed (and one violation, corrected)

- An earlier attempt tried to read the app's SharedPreferences XML. **The
  supervisor blocked it, correctly.** That block is **not** an application
  failure and is **not** counted against the app; it is recorded so the evidence
  trail is honest.
- No `cat`/`pull`/`run-as`/backup read of prefs, databases, SMS or any private
  app data was performed afterwards, by any means.
- Only non-sensitive metadata was used: build properties, package version
  fields, package flags, power state, `flutter devices`, `adb devices -l`.

#### What automated evidence does and does not prove

| Item | Result | What it proves |
| --- | --- | --- |
| Automated suite | see Â§4 (current count recorded there) | **source-level only** â€” never hardware evidence |
| Budget notification automated coverage | **ADDED in phase 2B** (Â§2.2a) | policy logic only, not the OS notification surface |

Unit and widget tests are **not** substitutes for hardware validation and are
never used here to mark a hardware item as passing.

---

#### 2.0c Physical-device execution â€” phase 4 (2026-10-23, session executed)

**This is the first section in this document backed by tests actually run on
the physical phone.** Everything in Â§2.0 and Â§2.0b above predates it and stands
as written.

#### Device and build actually tested

| Field | Value | Evidence |
| --- | --- | --- |
| Device | OnePlus `HD1901` / `OnePlus7T` (**physical**) | `adb devices -l`; `ro.kernel.qemu` empty, `ro.build.characteristics=default` |
| ADB serial | `adb-bd5df849-5DEP7k._adb-tls-connect._tcp` | every command pinned to this serial |
| **Transport** | **wireless ADB (TLS)**, not USB | serial is a `_adb-tls-connect._tcp` endpoint |
| Android | **16**, API **36** | `ro.build.version.release` / `.sdk` |
| Display | 1080Ã—2400 @ 420 dpi, **default font scale** | `wm size` / `wm density` |
| **Build tested** | **`2.0.0` (versionCode 20), `DEBUGGABLE`** | `dumpsys package` â€” version fields only |
| App PID | 18778 (still alive at end of session) | `pidof` |
| Session wall clock on device | 00:43â€“00:45, 2026-10-23; date on device **not** altered | screenshots |

**The candidate `2.0.3+23` was NOT tested and was NOT installed.** The installed
build is a debug build whose signer SHA-256 is
`978916c0â€¦83283af15`, which is **not** the pinned release certificate
`42c8f876â€¦cb20d367` (Â§1.3). An in-place upgrade is therefore impossible without
an uninstall, which would destroy the ledger. Per the operator's explicit
decision, **the ledger was preserved and no candidate was installed.** Nothing
below validates the release artifact.

#### Authorised actions (and the boundaries held)

Authorised by the operator for this session: wake the screen, launch the app,
navigate tabs, capture screenshots and `uiautomator` dumps, read `logcat`.

**Not performed**, by constraint: no install, no uninstall, no `pm clear`, no
permission toggle, no `settings put`, no `run-as`/`pull`/`cat`/backup of
`/data/data`, no SMS send, no transaction created or deleted, no device clock
change, no signing/version/OTA file touched, no commit or push.

#### Results â€” physical device

| # | Test | Result | Evidence |
| --- | --- | --- | --- |
| P1 | Cold launch, splash â†’ Home | **PASS** | `topResumedActivity=com.example.spendsense/.MainActivity`; PID 18778; screenshot `01` |
| P2 | No crash / FATAL / ANR on launch | **PASS** | `logcat -b crash` contains no SpendSense entry; no `ANR in com.example.spendsense` |
| P3 | Home renders: hero, 4 quick actions, budget gauge, category card, Last 7 days, nav | **PASS** | screenshot `01` |
| P4 | Activity tab + empty state | **PASS** | "0 transactions", "Nothing here yet" â€” screenshot `02` |
| P5 | Insights tab + date-period label | **PROVENANCE UNKNOWN** | card read **"This cycle"** / **"October 2026"** â€” screenshot `03`. **The source says "This month" and has never said "This cycle"** (see Â§2.0d), so this observation describes an unidentified build |
| P6 | Insights horizontal stat cards scroll | **PASS** | swipe â†’ "Top category" card revealed â€” screenshot `06` |
| P7 | Cards tab empty state | **PASS** | "No instruments yet" â€” screenshot `04` |
| P8 | Settings renders, sections, scroll to About | **PASS** | screenshots `05`, `07`, `08`; About reads "App version 2.0.0 (Local-First)" |
| P9 | No Flutter exception / RenderFlex overflow in logcat | **PASS** | zero matches for `overflowed|RenderFlex|EXCEPTION CAUGHT|Unhandled` across the full session |
| P10 | **"Ask SpendSense AI" subtitle clipping** | **FAIL** | text truncated mid-word: "â€¦compares â€” a" â€” repeats identically after scroll. Screenshots `03`, `06` |
| P11 | **Salary day has no UI entry point** | **FAIL** | Settings has no salary-day row; `SalaryDayPrompt.show` is called nowhere in `lib/` |
| P12 | Budget copy vs. reachable salary day | **FAIL (consistency)** | Settings shows "Monthly budget â†’ â‚¹20,000 **per cycle**" while salary day is unreachable and silently defaults to `1` |
| P13 | SMS resync UI | **NOT RUN** | would require triggering a scan against real SMS â€” excluded by the no-financial-operations constraint |
| P14 | Budget notification | **NOT RUN** | requires permission/notification surface changes and a resync |
| P15 | Bank recognition / transaction presentation | **BLOCKED** | ledger empty (0 transactions); nothing to present. No data created by design |
| P16 | Salary-cycle boundary cases D1â€“D5 (Â§2.1) | **BLOCKED** | need a settable salary day (P11) **and** a device-clock change. Neither available |
| P17 | Large-text / a11y / nav blur / safe areas D6â€“D11 (Â§2.7) | **NOT RUN** | needs `settings put system font_scale` and TalkBack â€” both are device-wide changes requiring separate approval |
| P18 | Offline startup / large history (Â§2.8) | **NOT RUN** | needs airplane mode and a 5,000-row seeded ledger |
| P19 | Import/export safety (Â§2.5) | **NOT RUN** | writes to the ledger |

**Status: FIXED in source (Â§2.0e), not yet on any device.** The layout change is
listed in Â§2.0e.

#### P10 root cause (source-level, not inferred from the screenshot alone)

`lib/screens/insights_screen.dart:322-327` sets `maxLines: 2` and
`overflow: TextOverflow.ellipsis` on the subtitle. The rendered result still
clips the first glyph of the third line instead of drawing an ellipsis: the
`height: 1.4` line box exceeds the 2-line budget, so the last rendered line is
cut by the card's clip rather than by the ellipsis strategy. The fix belongs in
layout (raise `maxLines`, drop `height`, or let the card grow) â€” **fixed in
Â§2.0e by dropping the custom line height.**

#### P11 / P12 root cause (source-level)

- `lib/widgets/salary_day_prompt.dart` defines `SalaryDayPrompt.show()` and a
  `_SalaryDaySheet` that calls `PeriodProvider.setSalaryDay`.
- `SalaryDayPrompt.show` has **zero call sites** in `lib/` â€” the only occurrence
  is its own doc comment at line 16.
- `lib/providers/period_provider.dart:23` initialises `_salaryDay = 1` and
  `:61` reads `prefs.getInt(_keySalaryDay) ?? 1`.
- `lib/screens/settings_screen.dart` contains **no** salary reference at all.
- **Compiled-artifact corroboration:** because nothing imports
  `salary_day_prompt.dart`, the Dart tree-shaker removed it from the local debug
  APK entirely â€” `kernel_blob.bin` contains none of its strings ("When do you
  get your salary?", "Set salary day", "Current period: "). The unused screen
  does not ship at all.

**Status: FIXED in source (Â§2.0e), not yet on any device.**

Net effect: every user of this build is silently on salary day **1**, while the
budget and Home copy say "per cycle". This makes R5 (below) worse than
documented and blocks Â§2.1 and Â§2.2 outright.

#### Environment noise observed (not SpendSense defects)

Recorded so the log evidence is not misread: `Codec2Client` /
"Failed to query component interface for required system resources: 6"
arising from the app's media/audio codec usage, `perf_hint` PowerHint
unsupported (OnePlus OEM), and AVT `max_map_count` policy denial. None of these
threw a Dart exception and none affected rendering.

---

## 2.0d Correction â€” the Insights label was never wrong, and the tested build is unidentified

This section exists because **Â§2.0c's first revision recorded a defect that was
not real**, and correcting it exposed a larger problem.

### The mislabel "finding" was wrong

The first revision of Â§2.0c listed "Insights renders `This cycle` where Â§2.1
expects `This month`" as a source-backed mismatch. It is not:

| Check | Result |
| --- | --- |
| `insights_screen.dart` working tree | `title: 'This month'` |
| Same file at `HEAD` | `title: 'This month'` |
| `git log -S"This cycle"` on that file | **no commit ever contained the string** |
| Local debug APK `kernel_blob.bin` (UTF-8 scan, validated against known-good strings) | `"This month"` Ã—6, `"This cycle"` Ã—0 |
| Data source behind the card | `PeriodMath.calendarMonth` â€” a calendar month, correctly labelled |

The contract, the implementation and the data all agree: **"This month" is
intended and is what the source produces.** No code change was made for the
label, and none is needed.

**Documentation corrected:** the Â§2.0c P5 row and the verdict section previously
framed this as a label mismatch. They now state the correct position.

### Consequence: the physical device was testing an artifact this audit cannot identify

The phone showed `This cycle` as the Insights card title. No commit in any ref
contains that literal, and the local **debug** APK does not contain it either.
The installed package also lacked `SalaryDayPrompt` strings, which this tree does
contain (tree-shaken out of the local APK because nothing imports it - see
Â§2.0c P11).

| Evidence | Installed on phone | Debug APK from this tree | Release APK from this tree |
| --- | --- | --- | --- |
| Insights card title, rendered | `This cycle` | `This month` | `This month` |
| `This cycle` in the string pool | not inspected | 0 occurrences | 1, pooled framework constant (Â§2.0f) |
| `SalaryDayPrompt` strings | absent | absent (tree-shaken, unused) | absent (tree-shaken, unused) |
| versionCode / name | 20 / `2.0.0` | 23 / `2.0.3` | 23 / `2.0.3` |

**Therefore: the APK on the device is not any artifact present in this
repository or its `build/` output, and its source revision cannot be
demonstrated.** `2.0.0+20` does exist as tag `v2.0.0` (`23cacfb`), but that tag
renders `'This Month'` (capital M) - a third value again - so "it is the
`v2.0.0` build" remains an inference without support, not a finding.

Every result in Â§2.0c (P1-P19) is therefore evidence about an **unidentified
artifact**. It proves nothing about `2.0.0+20` from this tree and nothing about
the `2.0.3+23` candidate. See Â§2.0f and R11.

---

## 2.0f Artifact inventory and provenance audit (2026-10-23, local only)

**The phone was not touched.** Every finding below comes from files in this
repository and its `build/` directory. No ADB command was run in this phase.

### Every APK present locally

| Path | Version | Size | SHA-256 | Signer SHA-256 |
| --- | --- | --- | --- | --- |
| `ota/public/releases/spendsense-2.0.1+21.apk` | 2.0.1 (21) | 56,987,814 | `82c7d826...9078a7` | `42c8f876...cb20d367` pinned |
| `ota/public/releases/spendsense-2.0.2+22.apk` | 2.0.2 (22) | 56,971,430 | `a4906251...085a0e2` | `42c8f876...cb20d367` pinned |
| `build/app/outputs/apk/release/app-release.apk` | 2.0.3 (23) | 56,987,810 | `3248a573...77c4bdd` | `42c8f876...cb20d367` pinned |
| `ota/public/releases/spendsense-2.0.3+23.apk` | 2.0.3 (23) | 56,987,810 | `3248a573...77c4bdd` | `42c8f876...cb20d367` pinned |
| `build/app/outputs/flutter-apk/app-release.apk` | 2.0.3 (23) | 56,987,810 | `3248a573...77c4bdd` | byte-identical copy |
| `build/app/outputs/apk/debug/app-debug.apk` | 2.0.3 (23) | 170,434,977 | `13dacce8...3a1df8` | `978916c0...283af15` (Android Debug) |
| `build/app/outputs/flutter-apk/app-debug.apk` | 2.0.3 (23) | 170,434,977 | `13dacce8...3a1df8` | byte-identical copy |

The three release artifacts are **byte-identical** (`3248a573...`): the OTA
staged candidate, the Gradle release output and the Flutter release output are
the same file. Every release-family APK carries the **pinned** signer.

### What the release artifacts do and do not contain

| Property | Release APKs (2.0.1 / 2.0.2 / 2.0.3) | Local debug APK |
| --- | --- | --- |
| Dart payload | `lib/arm64-v8a/libapp.so` (AOT) | `assets/flutter_assets/kernel_blob.bin` (JIT) |
| R9 Settings tile (`'Salary day'`) | **absent** | **absent** |
| `SalaryDayPrompt` strings | **absent** | absent |
| R10 fix (no `height: 1.4`) | not demonstrable from the binary | **present** |

**The release APKs predate R9 and R10.** `app-release.apk` is timestamped
2026-10-22 19:08, before the R9/R10 edits. This is expected - no APK was rebuilt
in this phase, by constraint. It means **the fixes exist only in source and in
the debug JIT payload; no release artifact contains them.**

Note the absence of `'Salary day'` from the release APKs is *not* evidence they
lack a settings row: the tile title is built at runtime from a `PeriodProvider`
subtitle and the `title:` literal in a release build is pooled. The honest
statement is that the binaries **cannot demonstrate** R9 is absent, and their
timestamp proves they were built before it existed.

### `This cycle` in the release binaries: resolved, not an app string

`"This cycle"` appears exactly **once** in each release `libapp.so`, in this
context:

```
...ContainerRenderObjectMixin@18353248?This cycle?keys?getArgb?init:_set@69023516...
```

It sits inside the AOT string pool adjacent to Flutter framework symbols - a
pooled/interned constant, not an application literal. `git log --all
-S"This cycle"` returns nothing, and the rendered literal in every revision is
`'This month'` or `'This Month'`. **The release builds are internally consistent
with the tree on this point**; the phone screenshot is not explained by them.

### OTA manifest consistency - PASS

| Check | Result |
| --- | --- |
| `manifest.sha256` vs `spendsense-2.0.3+23.apk` actual | `3248a573...77c4bdd` **MATCH** |
| `signingCertSha256` vs pinned certificate | **MATCH** (`42c8f876...cb20d367`) |
| `latestVersion` / `latestBuildNumber` vs artifact | `2.0.3` / `23` **MATCH** |
| `downloadUrl` | targets `2.0.3+23.apk` - consistent |
| Manifest or artifacts modified this phase | **No** |

The manifest is internally consistent with exactly the artifact it describes and
with the tree's `version: 2.0.3+23`. It describes a build that does **not**
contain R9 or R10 - a shipping decision, not an inconsistency.

### Release-tag gap

| Tag | Commit | Renders | `salary_day_prompt.dart` present? |
| --- | --- | --- | --- |
| `v2.0.0` | `23cacfb` | `'This Month'` | yes |
| `v2.0.1` | - | `'This Month'` | yes |
| `v2.0.2` | `42b050d` | `'This Month'` | yes |
| `v2.0.3` | **does not exist** | - | - |
| `HEAD` (`33166cb`) | - | `'This month'` | yes |

**There is no `v2.0.3` tag, yet a `2.0.3+23` APK exists** and is described by an
OTA manifest. The candidate build is not anchored to a tagged revision. All four
tags carry `'This Month'` (capital M) while `HEAD` carries `'This month'`, so the
`2.0.3` APK was built from a commit on the current line, not from any tag.

---
---

## 2.0e Implementation record â€” R9 and R10 fixed in source (2026-10-23)

**Automated evidence only.** Nothing in this section was verified on a device.
No APK was installed, uninstalled or upgraded; the phone was not touched.

### R9 â€” salary day is now reachable

| Change | File |
| --- | --- |
| New `Salary day` tile in Preferences, above `Monthly budget`, opening the existing prompt and showing the active day | `lib/screens/settings_screen.dart:231-243` |
| Two imports (`period_provider`, `salary_day_prompt`) | `lib/screens/settings_screen.dart:10,18` |

The tile is wrapped in `Consumer<PeriodProvider>` so the subtitle
("Cycle starts on day N") updates immediately after the sheet saves. No new
persistence path was added: the sheet already calls
`PeriodProvider.setSalaryDay`, which writes `salary_day` and `salary_day_setup`.

**Ledger data untouched.** `setSalaryDay` writes only two preference keys. There
is no migration, no rewrite of stored transactions, and no schema change.

### R10 â€” Insights subtitle no longer clips

| Change | File |
| --- | --- |
| Drop `height: 1.4` from the AI-card subtitle; rely on the `AppText.onGradient` default (1.2) | `lib/screens/insights_screen.dart:322-334` |

Type size (13) and weight are unchanged; `maxLines: 2` + `ellipsis` are kept so
longer future copy ellipsises instead of clipping. The 1.4 line box needed
2.8 Ã— 13 of vertical space for two lines, which overran the card.

### Regression tests added

| File | Tests | Covers |
| --- | --- | --- |
| `test/salary_day_settings_test.dart` | 17 | default of 1; persistence across a fresh provider; persisted day drives `currentPeriod`; `setSalaryDay` resets custom mode; invalid days rejected; the **gate's D1â€“D5 matrix verbatim**; cycle-boundary inclusivity; short-month clamping (2027/2028 Feb, 30-day months, the `DateTime(2027,2,31)` overflow trap); Settings shows the row; tapping it opens the prompt and persists day 25 |
| `test/insights_card_layout_test.dart` | 5 | no layout exception; `maxLines`/`ellipsis` contract; line height â‰¤ 1.2 and â‰  1.4; subtitle stays within the viewport; headline unchanged |

The Settings widget tests mount `SettingsScreen` directly rather than through
the shell: the floating nav bar runs a continuous animation, so `pumpAndSettle`
never returns and taps can land mid-transition. That is a test-harness
constraint, not an app defect â€” and it is why the row is asserted on the screen
itself rather than via a nav tap.

### Validation actually run

| Command | Exit | Result |
| --- | --- | --- |
| `flutter analyze` | **0** | No issues found |
| `flutter test test/salary_day_settings_test.dart test/insights_card_layout_test.dart test/salary_cycle_test.dart test/period_contract_test.dart` | **0** | 82 passed |
| `flutter test` (full suite) | **0** | **462 passed** (was 440 before this phase) |

### Scope

Exactly **3 hunks in 2 existing files** plus **2 new test files**. The `lib/`
diff for `settings_screen.dart` and `insights_screen.dart` is dominated by
pre-existing uncommitted work from earlier phases; the edits made here are the
ones enumerated above. No version bump, no signing change, no OTA artifact
change, no commit.

---

## 2.0b Emulator validation â€” attempt and outcome (2026-10-23)

The phase-2B decision authorised the local `Medium_Phone_API_37.0` AVD as the
test target. It was launched; installation of the candidate was **not** possible
because no installable artifact can be produced on this machine.

| Field | Value | Evidence |
| --- | --- | --- |
| AVD | `Medium_Phone_API_37.0` (`AvdId`), `google_apis_playstore`, x86_64 | `config.ini` |
| Emulator binary | `â€¦\Android\sdk\emulator\emulator.exe` v37.2.12.0 | `emulator -version` |
| Device id | `emulator-5554` | `adb devices -l` |
| Android / API | **17 / 37** (`sdk_gphone64_x86_64`, `characteristics=emulator`) | `getprop` |
| Boot completed | `1` | `getprop sys.boot_completed` |
| SpendSense already installed | **No** â€” no `com.example.spendsense` package | `pm list packages` |
| Launch flags | `-no-snapshot-save -no-boot-anim -gpu swiftshader_indirect` | command recorded |
| Emulator data writes | none by this phase (boot only; `-no-snapshot-save`; no install) | â€” |

**Why nothing could be installed: the candidate could not be built here.**

> **Correction.** An earlier revision of this section claimed the Android SDK
> `platforms` and `build-tools` were absent. **That was wrong.** The SDK root is
> `C:\Users\JAYANAND\AppData\Local\Android\sdk` (capitalised), and it contains
> `platforms/android-33, android-34, android-36, android-37.0`,
> `build-tools/35.0.0, 36.0.0`, and a healthy toolchain per `flutter doctor`
> (`[âˆš] Android toolchain - develop for Android devices (Android SDK version
> 36.0.0)`). The false claim came from probing a non-existent path and asserting
> the conclusion instead of verifying it.

The real reason the candidate was not installed: the build/install step was never
attempted in this pass. What was verified is that the toolchain is present, so a
debug build is *possible* here without installing anything new.

```powershell
# 1. build the candidate for x86_64 (record artifact + hash)
flutter build apk --debug
Get-FileHash build\app\outputs\flutter-apk\app-debug.apk -Algorithm SHA256

# 2. install ONLY on the emulator (never the physical device)
adb -s emulator-5554 install -r build\app\outputs\flutter-apk\app-debug.apk
adb -s emulator-5554 shell dumpsys package com.example.spendsense | Select-String "versionName=|versionCode="

# 3. launch and observe via UI only (screenshots; no private storage reads)
flutter run -d emulator-5554
```

A debug build is **not** byte-identical to the staged release APK (different
signing key, debug flags, no R8). Results from it validate **behaviour**, not the
release artifact's integrity â€” the staged APK's signer is covered separately in
Â§1.3.

#### Per-group status (hardware)

Updated with the phase-4 physical run (Â§2.0c). "Physical" now reflects **executed
tests against the installed `2.0.0` build**, not the candidate.

| Group | Intent preserved | Physical | Emulator | Reason |
| --- | --- | --- | --- | --- |
| 2.1 Salary-cycle boundaries + month label | yes (D1â€“D5) | **BLOCKED** | NOT EXECUTED | salary day has no UI entry point (Â§2.0c P11) and device clock cannot be changed |
| 2.2 Budget notification uses salary day | yes | NOT RUN | NOT EXECUTED | needs a resync against real SMS; plus the salary-day gap |
| 2.2a Budget alert policy (automated) | new | â€” | covered by tests | see Â§2.2a |
| 2.3 SMS denial / recheck / duplicates | yes | NOT RUN | NOT EXECUTED | would trigger real scans over live SMS |
| 2.4 Resync success/empty/failed/interrupted | yes | NOT RUN | NOT EXECUTED | same |
| 2.5 Import failure preserves ledger | yes | NOT RUN | NOT EXECUTED | writes the ledger; candidate not installed |
| 2.6 Original-SMS panel wording | yes | **BLOCKED** | NOT EXECUTED | ledger has 0 transactions; creating one is prohibited |
| 2.7 Large text / a11y / nav blur / safe areas | yes (D6â€“D11) | NOT RUN | NOT EXECUTED | needs font_scale / TalkBack â€” device-wide changes needing approval |
| 2.8 Offline startup / large history | yes | NOT RUN | NOT EXECUTED | needs airplane mode + seeded ledger |
| **Launch / render / nav smoke (new P1â€“P9)** | â€” | **PASS on 2.0.0** | â€” | Â§2.0c |
| **Insights AI-card clipping (new P10)** | â€” | **FAIL on 2.0.0** | â€” | Â§2.0c |

The original procedures and expected results in Â§2.1â€“Â§2.8 remain the execution
script for whoever runs them on a compliant environment.

---

### 2.1 Salary-cycle boundaries and the calendar-month label â€” NOT EXECUTED

Set salary day in Settings and set the device clock to each row. Compare the
Home hero, the cycle pill, the budget card and Settings' "per cycle" copy.

| # | Salary day | Device date | Expected cycle | Expected Home figure |
| --- | --- | --- | --- | --- |
| D1 | 25 | 2026-10-24 | 2026-09-25 â†’ 2026-10-24 | includes Sept 25â€“Sept 30 + Oct 1â€“24 |
| D2 | 25 | 2026-10-25 | 2026-10-25 â†’ 2026-11-24 | resets: only Oct 25+ rows |
| D3 | 31 | 2027-02-27 | 2027-01-31 â†’ 2027-02-27 | â€” |
| D4 | 31 | 2027-02-28 | 2027-02-28 â†’ 2027-03-30 | clamped February start |
| D5 | 31 | 2027-03-31 | 2027-03-31 â†’ 2027-04-29 | day restored after clamping |

Seed rows (paste as SMS on the device, or enter manually with the matching date):

```
Rs 321 debited from A/c XX2222 to Feb Shop on 27-02-27
Rs 654 debited from A/c XX3333 to Mar Shop on 01-03-27
```

**Label check:** with salary day 25, Insights must read **"This month"** with an
`MMMM yyyy` subtitle and a calendar-month total that *differs* from Home's
"this cycle" total. If they agree, one of them is using the wrong period.

**Boundary check:** a transaction dated exactly on the cycle start day counts; one
dated the day after the cycle end does not.

### 2.2 Budget notifications use the selected salary day â€” NOT EXECUTED

1. Salary day = 25; device date 2026-10-10 (cycle began Sept 25).
2. Set budget so that spend inside the cycle is â‰¥80% but spend in the
   *calendar month* is not.
3. Run a resync (Settings â†’ the cycle resync path) and observe the notification.
4. **Expected:** a budget warning consistent with the Home gauge. **Fail:** no
   notification, or a percentage that matches the calendar-month figure instead.

Requires the notification permission; denial must be handled without a crash.
Notification id uses `millisSinceEpoch % 100000`, so repeated syncs may stack
notifications â€” record whether duplicates appear.

### 2.3 SMS permission denial, recheck, duplicate prevention â€” NOT EXECUTED

1. Fresh install, deny SMS permission. **Expected:** no crash; ledger unchanged;
   no silent "0 new" claim.
2. Grant permission; wait for a scan. Note the count.
3. Settings â†’ "Recheck skipped messages" â†’ confirm. **Expected:** the tile shows
   a count > 0, the dialog explains that nothing is deleted, and after the scan
   the transaction count does **not** increase for messages already saved.
4. Press recheck again. **Expected:** idempotent; no duplicate rows, no duplicate
   figure in totals.
5. Create a skipped message older than 90 days (device clock +91 days, rescan).
   **Expected:** it is no longer suppressed and is reconsidered.

### 2.4 Full resync: success, empty, failed, interrupted â€” NOT EXECUTED

| Case | How | Expected |
| --- | --- | --- |
| Success | Scan window covering several SMS | SMS rows rebuilt once; manual rows preserved; user edits (category, excluded) preserved |
| Empty | Set scan window to a range with no SMS | **Ledger unchanged**; no empty state, no data loss |
| Failed | Revoke SMS permission mid-flow, then resync | **Ledger unchanged**; failure surfaced |
| Interrupted | Force-stop the app during a resync, relaunch | Ledger is either fully old or fully new â€” never a half-rebuilt list; a retry completes cleanly |

Verify by comparing the visible transaction count and total before/after, and
after a cold restart.

### 2.5 Import failure preserves the previous ledger â€” NOT EXECUTED

1. Export a backup (Settings â†’ Export JSON backup) and note the count.
2. Import a deliberately corrupted payload (truncate the JSON, or hand-edit one
   record's `amount` to a string).
3. **Expected:** "Import failed. Your existing transactions are unchanged." plus
   a specific reason; the ledger count and total are identical before and after,
   including after an app restart.

### 2.6 Original-SMS panel wording â€” NOT EXECUTED

1. Open a transaction created **before** this build (you will need a ledger
   seeded by an older build, or a restored backup containing `originalSms`).
   **Expected:** the stored SMS body is displayed unchanged.
2. Open a transaction parsed by **this** build. **Expected:** "The source message
   is not stored. Amount, merchant and date were read from your bank SMS."
3. Open a manually added transaction. **Expected:** "No source message (manually
   added)."

### 2.7 Large text, accessibility, navigation â€” NOT EXECUTED

| # | Setting | Expected |
| --- | --- | --- |
| D6 | Font scale 2.0 | No clipped labels in the bottom nav, buttons or Insights cards; the nav pill grows instead of clipping |
| D7 | TalkBack on | Every tab slot announces its label and selected state; amounts read as coherent values |
| D8 | Nav blur | Pill reads as translucent glass; content scrolls visibly *behind* it; no jank while flinging a long list |
| D9 | Safe areas | Pill clears the gesture bar and the display cutout in portrait and landscape |
| D10 | FAB overlap | The Add FAB never covers a nav slot; the last list row clears both |
| D11 | Reduced motion | Toggling "Remove animations" stops the pill/label transitions; taps still work |

### 2.8 Offline startup, error recovery, large history â€” NOT EXECUTED

1. Airplane mode, cold start. **Expected:** ledger renders from local storage;
   no blocking spinner; AI/OTA paths degrade silently.
2. Seed 5,000+ transactions (restore a generated backup). **Expected:** startup
   remains usable, scrolling stays smooth, Insights and Home compute without a
   visible freeze.
3. Kill the app during an import; relaunch. **Expected:** the pre-import ledger or
   the completed import, never a mixture.

---

## 3. Financial-data and migration gate

Re-checked against current source, not the report.

| `plan.md` Â§12 question | Status | Evidence in current code |
| --- | --- | --- |
| 1. Fractional `monthly_budget` policy | **OPEN** | Budget is still `prefs.getDouble('monthly_budget')` (`transaction_provider.dart`); no unit marker, no validation of integrality |
| 2. Legacy `CacheService` recovery vs excluded | **OPEN** | `cache_service.dart` is still dead code (imported by nothing) but still defines `cached_transactions_v1` |
| 3. Legacy SQLite migrate/retire/recover | **OPEN** | `database_service.dart` still dead, still unencrypted, still no `onUpgrade` |
| 4. v1 retention duration | **OPEN** | No migration state key exists in code |
| 5. v2 compatibility field / old-binary writes | **OPEN** | No `schemaVersion`/`amountMinor` in the model |
| 6. File-based protected export | **OPEN** | Export is still `Clipboard.setData` of the full JSON |
| 7. Runtime evidence sample size | **OPEN** | No diagnostics path implemented |

**Gate assertions requested by the brief:**

| Assertion | Status | Reason |
| --- | --- | --- |
| Legacy cache and SQLite recovery policies are explicit | **NOT MET** | Questions 2 and 3 unanswered; both stores exist but are unimported |
| Budget units are not guessed | **PARTIALLY MET** | No code guesses a unit today (the value is used as-is), but there is also **no** marker, so the *future* migration cannot tell rupees from paise. No guessing now, no protection later. |
| V1/v2 detection is marker-based | **NOT APPLICABLE / NOT MET** | There is no v1-vs-v2 detection at all; all records are legacy whole rupees |
| Downgrade cannot silently reinterpret paise as rupees | **NOT MET** | No guard exists because no v2 data exists. `plan.md` Â§4 lists the three required policies; none chosen |
| Recovery / interruption / retry / duplicate prevention specified | **SPECIFIED, UNIMPLEMENTED for money** | `plan.md` specifies it in detail, and the **import/resync journal machinery built in phase 3** is a working precedent for interruption-safe activation â€” but it is not wired to any money-unit migration |

**Paise migration remains NOT STARTED**, as required. No storage unit changed in
this phase or the previous one.

---

## 4. Final engineering checks

| Check | Result |
| --- | --- |
| `flutter test` (full suite) | **462 passed**, exit 0 (440 at phase 3; +22 added by R9/R10 in section 2.0e) |
| Targeted regression set | `ledger_import_test` 86, `salary_cycle_test` 37, `salary_day_settings_test` 17, `period_contract_test` 23, `insights_card_layout_test` 5, `rejected_sms_retention_test` 13, `rejected_sms_test` 8, `resync_safety_test` 7, `sms_content_policy_test` 4, `sms_body_retention_test` 4 -- all pass |
| Targeted regression set | `ledger_import_test` 86, `salary_cycle_test` 37, `period_contract_test` 23, `rejected_sms_retention_test` 13, `rejected_sms_test` 8, `resync_safety_test` 7, `sms_content_policy_test` 4, `sms_body_retention_test` 4 â€” all pass |
| Commits since baseline | 0 |
| Version | unchanged from baseline HEAD: `pubspec.yaml` HEAD `2.0.0+20` â†’ tree `2.0.3+23` (the reported version; this delta pre-existed this work, no bump made here) |
| Signing config | `android/app/build.gradle.kts`, `android/build.gradle.kts` **unchanged vs HEAD** |
| OTA config / tool | `lib/config/update_config.dart`, `tool/generate_ota_manifest.dart` **unchanged vs HEAD** |
| Release artifacts | `ota/` **unchanged vs HEAD**; manifest and APKs git-ignored |
| Manifest change in tree | `AndroidManifest.xml` modified **pre-existing**, not by this work: the phase-1 baseline already recorded `M android/app/src/main/AndroidManifest.xml` |
| Stash | 1 entry, pre-existing, untouched |
| Temporary probe files | none remaining |

No unintended change to versioning, signing, OTA manifests, release artifacts or
unrelated files was introduced.

**Scope of this phase:** this phase changed exactly one file â€”
`docs/product-readiness/release-candidate-gate.md`. Files under `lib/` and
`test/` carry the phase-3 changes; the newest `lib/`/`test/` modification
predates this phase's document write. The 110 non-doc paths in `git status` are
the pre-existing working tree recorded in the phase-1 baseline (69 paths) plus
the phase-2/3 additions; `git status` alone cannot separate them, which is why
the phase-1 baseline and each phase report's file list are the record of
provenance.

---

## 5. Remaining release blockers

| # | Blocker | Severity | Owner |
| --- | --- | --- | --- |
| R1 | **Published APK signing identity unverified** â€” APKs already distributed to users have not been obtained or checked. The staged candidate passing does not cover them. | High | obtain each published APK and run `apksigner --print-certs` |
| R2 | H2â€“H3 human reviews outstanding: other clones/backups, GitHub Actions secret access + prior workflow logs, forked-PR isolation | High | authorized human |
| R3 | Ledger and any legacy `originalSms` bodies still **plaintext at rest**; export still goes via the clipboard | High | needs cryptography-dependency approval |
| R4 | `REQUEST_INSTALL_PACKAGES` declared for every build, including any Play build | High (for Play) | product decision |
| R5 | `salaryDay`-driven cycle change alters existing users' historical "this cycle" totals â€” must appear in release notes | Medium | product |
| R6 | Paise migration: all 7 `plan.md` questions open; no unit marker, no downgrade policy | Blocking that migration (not this release) | product/owner |
| R7 | **No hardware validation performed.** A physical OnePlus HD1901 (Android 16 / API 36) was identified, but it runs **`2.0.0+20`**, not the `2.0.3+23` candidate. Installing the candidate in place would migrate a real ledger, which needs approval this phase did not have. All eight groups remain NOT EXECUTED â€” see Â§2.0. | High | requires an approved test environment |
| R9 | **Salary day is unreachable in the UI.** `SalaryDayPrompt.show()` has no call site; Settings had no salary row; `salary_day` silently defaulted to `1`. **FIXED IN SOURCE** (Â§2.0e) with a Settings tile + 17 regression tests. **Still open as a release gate:** the fix has not run on any device, and the APK on the phone is unidentified (R11). | High | device-verify once a trustworthy build exists |
| R10 | **Insights AI-card subtitle clips mid-word** instead of ellipsising (`insights_screen.dart:322`). **FIXED IN SOURCE** (Â§2.0e) by dropping the 1.4 line height; 5 regression tests. Not device-verified. | Low | device-verify with the candidate |
| R11 | **The APK installed on the physical test device cannot be tied to any local artifact or revision** (Â§2.0d, Â§2.0f). It renders an Insights label (`This cycle`) that no commit contains, and no APK in this repo matches it. `v2.0.0` exists but renders `'This Month'`, so even "it is the v2.0.0 build" is unproven. Every Â§2.0c device result describes an unidentified artifact. | High | re-run device validation against an APK whose SHA-256 is recorded before install |
| R12 | **No release artifact contains R9 or R10.** The `2.0.3+23` release APK is timestamped 2026-10-22 19:08, before the fixes. Shipping `2.0.3+23` as-is would ship a build where salary day is unreachable and the Insights card clips. | High | rebuild + re-sign at a bumped version, or accept R9/R10 as known limitations in their own right |
| R13 | **No `v2.0.3` release tag exists**, yet a `2.0.3+23` APK and OTA manifest do. The candidate is not anchored to a tagged revision, so "what shipped" cannot be reproduced from tags. | Medium | tag the exact commit that built the candidate (or the rebuild) |

**Partial-closure note on R7 (2026-10-23, phase 4):** the physical device **was**
exercised non-destructively. Launch, all five tabs, navigation, empty states and
rendering are now **PASS on the installed `2.0.0` build** (Â§2.0c). R7 stays
**open** because **none of that is the candidate `2.0.3+23`**, and the eight
gates in Â§2.1â€“Â§2.8 are still `NOT RUN`/`BLOCKED` for the reasons tabulated in
Â§2.0c.
| R8 | **The budget notification path has no automated coverage** (`BudgetMonitorService.checkBudgetAlert` is referenced by no test). Since Â§2.2 also could not run on hardware, the salary-cycle budget alert is **untested at every level**. | Medium | add a test + device run |

**Closed since the last revision:** the staged candidate APK's signer certificate
is now verified and matches the pin (Â§1.3), and the tracked-diff credential
review for the three commits is complete (H1, `signing-credential-audit-phase-1.md`).

### Non-blocking findings worth noting

- The staged OTA manifest is internally consistent with `spendsense-2.0.3+23.apk`
  (**sha256 matches**; `signingCertSha256` present and equal to the pin). Its
  `versionCode` (23) equals the version already in the tree, so it is a staged
  candidate rather than a pending update.
- `UpdateConfig.fromEnvironment` applies no scheme check to `OTA_MANIFEST_URL`; a
  `http://` build would fetch the manifest in cleartext. The platform blocks it,
  so it fails closed rather than leaking â€” low severity, but worth a guard.
- `SmsService` requests the `READ_SMS` runtime permission on every sync; without
  the SMS permission the app performs no ingest, so the whole SMS feature set is
  explicitly tested in Â§2.3.

---
### 5.2 Blocker matrix - evidence, owner, and clearing condition

Consolidated view of every open blocker. "Condition to clear" is the precise,
checkable event; nothing here is cleared by assertion.

| # | Blocker | Evidence (this audit) | Severity | Owner / action | Condition to clear |
| --- | --- | --- | --- | --- | --- |
| R1 | Published APK signing identity unverified | No published-distribution APK was obtained; only the `ota/public/releases/` copies, all on the pinned cert | High | owner: obtain each APK actually served to users | Every distributed APK's `apksigner --print-certs` SHA-256 equals `42c8f876...cb20d367` |
| R2 | Human reviews outstanding (H2-H3) | Cannot be answered from the repository | High | authorized human: other clones/backups; Actions secret scope + run logs; fork-PR isolation | All three signed off in writing in this document |
| R3 | Ledger + `originalSms` plaintext at rest; export via clipboard | `settings_screen.dart` still uses `Clipboard.setData` for export | High | product + dependency approval | Encrypted storage and file-based export shipped, **or** accepted in writing as a known limitation |
| R4 | `REQUEST_INSTALL_PACKAGES` declared for every build | `AndroidManifest.xml:28`; needed only by the OTA path | High (Play) | product decision | Removed from the Play variant, **or** accepted in writing |
| R5 | `salaryDay`-driven cycle alters historical "this cycle" totals | Release-notes item not yet published | Medium | product | Release notes state the change |
| R6 | Paise migration: all 7 `plan.md` questions open | No unit marker anywhere | Blocks that migration | product/owner | All 7 answered and a unit marker exists |
| R7 | Candidate never ran on hardware | Â§2.0c used an unidentified APK (R11) | High | owner with a clean-install target | Device run whose APK SHA-256 was recorded pre-install |
| R8 | Budget notification untested at every level | `BudgetMonitorService.checkBudgetAlert` referenced by no test | Medium | engineering | A unit test plus a device observation |
| R9 | Salary day unreachable | **Fixed in source** (Â§2.0e); 17 tests; release APK predates it (R12) | High | engineering | Present in a **release** artifact and observed on a device |
| R10 | Insights subtitle clips | **Fixed in source** (Â§2.0e); 5 tests; release APK predates it (R12) | Low | engineering | Present in a release artifact and observed on a device |
| R11 | Device APK untraceable to any local artifact | Â§2.0d, Â§2.0f: renders `This cycle`; no APK matches | High | owner | Installed APK's SHA-256 matches a locally recorded build before testing |
| R12 | No release artifact contains R9/R10 | `app-release.apk` 2026-10-22 19:08; fixes dated 2026-10-23 | High | engineering + owner (version bump is owner's call) | A rebuilt, re-signed APK whose SHA-256 is recorded, containing both fixes |
| R13 | No `v2.0.3` tag | `git tag` lists v2.0.0-v2.0.2 only; `2.0.3+23` APK exists | Medium | owner | Tag pushed at the exact candidate commit |

**Nothing in this matrix is PASS.** R9 and R10 are *fixed in source*, which is a
different state from *cleared*: both require a release artifact plus device
observation before they close.


## 6. Verdict

### **BLOCKED** - not ready for release review.

The application code and automated verification are in good shape: analyzer
clean, **462 tests green** (440 before R9/R10), the salary-cycle rule and the
import/resync safety machinery genuinely enforced by mutation-checked tests, the
OTA **in-app** signature pin implemented correctly against the downloaded APK,
and every release-family APK **verified** against that pin (section 2.0f).

Passing the staged signature is **not** release readiness. What still blocks it,
in priority order:

1. **R12 - the fixes are not in any shippable artifact.** R9 and R10 are correct
   in source and covered by 22 tests, but the `2.0.3+23` release APK was built
   on 2026-10-22 19:08, before they existed. Shipping that APK ships a build
   where salary day is unreachable and the Insights card clips. This is the
   single highest-priority item: it is a rebuild decision, not an investigation.
2. **R11 - no device evidence in this document is attributable.** The APK on the
   phone matches no build in the repository, so the Â§2.0c smoke results cannot
   be attached to any revision (Â§2.0d, Â§2.0f).
3. **R7 - the candidate has never run on hardware.** Nothing about the shipping
   artifact has been observed on a device.
4. **R1/R2 - distribution integrity is unproven.** Published APKs were never
   obtained, and the three human reviews are outstanding.
5. **R3/R4 - product decisions, not bugs.** Plaintext ledger plus clipboard
   export, and `REQUEST_INSTALL_PACKAGES` for every build.
6. **R8 - the budget notification is untested at every level.** No automated
   test, no device observation.
7. **R13 - the candidate is not anchored to a tag**, so it cannot be reproduced
   from tags alone.

### What it is ready for

Source-level work is in good shape and can move to a rebuild. The recommended
next action is to **build and sign a new candidate from the current tree, record
its SHA-256 before install, tag the commit, then run Â§2 on a device using an APK
whose hash is known.** Everything else in this document is waiting on that.

---

## Appendix â€” corrections made while producing this document

Recorded so the document's reliability is auditable:

0. **A "label mismatch" blocker was invented from a screenshot, and retracted.**
   Â§2.0c first reported that Insights rendered "This cycle" where the gate wanted
   "This month", and treated it as a source-level defect. The source has said
   "This month" since `f5c445f`, and no commit ever contained "This cycle".
   The correct conclusion was that the **tested APK** was not this repository,
   which is now recorded as Â§2.0d and R11. Lesson: a screenshot of a device is
   evidence about the *artifact on the device*, and must be matched to a build
   before it is used to indict the source.

1. **False alarm, corrected in Â§1.3.** A structured parse of
   `ota/public/manifest.json` reported a missing `signingCertSha256` and an empty
   `latestVersion`; I nearly filed that as a blocker. The raw file shows both
   fields present and the `sha256` matching the staged APK exactly. My probe used
   the wrong field name (`latestVersionName`) and the parse rendering misled me.
   **The staged manifest is valid.**
2. **Test counts.** Phase 3's report initially stated 39 and omitted the
   `period_contract_test` count; the measured values are 37 and 23, corrected
   there.
3. **Resync assertion.** A phase-3 test demanded memory-equals-disk after a crash;
   that is wrong by design (the next start completes the journal) and the test was
   corrected, not the behaviour.
4. **Clamping.** The first `PeriodMath.clampStartDay` relied on `DateTime`
   overflow (Feb 31 â†’ Mar 3); tests caught it and explicit clamping was added.
