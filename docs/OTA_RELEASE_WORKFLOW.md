# OTA release workflow

How a build becomes an update people can install. The trust model and the
manifest contract are in [OTA_UPDATES.md](OTA_UPDATES.md); this is the
operational path: what CI proves, what a human authorizes, and where the two
channels part company.

## The shape of a release

Two jobs, one gate between them.

```
build + validate  →  [ human authorization ]  →  deploy
```

CI never deploys. The `ota-publish` workflow is `workflow_dispatch` only, and
the deploy job runs under a GitHub Environment whose required reviewers are the
gate. Every check the build job runs is a refusal: if any of them fails, there
is nothing to authorize.

## Build and validate

Run from the release branch. `version` in `pubspec.yaml` is authoritative; the
workflow never rewrites it. If the version and the tag disagree, the run stops.

1. **Resolve the channel.** `channel` is a dispatch input, `production` by
   default. It sets one path prefix (`""` or `"staging"`) that the build, the
   manifest generation and the deploy all read from the same step output.
2. **Build.** `flutter build apk --release` with `OTA_MANIFEST_URL` compiled in
   for that channel. No manifest URL means the app makes no network request at
   all, which is what keeps debug and test builds quiet.
3. **Verify the signature.** `apksigner verify --print-certs` against the pinned
   SHA-256. This step exists because `android/app/build.gradle.kts` falls back to
   debug signing when no signing configuration is visible, and the manifest
   generator writes `signingCertSha256` from the *pinned constant*, not from the
   artifact. Without this check a debug-signed APK would be published carrying a
   manifest that claims the release certificate.
4. **Stage the payload.** Copy the APK into the channel's `releases/` directory
   under its version name, and remove any `latest.apk` left from before.
5. **Pre-flight the version.** `tool/check_ota_monotonicity.dart` compares the
   candidate against the manifest already live on *that channel* and refuses
   anything that is not strictly newer. See
   [OTA_UPDATES.md](OTA_UPDATES.md#version-monotonicity) for why this is a gate
   rather than a courtesy.
6. **Generate and verify the manifest.** `tool/generate_ota_manifest.dart`
   writes it from the verified APK; `tool/validate_ota_manifest.dart` re-reads
   the manifest against the APK it names. Both are offline by design — the live
   comparison is step 5's job.
7. **Assert the other channel was not touched.** A staging run must not have
   written the production manifest, or the reverse.
8. **Upload the payload** as the `ota-payload` artifact. The deploy job consumes
   that artifact, not a fresh checkout, so what is published is exactly what was
   validated.

The payload covers both channels at once. `firebase deploy` replaces the whole
Hosting release, so a staging publish also re-publishes production
byte-identically. That is idempotent and safe; it is also why the staging
directory must be tracked in Git — a directory that exists only on the live site
would be dropped by the next deploy.

## Human authorization

The deploy job is where a person takes responsibility. It:

- verifies the artifact is the one the build job validated (hash, version,
  channel),
- prints what it is about to publish,
- deploys `--only hosting,functions:downloadApk`,
- records the published version, channel and APK hash in the run summary.

`--only hosting` alone would publish the page while the download button fell
through to the 404 page, because `/releases/latest.apk` is a rewrite to the
`downloadApk` function.

Authorization is per-run and is never implied by a previous approval.

## Promotion: staging → production

A staging build is compiled against `/staging/manifest.json`, so it polls
staging forever. There is no file move that promotes it, and moving the APK
would produce an install that asks staging for its own updates.

To release what was tested:

1. Confirm the staging run passed and the staging version is the one to ship.
2. Dispatch `ota-publish` with `channel: production` from the same commit.
3. The version pre-flight now compares against the *production* manifest. A
   version that was newer than staging may not be newer than production.
4. Authorize the production deploy.

Same source commit, same version, new channel. If production is already at or
above the staging version, the pre-flight refuses — correctly, since publishing
would move production backwards or change nothing.

## Failure modes and what they mean

| Symptom | Cause |
|---|---|
| Publish succeeds, no device updates | Candidate not strictly newer than the live manifest for that channel. Step 5 should have caught it; check which manifest was compared. |
| `apksigner` mismatch | No signing configuration visible to Gradle; the APK is debug-signed. Never work around this by relaxing the pin. |
| Android refuses the install | Lower `versionCode` than the installed build. Android will not downgrade. |
| Pre-flight reports "no live manifest" | First publish on that channel — or a mistyped `OTA_BASE_URL`. Confirm the channel genuinely has never been published before trusting it. |

## Boundaries

- The workflow never fabricates a hash, signature, URL or version.
- The pinned certificate is the trust anchor and is not a build input.
- Release keys live in CI secrets. CI never prints them.
- A failed security check stops the release. It is never bypassed to finish one.
- Nothing here publishes on its own.
