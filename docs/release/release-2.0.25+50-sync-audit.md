# Release 2.0.25+50 — GitHub, Downloads & Documentation Sync Audit

**Phase:** 1 — read-only repository audit
**Date:** 2026-11-11
**Audited ref:** `origin/release/2.0.13+38` @ `ccd1618de70942d109cd9ce82b6fcb185de3b2da`
**Method:** `git archive` snapshot of the release branch (599 files) — no working tree modified.

> **Status of this document.** Sections 0–3 record the Phase 1 audit **as found** and
> are deliberately left unedited, so the original state stays on the record. Every
> finding's resolution, and the Phase 4 re-validation performed after the fixes, are
> in [§8 Resolution log](#8-resolution-log-phase-2-4) at the end. Read §8 for current
> state.

---

## 0. Verified production values

Every value below was independently confirmed against the live artefacts, not taken on trust.

| Value | Claimed | Verified | How |
|---|---|---|---|
| Version name | `2.0.25` | ✅ `2.0.25` | `aapt2 dump badging` on the live APK |
| Version code | `50` | ✅ `50` | `aapt2 dump badging` |
| Application ID | `com.example.spendsense` | ✅ `com.example.spendsense` | `aapt2 dump badging` |
| APK SHA-256 | `3c56d47d…90551` | ✅ exact match | `sha256sum` of a full 65 373 753-byte GET |
| Signing cert SHA-256 | `42c8f876…d367` | ✅ exact match | `apksigner verify --print-certs` |
| Live manifest | — | ✅ agrees on all values | `GET /manifest.json` |
| OTA URL | `https://spendsense-ota-2026.web.app` | ✅ serves 200 | HTTP GET |

Live `manifest.json` (unmodified, authoritative):

```json
{
  "schemaVersion": 1,
  "appId": "com.example.spendsense",
  "latestVersion": "2.0.25",
  "latestBuildNumber": 50,
  "minimumSupportedVersion": "2.0.24",
  "downloadUrl": "https://spendsense-ota-2026.web.app/releases/spendsense-2.0.25+50.apk",
  "releaseNotes": ["2.0.25+50 - Opus 5.5 redesign"],
  "sha256": "3c56d47d9634d8075c8405a2cf7ea2a5704df3a4090d6a6c44527d5432e90551",
  "signingCertSha256": "42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367",
  "publishedAt": "2026-11-11T13:05:53.466121Z"
}
```

The published values are internally consistent. **The OTA channel itself is correct** — the defects below are all in the *GitHub Releases face* and in *user-facing documentation*, not in the app's update mechanism.

---

## 1. Repository structure (relevant parts)

The git repository root is `app/` (not `E:\Projects\Spendsense`). Remote: `Chaitanysai/Spendsense`.

```
README.md                      root install + docs index         ← has defects
PRODUCT.md, DESIGN.md          product/design notes              ← clean
docs/OTA_UPDATES.md            OTA trust model                   ← clean, version-agnostic
docs/hosting-cache-headers.md  cache-policy measurement record   ← historical, see F-7
ota/README.md                  hosting layout + download link    ← clean
site/README.md                 landing-page build topology       ← clean
backend/assistant_proxy/README.md  assistant proxy               ← clean
ota/public/404.html            user-facing download fallback     ← has defect
site/src/components/Footer.tsx download button source             ← clean
lib/config/update_config.dart  pinned cert + app id               ← clean, matches live
```

---

## 2. Findings

Severity: **P0** = user gets wrong/old build or dead end · **P1** = contradictory/incorrect release info · **P2** = cosmetic/stale-but-harmless.

### F-1 — P0 — README install instructions point at a 12-build-old release

- **File:** `README.md` (lines 40–48)
- **Current content:**
  > ## Install
  > Android 7.0 or newer.
  > 1. Open the [latest release](https://github.com/Chaitanysai/Spendsense/releases/latest).
  > 2. Download the `.apk`.
- **Reality:** `https://github.com/Chaitanysai/Spendsense/releases/latest` returns **HTTP 302 → `/releases/tag/v2.0.13+38`**. The newest GitHub release is **2.0.13+38**; production OTA is **2.0.25+50**. A user following the README installs a build **12 versions behind**, and one whose `minimumSupportedVersion` (2.0.24) is *above* it — so the app it installs is immediately below the support floor.
- **Required correction:** Make the OTA URL the primary install path (`https://spendsense-ota-2026.web.app`), which is verified live and always serves the current build. Keep a GitHub Releases mention only as a secondary/mirror path, and never as "the latest".
- **Proposed action:** Rewrite the Install section to lead with the OTA download and distinguish the two channels explicitly (Phase 3).

### F-2 — P0 — No GitHub Release exists for 2.0.25+50; the newest release is stale

- **Location:** GitHub Releases, repository `Chaitanysai/Spendsense`
- **Current state:**

  | Tag | Name | Asset | Notes |
  |---|---|---|---|
  | `v2.0.13+38` | SpendSense 2.0.13 (build 38) | `spendsense-2.0.13+38.apk` | **marked "Latest"** |
  | `debug-ec1d994` | SpendSense Debug Build | `spendsense-debug.apk` (prerelease) | fine as-is |
  | `spendsense-glassmorphic-debug` | Glassmorphic UI (draft) | — | draft, not public |
  | `2.1.0` | v2.1.0-glassmorphic | *(no asset)* | historical preview |
  | `v2.0.2` | v2.0.2 | `spendsense-debug-signed-sideload.apk` | historical |
  | `v1.0.5+5` / `v1.0.4+4` | SpendSense v1.0.x | `app-release.apk` etc. | historical |

- **Required correction:** Publish a `v2.0.25+50` GitHub Release carrying the **verified** production APK, with accurate release notes, so `releases/latest` resolves to the current build. See Phase 2.
- **Proposed action:** Attach the hash-verified live APK (`3c56d47d…`). Do **not** rebuild.

### F-3 — P0 — `2.0.24+49` returns HTTP 404 from the OTA path

- **URL:** `https://spendsense-ota-2026.web.app/releases/spendsense-2.0.24+49.apk` → **HTTP 404** (2 127-byte HTML error page)
- **Root cause (confirmed, not guessed):** `firebase deploy` replaces the **entire** Hosting release; the published site is exactly the contents of `ota/public` at deploy time. `ota-publish.yml` additionally asserts *"Expected exactly one APK in ota/public/releases"* and **fails the deploy if there is more than one**. So each release necessarily removes every earlier APK. This is by design, and it is documented in `site/README.md` §1 and in the workflow's own comments. It is not a regression.
- **Also 404 (same cause):** `2.0.23+48`, `2.0.21+46` — every version-named APK except the current one.
- **Trusted restoration source found:** a still-unexpired GitHub Actions artefact, `ota-payload` from run **42514904872** (2026-11-08, the 2.0.24+49 deploy):

  | Property | Value |
  |---|---|
  | Path in artefact | `releases/spendsense-2.0.24+49.apk` |
  | Size | 65 176 865 bytes |
  | SHA-256 | `d48fe7ac7edafb4141868a6dfeebaeacfebe808432d1f7d8e046b96b8a04dea5` |
  | Package | `com.example.spendsense` |
  | versionName / code | `2.0.24` / `49` |
  | Signer SHA-256 | `42c8f876…d367` — **identical to the current release cert** |
  | Manifest digest | matches the artefact's own **published** `manifest.json` exactly |

  This is a genuine, signature-verified, install-compatible 2.0.24+49 build — the very bytes that were served in production. **It is a legitimate restoration source and must not be rebuilt.**
- **Caveat:** the artefact has `retention-days: 7` and was created 2026-11-08, so it **expires around 2026-11-15**. Restoration should happen before then or the source is lost.
- **Proposed action:** Restore by attaching the verified artefact — see Phase 2/3 decision point D-1.

### F-4 — P1 — `404.html` tells users the site does not host downloads, which is false

- **File:** `ota/public/404.html` (lines 36–40, 47)
- **Current content:**
  > **Looking for the app?** SpendSense is installed from [the latest GitHub release](https://github.com/Chaitanysai/Spendsense/releases/latest). **This site only hosts the legal pages.**
  >
  > - [Download the latest version](https://github.com/Chaitanysai/Spendsense/releases/latest)
- **Reality:** the statement "this site only hosts the legal pages" is **factually wrong** — the same origin *does* serve the live 2.0.25+50 APK, and `/releases/latest.apk` resolves correctly (verified: `302 → spendsense-2.0.25+50.apk → 200`, 65 373 753 bytes). Worse, the recommended link sends the user to the stale 2.0.13+38 GitHub release (F-1).
- **Required correction:** Point the fallback at `/releases/latest.apk` (the stable redirect that always tracks the manifest) and delete the "only hosts the legal pages" claim. Keep a GitHub link only as a secondary mirror.
- **Proposed action:** Edit `404.html`; note the deployed copy is generated into `ota/public`, so this requires a future OTA deploy to take effect — flag for approval (D-2).

### F-5 — P2 — GitHub repository state has no release tag for the current build

- **Location:** git tags
- **Current:** tags stop at `v2.0.13+38`. No tag exists for `2.0.24+49`, `2.0.25+50`, or any build between `v2.0.13` and now — despite `v2.0.13+38` being tagged while the release branch has advanced 12 version bumps.
- **Required correction:** The `v2.0.25+50` tag should exist if a GitHub Release referencing it is published (Phase 2).
- **Proposed action:** Create the tag as part of the release publish, pointing at `ccd1618d…`.

### F-6 — P2 — No CHANGELOG file exists anywhere in the repository

- **Location:** repository root and `docs/`
- **Current:** no `CHANGELOG.md`, `CHANGELOG`, `RELEASES.md` or equivalent. Release history lives only in (a) commit subjects of the form `release: bump to X.Y.Z+B (#N)` and (b) per-release `releaseNotes` inside each deployed `manifest.json`.
- **Assessment:** The commit log is a usable de-facto changelog and `git log --grep="bump to"` is coherent. This is a **gap, not an error** — nothing contradicts anything.
- **Proposed action:** Either add a `CHANGELOG.md` seeded from the bump commits, or explicitly record in the README that GitHub Releases are the changelog. **Needs your call (D-3)** — adding a new file is a scope decision.

### F-7 — P2 — Historical measurement record references build 49 (correct to leave)

- **Files:** `docs/hosting-cache-headers.md` (lines 17, 76, 90, 195), `docs/repository-finalization/FINAL-REPOSITORY-REPORT.md`, `docs/design-redesign/04-source-reconciliation.md`, `docs/design-redesign/06-validation-report.md`
- **Current content:** statements such as *"Deployed on 2026-11-08 with OTA run 42514904872 (build 2.0.24+49). Readings taken…"*, *"§2.1 records the before/after readings"*, and a before/after table with explicit `2.0.24+49` rows.
- **Assessment:** **These are historical records and are correctly historical.** The heading says "Before", the prose says when the readings were taken, and the numbers are a measurement log of a specific deploy. Editing them to say 2.0.25 would *falsify evidence*. Per the Phase 3 instruction, historical records must remain historically accurate.
- **Proposed action:** **Leave unchanged.** Recorded here so the decision is explicit rather than an oversight.

### F-8 — P2 — CI validator uses a stale version string as a fixture path

- **File:** `tool/validate_hosting_headers.js` (line 142)
- **Current content:** `['/releases/spendsense-2.0.24+49.apk', IMMUTABLE],`
- **Assessment:** The validator tests the `/releases/**` **glob** rule; the filename is an arbitrary fixture. It passes today and will pass for any version. Not a correctness bug — but it reads as a current-release reference and will keep looking stale.
- **Proposed action:** Cosmetic; optionally retarget to the current version or to a neutral `spendsense-9.9.9+99.apk` fixture. Low priority — include only if you want zero stale-looking strings (D-4).

### F-9 — P2 — `backend/download_redirect` test uses build 46 as a fixture URL

- **File:** `backend/download_redirect/test/download_redirect.test.js` (line 19)
- **Current content:** `const GOOD = 'https://spendsense-ota-2026.web.app/releases/spendsense-2.0.21+46.apk';`
- **Assessment:** Same class as F-8 — an arbitrary well-formed fixture, not a release claim. Test passes.
- **Proposed action:** Optional cosmetic retarget. Low priority.

---

## 3. Files inspected (complete list)

**Documentation / user-facing:** `README.md`, `PRODUCT.md`, `DESIGN.md`, `docs/OTA_UPDATES.md`, `docs/hosting-cache-headers.md`, `docs/assistant.md`, `docs/firebase.md`, `docs/email-import.md`, `docs/spending-semantics.md`, `docs/typography.md`, `docs/sync-design.md`, `docs/repository-finalization/FINAL-REPOSITORY-REPORT.md`, `docs/design-redesign/*` (6 files), `docs/design-review/README.md`, `ota/README.md`, `ota/DESIGN.md`, `ota/manifest.example.json`, `site/README.md`, `assets/sounds/CREDITS.md`, `backend/assistant_proxy/README.md`, `ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md`.

**Web / hosting:** `ota/public/index.html`, `ota/public/404.html`, `ota/public/legal/index.html`, `ota/public/landing.css`, `ota/public/site/assets/*` (3 bundles), `site/index.html`, `site/src/**` (App, Hero, HeroScene, Features, HowItWorks, Privacy, Product, Nav, Footer, hooks, tokens), `web/index.html`, `web/manifest.json`, `firebase.json`.

**CI / workflows:** `.github/workflows/ota-publish.yml`, `android-release.yml`, `flutter-test-only.yml`, `pr-build.yml`, `pr-mergeability-check`, `pr-security.yml`, `release-branch-ci.yml`, `.github/actions/flutter-setup/*`, `.github/CODEOWNERS`.

**App / config:** `pubspec.yaml`, `android/app/build.gradle.kts`, `lib/config/update_config.dart`, `lib/models/update_manifest.dart`, `lib/services/update_service.dart`, `lib/screens/update_screen.dart`, `lib/screens/settings_screen.dart`, `tool/generate_ota_manifest.dart`, `tool/validate_ota_manifest.dart`, `tool/validate_hosting_headers.js`, `tool/read_ota_pin.dart`, `tool/ota_pin_parser.dart`, `shorebird.yaml`, `.gitignore`, `ota/manifest.example.json`, `backend/download_redirect/index.js` + tests, `backend/assistant_proxy/package.json`.

**Remote state:** all 7 GitHub Releases + assets, OTA-publish workflow run history (15 runs), Actions artefacts for runs 42514904872 and 43024722623, live `manifest.json`, live APK GETs, live redirect behaviour, git tags.

---

## 4. Download-link validation results

| URL | Method | Result | Verdict |
|---|---|---|---|
| `spendsense-ota-2026.web.app/manifest.json` | GET | 200, valid JSON | ✅ |
| `…/releases/spendsense-2.0.25+50.apk` | GET (full) | 200, 65 373 753 bytes, sha matches | ✅ |
| `…/releases/latest.apk` | GET | 302 → `spendsense-2.0.25+50.apk` | ✅ |
| `…/releases/latest.apk` (followed) | GET | 200, 65 373 753 bytes | ✅ |
| `…/releases/spendsense-2.0.24+49.apk` | GET | **404** | ❌ F-3 |
| `…/releases/spendsense-2.0.23+48.apk` | GET | 404 | expected (superseded) |
| `…/releases/spendsense-2.0.21+46.apk` | GET | 404 | expected (superseded) |
| `github.com/…/releases/download/v2.0.13+38/spendsense-2.0.13+38.apk` | GET | 200, 64 651 940 bytes, verifies | ✅ but stale |
| `github.com/…/releases/latest` | GET | 302 → tag `v2.0.13+38` | ❌ F-1 |
| `github.com/…/releases/download/v2.0.13+38/…` signer | apksigner | `42c8f876…d367` (same cert) | ✅ install-compatible |

GET was used throughout, per the brief — not HEAD — so the reported sizes are true body sizes and the hashes are over the real served bytes.

---

## 5. Contradiction summary

The single systemic contradiction: **GitHub says 2.0.13+38, the OTA channel says 2.0.25+50.** Everything else is consistent. Specifically:

- `pubspec.yaml`, the live manifest, the live APK's own `badging`, and `update_config.dart` **all agree** on `2.0.25` / `50` / `com.example.spendsense` / cert `42c8f876…`.
- `minimumSupportedVersion: 2.0.24` appears only in the live manifest; no repository document contradicts it, and none states a different floor.
- No duplicate or conflicting *install instruction* exists — there is only the README's one (stale) instruction and the working website button.

---

## 6. Decisions needed before Phases 2–3

- **D-1 — 2.0.24+49 restoration.** The artefact expires ~2026-11-15. Options: (a) attach it to a GitHub Release as a verified historical asset (durable, recommended); (b) restore it to Firebase Hosting (would require an OTA deploy — **excluded by your constraints**, since that means republishing and the pipeline permits only one APK anyway); (c) record it as intentionally superseded and leave the 404. **My recommendation: (a)** — it preserves the build without touching production OTA.
- **D-2 — `404.html` fix reach.** The file is source-tracked but the deployed copy only updates on the next OTA deploy. Fixing the source is correct; the live site keeps the old text until a future release. Confirm you accept that lag, or leave it entirely.
- **D-3 — CHANGELOG.** Add one, or document that GitHub Releases are the changelog?
- **D-4 — cosmetic fixtures (F-8, F-9).** Retarget the two stale-looking version strings, or leave them as harmless fixtures?

---

## 7. Status at end of Phase 1

Phase 1 complete. **No files were modified.** The only write so far is this audit document itself. Awaiting your review and answers to D-1…D-4 before Phase 2.

---

## 8. Resolution log (Phases 2–4)

All four decisions were answered by the user and executed. This section is the
current state of the audit.

### 8.1 Findings

| # | Severity | Finding | Status | Evidence |
|---|---|---|---|---|
| F-1 | P0 | README install pointed at a 12-build-old release | ✅ **Fixed** | `README.md` §Install now leads with the OTA download and carries a per-channel table; `releases/latest` re-checked below |
| F-2 | P0 | No GitHub Release for 2.0.25+50 | ✅ **Fixed** | Release `v2.0.25+50` published, marked Latest, asset hash-verified |
| F-3 | P0 | `2.0.24+49` returned 404 with no durable copy | ✅ **Fixed** | Release `v2.0.24+49` published from the original artifact bytes; provenance in the release notes |
| F-4 | P1 | `404.html` claimed the site hosts only legal pages | ✅ **Fixed** (source) | `ota/public/404.html` corrected; **not deployed** — see 8.4 |
| F-5 | P2 | No release tag for the current build | ✅ **Fixed** | Tags `v2.0.25+50` and `v2.0.24+49` now exist |
| F-6 | P2 | No CHANGELOG | ✅ **Fixed** | `CHANGELOG.md` added at repo root |
| F-7 | P2 | Historical cache-header measurements reference build 49 | ⏸️ **Left as-is** (D-4) | Correct decision: these are measurement records |
| F-8 | P2 | `validate_hosting_headers.js` fixture path | ⏸️ **Left as-is** (D-4) | Arbitrary fixture, passes |
| F-9 | P2 | `download_redirect` test fixture URL | ⏸️ **Left as-is** (D-4) | Arbitrary fixture, passes |

### 8.2 D-1 — `2.0.24+49` recovery

Recovered from Actions artifact `ota-payload` ID `13630679843`, run
`42514904872`, **before its ~2026-11-15 expiry**, and published as a GitHub
Release asset. Published **unmodified**.

Provenance rests on digest equality, which is the part that cannot be forged:
the artifact carried the `manifest.json` that was deployed to production for this
build, and that manifest's `sha256` field equals the digest of the attached APK
exactly (`d48fe7ac…4dea5`). A rebuild could not reproduce that digest.

Locally the recovered bytes are held git-ignored in `.release-recovery/`; the
65 MB binary is deliberately kept out of Git history. Publishing it to the OTA
channel was **not** done — that would have required an OTA deploy, which the
constraints exclude.

### 8.3 D-2 — `404.html`

The false "this site only hosts the legal pages" claim is gone, and both the
callout and the link list now point at `/releases/latest.apk` — the stable
redirect that reads the live manifest. The stale `2.0.13+38` destination is no
longer reachable from this page.

### 8.4 Known lag: the deployed `404.html` is still the old one

**This is the one finding that is fixed in source but not in production, and it
cannot be fixed without a deploy.** Firebase Hosting serves `ota/public` as one
release, so the corrected file reaches users only on the next OTA deploy. The
brief excludes deploying, so the live site keeps the old text until then.
Flagged here rather than left implicit.

### 8.5 D-3 — `CHANGELOG.md`

Added at the repository root. Covers `2.0.25+50` and `2.0.24+49`, links each to
its GitHub Release, separates features / improvements / fixes / compatibility,
and states GitHub Releases as the authoritative home for downloadable assets.

**No historical detail was invented.** The "Earlier releases" section is
deliberately an honest gap — the releases before `2.0.24+49` predate the changelog
and their artifacts are gone from the OTA channel, so reconstructing notes for
them from incomplete evidence would have meant fabricating a record.

### 8.6 D-4 — preserved reference material

Left untouched, on purpose: the historical measurement log in
`docs/hosting-cache-headers.md` (rewriting it to say 2.0.25 would falsify
evidence), and the arbitrary version strings in
`tool/validate_hosting_headers.js` and
`backend/download_redirect/test/download_redirect.test.js`.

### 8.7 Phase 4 — re-validation after the fixes

Every check below was run against the live services **after** the changes, using
full GET rather than HEAD, and every APK was hashed over the actual served bytes.
All three files were re-downloaded and re-hashed independently of the originals.

**Link checks**

| URL | Method | Result | Verdict |
|---|---|---|---|
| `…/releases/latest.apk` | GET | 302 → `spendsense-2.0.25+50.apk` | ✅ |
| `…/releases/latest.apk` (followed) | GET | 200, 65 373 753 bytes | ✅ |
| `spendsense-ota-2026.web.app/manifest.json` | GET | 200, valid JSON | ✅ |
| `spendsense-ota-2026.web.app/` | GET | 200 | ✅ |
| `spendsense-ota-2026.web.app/legal/` | GET | 200 | ✅ |
| `github.com/…/releases/latest` | GET | 302 → **`v2.0.25+50`** (was `v2.0.13+38`) | ✅ **F-1 root cause gone** |
| `github.com/…/releases/tag/v2.0.25+50` | GET | 200 | ✅ |
| `github.com/…/releases/tag/v2.0.24+49` | GET | 200 | ✅ |
| `github.com/…/actions/runs/42514904872` | GET | 200 | ✅ |
| `…/releases/spendsense-2.0.24+49.apk` (OTA) | GET | 404 | ⚠️ expected — documented in `CHANGELOG.md` §OTA downloads |

**Checksums over re-downloaded bytes**

| Artifact | Source | Bytes | SHA-256 | Verdict |
|---|---|---|---|---|
| 2.0.25+50 APK | OTA (followed redirect) | 65 373 753 | `3c56d47d…90551` | ✅ matches baseline |
| 2.0.25+50 APK | GitHub Release asset | 65 373 753 | `3c56d47d…90551` | ✅ **byte-identical to OTA** |
| 2.0.24+49 APK | GitHub Release asset | 65 176 865 | `d48fe7ac…4dea5` | ✅ matches recovered source |

**Build identity and signature** (`aapt2 dump badging`, `apksigner verify --print-certs`)

| APK | Package | versionName / code | Signer SHA-256 |
|---|---|---|---|
| 2.0.25+50 (OTA) | `com.example.spendsense` | `2.0.25` / `50` | `42c8f876…d367` |
| 2.0.25+50 (GitHub) | `com.example.spendsense` | `2.0.25` / `50` | `42c8f876…d367` |
| 2.0.24+49 (GitHub) | `com.example.spendsense` | `2.0.24` / `49` | `42c8f876…d367` |

All three carry the **same signing certificate as the pinned release cert**, so
both preserved builds install over and update in place on an existing install.

**Repository self-consistency**

- `node tool/validate_hosting_headers.js` → *"OK: hosting cache policy matches the
  deploy contract."*
- `npm test` in `backend/download_redirect` → 11 passed, 0 failed.
- Repo-wide grep confirms **no tracked file still directs users to `2.0.13+38`**.
  The only remaining `2.0.13` strings are in `docs/design-redesign/*` and
  `docs/repository-finalization/*`, where they are accurate history about the
  branch name and a past checkout.

### 8.8 Constraints observed

Production OTA Hosting and the live manifest were **not** touched. No OTA release
was published. No signing credentials or Firebase configuration were changed. No
history was rewritten and nothing was force-pushed. The dirty
`design/home-go-club-suno` worktree was not touched. Nothing was merged.

