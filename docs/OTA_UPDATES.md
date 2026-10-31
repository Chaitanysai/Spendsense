# OTA updates

SpendSense can update itself from a static HTTPS manifest and a signed APK. It
does not use Shorebird, Firebase Remote Config or a Firebase SDK for updates.

## How an update works

```
App (package_info_plus)
  │  HTTPS GET manifest.json
  ▼
Manifest ──► version newer?
  │
  ├─ download APK to cache
  ├─ SHA-256(APK) == manifest.sha256?
  ├─ APK packageName == application id?
  └─ APK signer == pinned release certificate?
         │ yes
         ▼
  FileProvider → Android package installer → user confirms
```

The manifest is untrusted. The APK signature is the trust anchor: the
certificate fingerprint is pinned in `lib/config/update_config.dart`, so a
compromised host cannot deliver an APK signed by anyone else.

## Guarantees

- Manifest URL and download hosts must use HTTPS; approved hosts are compiled
  in with `--dart-define`.
- The manifest has a strict schema, app id, version monotonicity and download
  URL checks.
- The downloaded bytes must match the manifest SHA-256.
- The APK package name and signer must match the pinned values before the
  system installer is opened.
- Updates are never silent: Android shows its installer confirmation.
- A failed check, download or verification leaves the current install intact.

## Configuration

The release build supplies:

```bash
flutter build apk --release \
  --dart-define=OTA_MANIFEST_URL=https://<host>/manifest.json \
  --dart-define=OTA_DOWNLOAD_HOSTS=<host>
```

`OTA_DOWNLOAD_HOSTS` is a comma-separated allowlist for additional download
hosts; the manifest host is added automatically.

## Publishing

Publishing is a two-step CI job:

1. **Build and validate** — build a release APK, verify its certificate against
   the pin, upload the APK under `ota/public/releases/`, generate
   `ota/public/manifest.json` with `tool/generate_ota_manifest.dart`, and verify
   the staged payload.
2. **Deploy** — deploy only `ota/public/` to the static host after an explicit
   deploy confirmation.

`manifest.json`, APKs and checksum sidecars are generated artifacts and are
ignored by Git. Keep release keys in CI secrets, never in the repository or the
APK.

## Manifest shape

```json
{
  "schemaVersion": 1,
  "appId": "<application-id>",
  "latestVersion": "x.y.z",
  "latestBuildNumber": 0,
  "minimumSupportedVersion": "x.y.z",
  "downloadUrl": "https://<host>/releases/<apk>",
  "releaseNotes": ["..."],
  "sha256": "<apk sha256>",
  "signingCertSha256": "<pinned certificate sha256>",
  "publishedAt": "<ISO-8601>"
}
```

## Security notes

- A hash delivered beside the APK is not sufficient on its own; the pinned
  certificate is what prevents a malicious host from shipping a different app.
- Protect the release signing key. If it is lost or leaked, pinned installs must
  be migrated through a new application identity.
- A rooted device can bypass Android's installer consent; that is outside the
  app's control.
- Android's version checks prevent downgrades, not the manifest.

## Testing a release

1. Install a build compiled with `OTA_MANIFEST_URL`.
2. Publish a manifest with a higher version/build.
3. Open **Settings → Software update → Check**.
4. Verify the download, hash, package and certificate checks, then confirm the
   system install.
5. Relaunch and confirm the ledger and account state are intact.
