# Changelog

Release history for SpendSense. Newest first.

Downloadable APKs live on **[GitHub Releases](https://github.com/Chaitanysai/Spendsense/releases)**.
That is the authoritative location for release binaries: every entry below links
to the release page that carries its signed APK and its SHA-256. The OTA channel
at <https://spendsense-ota-2026.web.app> serves only the current build — see
[OTA downloads](#ota-downloads) for why the two channels differ.

Versions are `MAJOR.MINOR.PATCH+BUILD`. The build number is the Android
`versionCode` and is what the OTA updater compares; the version name is the
`versionName` users see.

## [2.0.25+50](https://github.com/Chaitanysai/Spendsense/releases/tag/v2.0.25%2B50) — 2026-11-10

The Opus 5.5 redesign. Current production release.

**Features**

- Redesigned transaction surfaces — Stage 1 and Stage 2 of the Opus 5.5 work.
- Nineteen curated palettes, each in light and dark mode, grouped into three
  families.

**Compatibility**

- `minimumSupportedVersion` raised to `2.0.24`. Builds older than that are asked
  to update before continuing.
- Signing certificate unchanged, so updating in place keeps the local ledger.
  See [Compatibility](#compatibility) below.

**Assets**

| | |
|---|---|
| versionName / versionCode | `2.0.25` / `50` |
| Package | `com.example.spendsense` |
| minSdk / targetSdk | `24` (Android 7.0+) / `36` |
| SHA-256 | `3c56d47d9634d8075c8405a2cf7ea2a5704df3a4090d6a6c44527d5432e90551` |
| Signing certificate SHA-256 | `42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367` |

Deployed commit `ccd1618de70942d109cd9ce82b6fcb185de3b2da` on `release/2.0.13+38`.

## [2.0.24+49](https://github.com/Chaitanysai/Spendsense/releases/tag/v2.0.24%2B49) — 2026-11-08

Preserved historical build. Superseded by 2.0.25+50; most users should install
the newer release.

**Improvements**

- Immutable, long-lived cache headers for content-hashed assets on the hosting
  origin, with revalidation for HTML.

**Compatibility**

- `minimumSupportedVersion` was `2.0.24`, making this the floor of the currently
  supported range.
- The live OTA channel no longer serves this version.

**Assets**

| | |
|---|---|
| versionName / versionCode | `2.0.24` / `49` |
| Package | `com.example.spendsense` |
| minSdk / targetSdk | `24` (Android 7.0+) / `36` |
| SHA-256 | `d48fe7ac7edafb4141868a6dfeebaeacfebe808432d1f7d8e046b96b8a04dea5` |
| Signing certificate SHA-256 | `42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367` |

The attached APK is the original artifact bytes for this build, recovered from
the `ota-payload` artifact of OTA workflow run
[`42514904872`](https://github.com/Chaitanysai/Spendsense/actions/runs/42514904872)
and republished unmodified — not rebuilt. Its authenticity rests on the
`manifest.json` that the same artifact carried into production: that manifest's
`sha256` field is byte-for-byte identical to the digest of the attached APK.
Deployed commit `e7216905`.

## Earlier releases

Releases before `2.0.24+49` predate this changelog and their artifacts are no
longer available from the OTA channel. Their Git tags and GitHub Release pages,
where they exist, remain the record — see
[all releases](https://github.com/Chaitanysai/Spendsense/releases). Details have
deliberately not been reconstructed here, because release notes written after
the fact from incomplete evidence are worse than an honest gap.

## Compatibility

Every release under this changelog is signed with the same certificate:

```
42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367
```

That single fact is what makes in-place updates safe. An installed build accepts
an update only when the downloaded APK carries the same signing certificate, so
these releases upgrade over each other and over any earlier build from this
project, keeping the encrypted ledger. An APK signed with a different key — an
unofficial rebuild, or a "modded" copy — will be rejected by the installer, and
by the in-app updater, rather than replacing data with a build this project did
not sign.

Minimum requirements across these releases: Android 7.0 (API 24) or newer.

## OTA downloads

The OTA channel publishes the manifest that installed builds poll:

<https://spendsense-ota-2026.web.app/manifest.json>

Firebase Hosting serves the site as one release, and the publish pipeline
requires exactly one APK in the payload, so deploying a new build replaces the
previous APK file at its versioned path. The OTA channel therefore carries the
**current** build only — an older versioned URL like
`/releases/spendsense-2.0.24+49.apk` returns 404 once the next release deploys.
That is by design, and it is why GitHub Releases, not the OTA path, is the
durable archive.

To download whatever the channel currently serves, use the stable redirect:

<https://spendsense-ota-2026.web.app/releases/latest.apk>

It reads the live manifest and redirects to the exact APK that manifest names, so
it cannot go stale between releases.

## Verifying a download

```bash
sha256sum spendsense-2.0.25+50.apk
# 3c56d47d9634d8075c8405a2cf7ea2a5704df3a4090d6a6c44527d5432e90551
```

Installed builds perform these checks themselves — SHA-256, package name and
signing certificate — before handing a download to the system installer. The
trust model is documented in [docs/OTA_UPDATES.md](docs/OTA_UPDATES.md).
