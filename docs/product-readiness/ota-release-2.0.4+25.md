# OTA release 2.0.4+25 — deployed and verified

**Date:** 2026-10-24 03:40 IST · **Project:** `spendsense-ota-2026` (Firebase Hosting)

## Result: DEPLOYED and VERIFIED (remote checks passed)

Device validation of the new features is **not** complete. The release was published
on an explicit owner decision to accept that risk; the owner tests on their own phone.

## Release artifact

| Property | Value |
|---|---|
| Version | 2.0.4 (versionName) + 25 (versionCode) — `pubspec.yaml` `version: 2.0.4+25` |
| Package | `com.example.spendsense`, minSdk 24, targetSdk 36 |
| Size | 86,414,130 bytes |
| SHA-256 | `877092addd6f6df5904c5fc5229bb053ed316601fadfa9d40def56a79eb315d4` |
| Signer | `CN=chaitanya.sai, OU=me, O=Mine, L=Hyderabad, ST=Telangana, C=IN` — certificate SHA-256 `42c8f876…cb20d367`, equal to the pinned constant in `lib/config/update_config.dart` (`apksigner verify --print-certs`) |
| Build | `flutter build apk --release --dart-define=OTA_MANIFEST_URL=https://spendsense-ota-2026.web.app/manifest.json` |
| Signing source | `android/key.properties` (no credential values read or printed) |

The earlier reference hash `D22206…` belonged to an earlier build of the same
version and is **not** the published artifact.

## OTA manifest

Generated with `tool/generate_ota_manifest.dart --minimum 2.0.1` (never hand-edited):
latest 2.0.4+25, minimum supported 2.0.1 (update stays optional), `sha256` equal to the
APK's hash, `signingCertSha256` equal to the pinned certificate, `publishedAt`
2026-10-23T22:09:33.815536Z, download URL
`https://spendsense-ota-2026.web.app/releases/spendsense-2.0.4+25.apk`.

## Deployment verification

- `firebase deploy --only hosting --project spendsense-ota-2026`: completed.
- Remote manifest: latestVersion 2.0.4, build 25, minimum 2.0.1, sha256 and certificate
  match the local manifest.
- Remote APK: HTTP 200, `Content-Type: application/vnd.android.package-archive`,
  `Content-Length: 86414130`.
- Downloaded remote APK SHA-256 equals the local artifact hash.
- Previous releases still reachable (HTTP 200): 2.0.3+24, 2.0.2+22, 2.0.1+21.

## Source state

The published APK was built from the complete uncommitted working tree at HEAD
`33166cb062690c2c4ffa7e520b7a1071c4ddbe93` (branch `chore/cleanup-root-files`). That
tree contains work from several generations: the OTA updater, sound effects, encrypted
ledger and migration, SMS content policy, and the 2.0.4 dashboard, typography, budgets,
planned bills, insights and summary. The checkpoint commit that records this source
state is therefore a snapshot, not an isolated release diff.

## Notes and remaining items

- Installed devices on older builds will see this as an optional update.
- Not device-validated: fault-injection, tamper, missing-key and Keystore behaviour
  (see earlier validation records). The owner is testing the new features on a phone.
- `ota/public/manifest.json` and `ota/public/releases/*` are gitignored by design and
  are not part of the checkpoint commit.
