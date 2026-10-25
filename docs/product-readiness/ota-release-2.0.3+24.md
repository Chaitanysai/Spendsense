# OTA release 2.0.3+24 — deployed and verified

**Date:** 2026-10-24 02:00 IST · **Project:** `spendsense-ota-2026` (Firebase Hosting)

## Result: DEPLOYED and VERIFIED

## Blocker review before release

- **Original-SMS panel wording (gate 2.6):** no defect. `transaction_details_screen.dart`
  implements exactly the gate's expected wording for all three cases (stored body
  displayed via `SmsContentPolicy.preserve`, "No source message (manually added).",
  "The source message is not stored. Amount, merchant and date were read from your
  bank SMS."). Nothing to fix.
- **Corrupted-ledger UX / large-text overflow:** already fixed and regression-tested
  in Stage 1 (see `release-candidate-gates-stage1.md`).
- **Stale release artifact / stale manifest:** resolved by this release.

## Release artifact

| Property | Value |
|---|---|
| Version | 2.0.3 (versionName) + 24 (versionCode) — pubspec unchanged, approved value |
| Package | `com.example.spendsense`, minSdk 24, targetSdk 36 |
| Size | 57,348,354 bytes |
| SHA-256 | `8749d8ef8097a24fc9f1b744c60f3395a103f8e65195d43d882344f943f017b3` |
| Signer | `CN=chaitanya.sai, OU=me, O=Mine, L=Hyderabad, ST=Telangana, C=IN` — certificate SHA-256 `42c8f876…cb20d367`, **equal to the pinned constant** in `lib/config/update_config.dart` (verified with `apksigner verify --print-certs`) |
| Build | `flutter build apk --release --dart-define=OTA_MANIFEST_URL=https://spendsense-ota-2026.web.app/manifest.json` — updater-enabled per `docs/OTA_UPDATES.md`; the compiled `libapp.so` contains the manifest host (compile-time `String.fromEnvironment`) |
| Signing source | `android/key.properties` (field names only inspected; no credential values read or printed) |

## OTA manifest

Generated with `tool/generate_ota_manifest.dart` (never hand-edited):
`https://spendsense-ota-2026.web.app/manifest.json` — latest 2.0.3+24, minimum
supported 2.0.1 (previous policy preserved), `sha256` equals the APK's actual
hash, `signingCertSha256` equals the pinned certificate, download URL
`https://spendsense-ota-2026.web.app/releases/spendsense-2.0.3+24.apk`.

Update-policy behaviour (downgrade refusal, minimum-version mandatory update,
hash/pin enforcement) re-validated with the targeted suites
`update_manifest_test` + `update_provider_test` + `update_service_test` — 45/45 passed.

## Deployment verification (all confirmed after `firebase deploy --only hosting`)

- Published manifest fields match the local generated manifest exactly
  (including `publishedAt` 2026-10-23T20:24:38Z).
- Published APK: HTTP 200, `Content-Length: 57348354` (exact),
  `Content-Type: application/vnd.android.package-archive`,
  `Cache-Control: public, max-age=31536000, immutable`, and the **downloaded
  file's SHA-256 equals the local release hash** (byte-identical artifact).
- Manifest served with `no-cache` headers (per `firebase.json`).
- Previous releases remain reachable (HTTP 200) for rollback:
  2.0.1+21, 2.0.2+22, 2.0.3+23.

## Notes and remaining items

- The OnePlus test device runs the debug-signed 2.0.3+24 build; OTA applies to
  release-signed installs, so in-app update flow on that device is expected to
  report no applicable update. No device changes were made.
- Nothing was committed or pushed; `ota/public` artifacts are gitignored by design.
- CI (`android-release.yml`) still builds without the OTA dart-define; its APKs
  are store/manual-distribution builds. If CI should ship OTA-enabled builds,
  add the `--dart-define` there (deliberate left unchanged in this release).
