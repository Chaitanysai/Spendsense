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

### Channels

`ota-publish` takes a `channel` input, `production` (the default) or `staging`.
The channel is a path prefix and nothing else:

| | production | staging |
|---|---|---|
| manifest | `/manifest.json` | `/staging/manifest.json` |
| APK | `/releases/spendsense-<v>.apk` | `/staging/releases/spendsense-<v>.apk` |
| compiled into | default builds | builds made with `OTA_MANIFEST_URL=…/staging/manifest.json` |

A staging build is compiled against `/staging/manifest.json`, so a production
release can never offer a staging build to a production install, and vice versa.
Three things must agree for this to hold — the directory compiled into the APK,
the `--base-url` the manifest generator is given, and the directory the deploy
stages — and the workflow derives all three from the one `channel` input rather
than letting them be set independently.

The staging payload lives in `ota/public/staging/` inside the same Hosting site.
`firebase deploy` replaces the whole release, so both channels are always
published together from one validated payload; a staging publish therefore
re-publishes production byte-identically. Staging needs its own cache rules
(`/staging/manifest.json` revalidates, `/staging/releases/spendsense*.apk` is
immutable), because `/releases/spendsense*.apk` does not match the nested path.

Promoting a staging build to production is a rebuild, not a file move: the
manifest URL is compiled into the APK, so a staging APK always polls staging.
Publish the same source at the same version with `channel: production`, which
gives a production-flavoured APK and the production manifest in one run.

Because `/staging/` is a directory in the hosted payload, anyone who knows the
URL can read the staging manifest and download staging builds. Staging is a
test channel, not a private one — do not publish anything to it that you would
not publish.

## Version monotonicity

The workflow refuses to publish a candidate that is not strictly newer than the
manifest already live on that channel. This is a real failure mode, not
belt-and-braces: the update decision is made on the client
(`UpdatePolicy.decide` → `latest.isNewerThan(installed)` → `AppVersion.compareTo`
> 0), and nothing on the server compares a candidate against the live manifest.
A non-increasing candidate passes every other gate, publishes cleanly, and is
then silently never offered — CI is green, the site updates, and no device
moves. Publishing a *lower* build is worse: Android refuses to install a lower
`versionCode`, so even a forced download could not be applied.

`tool/check_ota_monotonicity.dart` runs before the manifest is staged. It reads
the live manifest for the channel and mirrors `AppVersion.compareTo` exactly —
major, minor, patch, then release-before-pre-release, then dot-split
pre-release parts, then build number. It deliberately does not use `sort -V`,
which disagrees with the app both on pre-release ordering and on
equal-version-different-build, i.e. exactly on rebuilds of the current release.
A candidate equal to the live version+build is refused; a rebuild needs the
build number bumped.

A 404 from the live manifest is treated as "first publish on this channel" and
passes with a loud note. Any other HTTP failure is fatal, so a network blip
cannot read as "nothing to compare" and let a non-monotonic build through.

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
