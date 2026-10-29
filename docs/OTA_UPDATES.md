# SpendSense OTA updates

Status: **implemented locally, not deployed.** The app, manifest validation,
download verification, native installer bridge, tests, CI artifact generation,
and hosting configuration are in place. Publishing requires a hosting project
and explicit authorization; see [Remaining manual steps](#15-remaining-manual-steps).

SpendSense does not use Shorebird, Firebase Remote Config, Firestore, or any
Firebase SDK. Updates are a static HTTPS manifest plus a signed APK, verified
on-device against a certificate pinned in source.

---

## 1. Architecture and trust boundaries

```
┌────────────────────┐        HTTPS GET         ┌─────────────────────────┐
│ SpendSense (Flutter)│ ───────────────────────▶ │ Static host             │
│ package_info_plus   │                          │  /manifest.json         │
│ UpdateService       │ ◀─────────────────────── │  /releases/<apk>        │
└─────────┬──────────┘                          └─────────────────────────┘
          │ download to cache/updates
          ▼
  SHA-256(APK) == manifest.sha256 ?
  APK packageName == com.example.spendsense ?
  APK signer SHA-256 == pinned certificate ?
          │ yes
          ▼
  MethodChannel → FileProvider → Android package installer → user confirms
```

Trust anchors:

| Input | Trust | Enforcement |
|---|---|---|
| Manifest JSON | **Untrusted** | Strict schema, app ID, HTTPS, approved host, hash/cert format, version monotonicity |
| Manifest `sha256` | Untrusted, but useful for corruption | Compared against the bytes actually downloaded |
| Manifest `signingCertSha256` | Untrusted claim | Must equal the certificate pinned in `lib/config/update_config.dart` |
| APK signer | Verified on-device | `PackageManager` signing info compared to the pinned certificate |
| HTTPS transport | Protects confidentiality/integrity in transit | `https` only; no cleartext |
| Release key | **Root of trust** | Held in GitHub secrets / local keystore; never in the app |

A SHA-256 delivered next to the APK over the same channel is not a sufficient
trust anchor. The pinned certificate is. Compromising the host lets an attacker
serve a different manifest, but they still cannot produce an APK signed by the
SpendSense release key, so the update is rejected before the installer opens.

Pinned certificate (SHA-256 of the DER certificate, lowercase hex):

```
42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367
```

---

## 2. Components

| File | Responsibility |
|---|---|
| `lib/models/update_manifest.dart` | `AppVersion` comparison, strict manifest parser, update policy |
| `lib/config/update_config.dart` | Pinned certificate, app ID, `OTA_MANIFEST_URL` / `OTA_DOWNLOAD_HOSTS`, timeouts |
| `lib/services/update_service.dart` | Manifest fetch, download, SHA-256, signature/package inspection, installer orchestration, cancellation |
| `lib/services/update_platform.dart` | `MethodChannel('spendsense/update')` contract and typed errors |
| `lib/providers/update_provider.dart` | UI state machine, duplicate-operation guards, silent startup check |
| `lib/screens/update_screen.dart` | Glassmorphic update UI reached from Settings |
| `android/.../MainActivity.kt` | APK inspection, unknown-app-sources permission, system installer |
| `android/app/src/main/res/xml/file_paths.xml` | Only `cache/updates/` is shareable |
| `tool/generate_ota_manifest.dart` | Builds `manifest.json` from a verified APK |
| `.github/workflows/android-release.yml` | Fail-closed build, pinned-cert check, OTA manifest artifact |
| `firebase.json` | Firebase Hosting config for `ota/public/` |

The Settings → **Software update** tile shows the live installed version and
opens the update screen. The app performs one quiet check after startup; it
never blocks startup, never shows a dialog, and never plays a sound.

---

## 3. Prerequisites

- Flutter stable with Dart 3 (`flutter --version`)
- Java 17 (`java -version`)
- Android SDK platform 36 and build-tools 36.0.0
- Packages: `package_info_plus ^9.0.1`, `crypto ^3.0.7`, plus the existing
  `http`, `path`, `path_provider`
- For hosting only: Firebase CLI (`npm i -g firebase-tools`) and access to the
  Firebase project

Ordinary unit tests need none of the cloud tooling.

---

## 4. Local development

### Build an updater-enabled build

```sh
flutter build apk --release \
  --dart-define=OTA_MANIFEST_URL=https://your-host.example/manifest.json
```

The manifest host is automatically added to the approved download hosts. Add
extra hosts (for example a CDN) with:

```sh
  --dart-define=OTA_DOWNLOAD_HOSTS=cdn.your-host.example
```

Without `OTA_MANIFEST_URL` the app compiles normally; the update screen reports
"Update channel not configured" and performs **no network request**. This is the
expected state for local builds.

### Important debug-build limitation

The verifier checks the **downloaded APK**, not the running app. A debug build
can download and verify a release APK, but Android will refuse to install it
over a debug-signed installation because the signing identities differ. Test
the full flow with a release build signed by the release key (or install the
release APK first). Never uninstall a release build to "fix" this — uninstalling
deletes local transaction data.

### Local manifest

`UpdateService` accepts a `Uri` and enforces HTTPS. To test locally, serve the
files through an HTTPS endpoint (a tunnel or a local reverse proxy with a
trusted certificate) and pass that URL. Cleartext HTTP is rejected by design and
is not configurable.

---

## 5. Manifest schema

`schemaVersion` is currently `1`. Unknown versions are rejected.

```json
{
  "schemaVersion": 1,
  "appId": "com.example.spendsense",
  "latestVersion": "2.0.0",
  "latestBuildNumber": 20,
  "minimumSupportedVersion": "2.0.0",
  "downloadUrl": "https://YOUR_APPROVED_HOST/releases/spendsense-2.0.0+20.apk",
  "releaseNotes": [
    "Initial OTA-enabled release"
  ],
  "sha256": "GENERATED_APK_SHA256",
  "signingCertSha256": "42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367",
  "publishedAt": "GENERATED_UTC_TIMESTAMP"
}
```

Rules enforced by the parser:

| Field | Rule |
|---|---|
| `schemaVersion` | Integer, exactly `1` |
| `appId` | Exactly `com.example.spendsense` |
| `latestVersion` | `x.y.z` with numeric segments; optional `-prerelease` |
| `latestBuildNumber` | Positive integer |
| `minimumSupportedVersion` | `x.y.z`, not newer than `latestVersion` |
| `downloadUrl` | Absolute `https://` URL, no credentials, approved host, no dot segments, path ends in `.apk` |
| `releaseNotes` | Optional list of strings |
| `sha256` | 64 hex characters (colons/uppercase normalised) |
| `signingCertSha256` | 64 hex characters; must equal the pinned certificate |
| `publishedAt` | Optional ISO-8601 timestamp |

Version comparison is numeric (`1.10.0 > 1.9.9`), the build number breaks ties,
and a release outranks its own pre-release. It never compares strings
lexicographically.

Policy outcomes:

- **Up to date** — installed version is equal to or newer than `latestVersion`
- **Optional** — installed is below `latestVersion` but at/above the minimum
- **Required** — installed is below `minimumSupportedVersion`

A required update is advisory in the UI: it is surfaced prominently but never
blocks the app, never deletes data, and never prevents JSON export from
Settings.

---

## 6. Hosting setup (manual, requires authorization)

`firebase.json` is committed with `public: "ota/public"`. The directory layout
is:

```
ota/public/
├── manifest.json
└── releases/
    └── spendsense-2.0.0+20.apk
```

Steps:

1. `firebase login`
2. Select or create the project: `firebase projects:list`, then
   `firebase use --add` (this writes `.firebaserc` locally).
3. Do **not** run `firebase init hosting` against the existing `firebase.json`
   unless you intend to review and merge its changes.
4. Generate the release files (Section 7), then deploy:
   `firebase deploy --only hosting`
5. Configure the custom domain and verify HTTPS in the Firebase console.
6. Verify the published manifest:
   `curl -sS https://YOUR_HOST/manifest.json` and confirm the APK URL returns
   the same bytes/hash that CI produced.

`.firebaserc` contains a project identifier (not a secret). Commit it only if
the team agrees the identifier is public; otherwise keep it local. Never commit
`FIREBASE_TOKEN`, service-account JSON, or `firebase login` credentials.

CI does **not** deploy. Deployment requires a human with project access.

---

## 7. Release publication

1. Decide the version explicitly and bump `pubspec.yaml` (`version: 2.0.1+21`).
   Nothing increments it automatically.
2. Build and verify in CI (`.github/workflows/android-release.yml` →
   `workflow_dispatch`) or locally:
   ```sh
   flutter analyze
   flutter test
   flutter build apk --release
   ```
3. Confirm the APK signature and certificate with `apksigner verify
   --print-certs`. CI fails if it differs from the pinned certificate.
4. Generate the manifest from the **verified** APK:
   ```sh
   mkdir -p ota/public/releases
   cp build/app/outputs/flutter-apk/app-release.apk \
      "ota/public/releases/spendsense-2.0.1+21.apk"
   dart run tool/generate_ota_manifest.dart \
     --apk "ota/public/releases/spendsense-2.0.1+21.apk" \
     --base-url https://YOUR_HOST \
     --out ota/public/manifest.json \
     --notes "Faster insight cards"
   ```
   Version and build number come from `pubspec.yaml`; the tool computes the
   SHA-256 itself. It refuses non-HTTPS base URLs and non-numeric versions.
5. Upload the APK and manifest with the hosting CLI.
6. Smoke test with the previous release installed: Settings → Software update →
   Check → Download → Install.
7. Keep `manifest.json` non-cacheable and release APKs immutable (see
   `firebase.json`). Never reuse a versioned filename for different bytes.

In CI, the manifest is generated only when the repository variable
`OTA_BASE_URL` is set, and is uploaded as the `ota-manifest` artifact. The
workflow never publishes it.

---

## 8. Secrets and configuration

| Name | Where | Purpose |
|---|---|---|
| `SIGNING_KEY` | GitHub secret | Base64 release keystore |
| `KEY_ALIAS` | GitHub secret | Release key alias |
| `KEY_PASSWORD` | GitHub secret | Key password |
| `STORE_PASSWORD` | GitHub secret | Keystore password |
| `OTA_BASE_URL` | GitHub repository **variable** | Public HTTPS origin used to build the manifest URL |
| `OTA_MANIFEST_URL` | Build `--dart-define` | Manifest endpoint compiled into the app |
| `OTA_DOWNLOAD_HOSTS` | Build `--dart-define` | Extra approved hosts (comma-separated) |

Local signing lives in `android/key.properties` and
`android/app/upload-keystore.jks`, both ignored by git. No secret is ever
printed by the app or the tooling; the pinned certificate is a public value.

---

## 9. Certificate verification

- In CI: `apksigner verify --print-certs` output is normalised and compared to
  the pinned fingerprint; a mismatch fails the build before artifacts upload.
- On-device: `MainActivity` reads the downloaded archive with
  `PackageManager.getPackageArchiveInfo` and hashes the signer's DER
  certificate. `UpdateService` compares it to the pinned value **and** checks
  the manifest's claimed value.
- Manual check:
  ```sh
  APKSIGNER=$(ls "$ANDROID_HOME"/build-tools/*/apksigner | tail -n1)
  "$APKSIGNER" verify --print-certs path/to/app-release.apk
  ```
  Compare the `SHA-256 digest` line with the pinned value.

Certificate rotation is a breaking change: an app can only accept updates signed
by the certificate it was built with. Rotate by shipping a final update signed
with the old key that pins the new certificate, then sign subsequent releases
with the new key. Document the rotation with the release.

---

## 10. User update flow

1. Settings → Software update shows the installed version/build.
2. **Check for updates** fetches and validates the manifest.
3. If a newer version exists, release notes and a **Download update** button
   appear (plus a required-update notice when applicable).
4. Download shows progress and can be cancelled; cancelled or failed downloads
   are deleted.
5. After download the app verifies SHA-256, package name, and signer. A failure
   shows a clear error and the file is removed.
6. **Install update** asks for the "install unknown apps" permission when
   needed, opens that Android settings page, then launches the system package
   installer after the user returns.
7. Android shows its own confirmation dialog. Nothing installs silently, and
   the app never uninstalls itself.

---

## 11. Data preservation

- Updates use Android's normal same-certificate in-place install; the app is not
  uninstalled and its data directory is preserved.
- OTA code only creates and deletes files under `cache/updates/`. It never
  touches the transaction database, secure storage, or exported backups.
- A test asserts that a download verification failure does not delete an
  unrelated file in the cache directory.
- JSON export/import in Settings keeps working regardless of update state, and a
  required update never blocks export.
- `allowBackup="false"` is unchanged: uninstalling the app deletes local data.
  Users who need a safety copy should export JSON before any manual reinstall.

---

## 12. Testing

```sh
flutter analyze
flutter test
```

New coverage:

- `test/update_manifest_test.dart` — numeric version/build ordering, pre-release
  ordering, valid parsing, invalid JSON, wrong app ID, unsupported schema,
  missing fields, invalid versions/builds, minimum-version policy, insecure and
  unapproved URLs, malformed hashes/certificates/notes/timestamps, and all
  update-policy outcomes.
- `test/update_service_test.dart` — up-to-date/optional/required checks, invalid
  manifest, untrusted certificate claim, timeout/offline mapping,
  unconfigured channel, successful download, hash mismatch cleanup, signer
  mismatch, package mismatch, unapproved URL, cancellation cleanup, HTTP errors,
  unrelated-file preservation, and installer permission gating.

Manual device checks that cannot run in unit tests:

- Fresh install of release N, publish N+1, verify the in-place update.
- Deny "install unknown apps", confirm the explanation and settings deep link.
- Cancel the Android installer and confirm the app still runs.
- Airplane mode during check and during download.
- Low-storage download failure.

---

## 13. Outage and rollback

- **Host offline / no network:** checks return a network error; the app remains
  fully usable and local-first.
- **Bad manifest pushed:** clients reject it (invalid schema/host/cert) and keep
  the installed version. Fix the manifest; no app update is required.
- **Bad APK published:** clients whose download fails verification never reach
  the installer. If a bad build was already installed, publish a new build with
  a **higher** build number built from the last good source. Android will not
  install a lower version number over a higher one, so "rollback" means
  forward-shipping a fixed build.
- **Certificate/key compromise:** follow the rotation procedure in Section 9;
  an emergency build signed with the compromised key is still trusted by
  existing installs, so treat the key compromise as a full release incident.

---

## 14. Threat model summary

Mitigated:

- Manifest tampering → strict validation + pinned certificate claim
- Host/CDN compromise → APK signer pin rejects unauthorized binaries
- Corrupted/truncated downloads → SHA-256 + delete-on-failure
- Arbitrary URL/path injection → HTTPS, approved host, `.apk`, sanitized local
  filename, path check in the native installer
- Silent installation → Android permission + system confirmation required
- Overwriting user data → cache-only writes; backup/export untouched
- Debug APK masquerading as release → CI fail-closed certificate comparison

Not mitigated (documented):

- A compromised **release signing key** can produce trusted malware. Key custody
  is the critical control.
- A rooted/compromised device can bypass Android's installer consent.
- Downgrade attacks are prevented by Android's version checks, not by the app.

---

## 15. Remaining manual steps

1. Choose the hosting project and confirm the production origin.
2. Run `firebase use --add`, configure the domain, and verify HTTPS.
3. Set the GitHub repository variable `OTA_BASE_URL`.
4. Build the first updater-enabled release with
   `--dart-define=OTA_MANIFEST_URL=https://YOUR_HOST/manifest.json`.
5. Publish the APK + manifest (Section 7) after explicit authorization.
6. Install that release on a device, then publish the next build and complete the
   manual device checks in Section 12.

Until steps 1–5 are done, the app reports "Update channel not configured" and no
update traffic occurs.
