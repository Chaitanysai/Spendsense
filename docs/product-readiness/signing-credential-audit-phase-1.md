# Signing security and credential audit — Phase 1

Date: 2026-10-22
Project: SpendSense
Branch: `chore/cleanup-root-files`
HEAD: `33166cb062690c2c4ffa7e520b7a1071c4ddbe93`

## Scope and safety

- Read-only audit. No source, signing configuration, workflow, version, OTA
  artifact or application behavior was changed.
- No commit, push, deploy, upload, branch switch, reset, clean, stash or history
  rewrite was performed.
- No private-key, password, token, signing secret or credential value was read
  into output or copied into this report.
- Files inspected were inside the project repository only.

## A. Baseline

| Item | Evidence / result |
| --- | --- |
| Branch / HEAD | `chore/cleanup-root-files` / `33166cb` |
| Working tree | Existing modified and untracked paths preserved; see phase-1 baseline. |
| Existing stash | One pre-existing stash (`stash@{0}`); not modified. |
| App version | `pubspec.yaml:4` → `2.0.3+23` |
| Current release-gate verdict before this audit | `docs/product-readiness/release-candidate-gate.md` → `BLOCKED` |
| Certificate pin locations | `lib/config/update_config.dart:18`, `tool/generate_ota_manifest.dart:21`, `.github/workflows/android-release.yml:210`, `ota/public/manifest.json:13`; values intentionally redacted here. |
| Pin consistency | The four values compare equal. The values are public certificate fingerprints, but are omitted from this report. |

## B. Three suspicious commits

### `2322c87f402fc441ac54a8c560b5adf35298693f`

Subject: `ci: require release signing secrets and harden release workflow`

Files changed: `.github/workflows/android-release.yml`,
`android/app/build.gradle.kts`.

Relevant changes:

- Added environment/property lookups for the alias, key password, store
  password and keystore path.
- Added completeness checks for the password fields and keystore existence.
- Changed the release signing configuration from an unconditional local path to
  a fail-closed configuration.
- Added failure messages describing missing release credentials.

**Classification: credential value ruled out from the inspected diff.** The
added values are environment-variable names, properties-map keys, identifiers,
and error-message fragments. No literal password, API token, private-key block,
or signing credential value was added by the relevant changes.

Historical status: the commit remains in Git history, but the inspected
credential-bearing values are references and control flow, not secret values.
Current status: current `android/app/build.gradle.kts` still uses environment or
`key.properties` lookups; no literal value was found in the current file.

### `ec1d994d422e16c136a0efabfc0befad57b4cdb2`

Subject: `feat(ui): integrate glossy UI, bundled sound and motion work`

Files changed: UI, sound, tests, generated plugin files, `pubspec`, and
`android/app/build.gradle.kts`.

Relevant signing changes in the Gradle file are the same environment/property
lookup and fail-closed signing block introduced by `2322c87`.

**Classification: credential value ruled out from the inspected diff.** No
literal password, API token, private-key block, or signing credential value was
added by the relevant changes. The commit's other additions were not treated as
signing credentials merely because the commit touched many files.

Historical status: the commit remains in Git history; no secret value was
confirmed in the relevant Gradle changes. Current status: current Gradle uses
lookups, not literals.

### `f38ff15324de2b4c9f41ed66956dbcf4fa83db4d`

Subject: `ci: Configure cloud Android builds and verify APK artifact`

Files changed: new `.github/workflows/android-release.yml`,
`README.md`, and `android/app/build.gradle.kts`.

Relevant changes:

- Introduced `key.properties` as a local fallback file.
- Read alias/password/store-password values from environment variables or the
  properties file.
- Added the first cloud build workflow and secret references.

**Classification: credential value ruled out from the inspected diff.** No
literal password, API token, private-key block, or signing credential value was
added by the relevant changes. The values are references to environment or
properties lookups.

Historical status: the commit remains in Git history; no literal secret was
confirmed in the relevant changes. Current status: no credential-like file is
tracked.

### History-wide path check

- `git ls-files` found no tracked `key.properties`, `.jks`, `.keystore`, `.p12`,
  `.pfx` or `.pem` file.
- `git log --all --name-only --diff-filter=ADR` found no such credential-like
  path ever added, deleted or renamed.
- The current working-tree keystore and `key.properties` exist locally but are
  ignored; their contents were not read.
- Exact label history counts: `storePassword` and `keyPassword` each occur in 3
  commits; workflow secret labels occur in the expected workflow history. Label
  presence is not evidence of a secret value.

### Remaining uncertainty

The three commit reviews are based on the relevant textual diffs and context.
They do not prove that a value was never present in a developer's local
uncommitted file, CI secret, log, artifact, backup, or another clone. The
repository is public, so any credential found in an external copy must be
contained by an authorized human; do not rotate or rewrite history automatically.

## C. Staged APK signer verification

### Artifact and independent file hash

| Field | Result |
| --- | --- |
| APK | `ota/public/releases/spendsense-2.0.3+23.apk` |
| Size | 56,987,810 bytes |
| APK SHA-256 | `3248a573b33f2693032f57facaa0d5be802d2ff6d528ee6023ee503e677c4bdd` |
| Manifest file SHA-256 | **Matches** the APK hash above |
| Manifest signing certificate field | Present, 64 hex characters |
| App/CI/manifest pin equality | **Equal** (fingerprint values omitted) |

### Tool availability

`apksigner` was not on PATH during this audit. `ANDROID_HOME` and
`ANDROID_SDK_ROOT` were unset, and no project-local SDK/build-tools directory was
present. No executable was installed or downloaded.

**Update (2026-10-23): verification supplied by the user.** The user ran
`apksigner verify --verbose --print-certs` against this APK and supplied the
output. It is recorded as **user-supplied terminal output**, not reproduced in
this environment:

| Field | Reported |
| --- | --- |
| APK Signature Scheme v2 | true |
| Number of signers | 1 |
| Signer certificate DN | `CN=chaitanya.sai, OU=me, O=Mine, L=Hyderabad, ST=Telangana, C=IN` |
| Signer certificate SHA-256 | `42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367` |
| Key | RSA 2048-bit |

**Staged APK signer certificate comparison: PASS** (user-supplied evidence). I
re-checked locally that the file has not changed since the audit
(SHA-256 `3248a573…c4bdd`, matching the manifest) and that the supplied
fingerprint equals the app pin, the CI `EXPECTED_CERT_SHA256`, and the manifest
`signingCertSha256` — all equal.

The command verified the **APK signer certificate**, not the APK file hash; both
are recorded separately and are consistent.

**Still open:** published APKs. This result covers the staged candidate only.

The CI equivalent already exists in
`.github/workflows/android-release.yml:182-212`: it uses the runner SDK's
`apksigner verify --print-certs` and compares the signer certificate to the
pinned fingerprint.

## D. Repository and local exposure

Verified within the approved repository scope:

- Neither `android/app/upload-keystore.jks` nor `android/key.properties` is
  tracked.
- Neither path appears in any local Git ref history.
- No credential-like file path was ever added/deleted/renamed in local refs.
- The one existing stash contains no credential-like path name.
- The local files exist and are ignored by `android/.gitignore`; contents were
  not read.

Not verified and intentionally not searched:

- Other clones, developer backups, cloud-sync folders, removable media,
  GitHub Actions secret values, workflow logs, or APKs already installed on
  users' devices.
- No claim is made that those external locations are clean.

## E. GitHub Actions human-review checklist

Workflow inspected: `.github/workflows/android-release.yml`.

### Secret references (verified from repository text)

The workflow references these secret **names**:

- `SIGNING_KEY` — base64-decoded into the temporary
  `android/app/upload-keystore.jks` at the runner.
- `KEY_ALIAS` — Gradle environment input.
- `KEY_PASSWORD` — Gradle environment input.
- `STORE_PASSWORD` — Gradle environment input.

The workflow sets `set +x` around keystore preparation and uses least-privilege
`contents: read` permissions. It runs on pushes to a named feature branch/tags
and manual dispatch; it does not use `pull_request_target` and does not publish
an APK or deploy OTA in the inspected workflow.

### Human-only checks

- Confirm repository Actions secrets are protected and scoped correctly; do not
  paste values into issues or logs.
- Confirm who can modify workflow files and who can approve/tag/manual-dispatch
  release runs.
- Confirm whether branch protection or environment approvals are required for
  release publication outside this workflow.
- Confirm forked pull requests cannot read signing secrets. The workflow does
  not trigger on `pull_request`, but repository policy still needs checking.
- Confirm Actions logs from prior runs contain no secret echo. The workflow
  avoids `set -x` during keystore preparation; review logs without exporting or
  copying secret values.
- Confirm the base64 `SIGNING_KEY` secret is stored as a protected secret and
  not as a repository variable or committed file.
- Confirm release credentials are rotated if any external copy, CI log, or
  untrusted runner exposure is found. No rotation was performed here.
- Confirm any production OTA deployment requires a separate explicit approval;
  this workflow currently builds/uploads artifacts but does not itself publish.

## F. Release-gate result

The gate remains **BLOCKED**, though **one item is now closed**: the staged
candidate APK's signer certificate is verified (user-supplied `apksigner` output)
and matches the pin, and the tracked-diff credential review for the three commits
is complete.

Still blocking release, unchanged:

1. **Published APKs unverified** — the staged candidate is not what users already
   run; obtain and check those exact artifacts.
2. **Human reviews outstanding** — other clones/backups, GitHub Actions secret
   access and prior workflow logs, forked-PR isolation.
3. **Existing phase-4 blockers** — plaintext ledger and legacy raw SMS at rest,
   no device validation, `REQUEST_INSTALL_PACKAGES` review, and the open
   migration decisions in `plan.md`.

A passing staged signature shows the artifact is signed by the right certificate.
It does not show that the key was never exposed, and it does not substitute for
published-artifact verification.

## Commands executed and outcomes

- `git branch --show-current` / `git rev-parse HEAD` — exit 0.
- `git status --short` — exit 0; pre-existing changes preserved.
- `git stash list` — exit 0; one stash listed, not modified.
- `git ls-files --error-unmatch` for both signing paths — exit 1 each; neither tracked.
- `git log --all` path/name checks — exit 0; no credential-like paths found.
- Redacted `git show` reviews for all three commits — exit 0; no literal secret
  confirmed in relevant diffs.
- `Get-FileHash -Algorithm SHA256` on staged APK — exit 0; matches manifest.
- `Get-Command apksigner` and approved SDK-root checks — no tool found; no install attempted.
- Workflow structure/secret-name inspection — exit 0; names only, no values.

### 2026-10-23 update

- `apksigner verify --verbose --print-certs` on the staged APK — **run by the
  user, not in this environment**; output supplied and recorded above.
- Re-checked the staged file hash before recording the result: unchanged
  (`3248a573…c4bdd`, matches manifest), so the supplied signer result refers to
  this exact artifact.

No application code was changed in this phase; only the two product-readiness
documents were updated, and the release verdict was **not** advanced.
