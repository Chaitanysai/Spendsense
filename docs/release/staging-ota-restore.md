# Restoring production after a bad or partial Hosting publish

`firebase deploy` replaces the **entire** Hosting release. A staging publish
republishes production's files too, so a staging run that is missing production
bytes silently deletes production's `manifest.json` and APK. That is the failure
this document recovers from.

## The recovery artifact

| Property | Value |
|---|---|
| Artifact name | `release-recovery` |
| Produced by | the `validate` job of `.github/workflows/ota-publish.yml`, staging channel only |
| Contents | `manifest.json`, `releases/*.apk` (the live production payload), `inventory.json`, `SHA256SUMS` |
| Location | GitHub Actions artifact on the run that deployed: repository → **Actions** → the run → **Artifacts** |
| Retention | **90 days requested** (`retention-days: 90`). The account's effective maximum is not verified: the repository retention-policy endpoint returns 404, so GitHub may shorten it. Treat 90 days as an upper bound and confirm on the first run that publishes a baseline |
| Owner | the release manager for the run that published it |
| Capture timing | before the staging payload is assembled, so it records production as it was **before** the deploy |

`inventory.json` records the Hosting release it came from (`release.versionId`,
`release.releaseTime`), the file list with per-file sizes and digests, and the
manifest fields. `SHA256SUMS` covers every captured file and is what the deploy
job verifies before it publishes.

### The retention limit is a correctness property

The Hosting API cannot return historical file bytes
(`/versions/{id}/files/{path}` returns 404) and exposes no per-file size. The
artifact is therefore the **only** offline copy of what production served. Once
it expires there is no recovery path through the API. To keep it available
longer, download it and store it somewhere with its own retention; do not rely
on the artifact surviving 90 days.

## Retrieve the artifact

1. Open the repository's **Actions** tab and select the `OTA Publish` run that
   performed the deploy.
2. Download **`release-recovery`**.
3. Verify it before trusting it:

   ```sh
   cd release-recovery
   sha256sum --check SHA256SUMS
   ```

4. Confirm the manifest still describes the APK in the archive:

   ```sh
   node -e '
     const m = require("./manifest.json");
     const u = new URL(m.downloadUrl);
     console.log(u.pathname, m.sha256, m.latestVersion + "+" + m.latestBuildNumber);
   '
   sha256sum releases/spendsense-2.0.25+50.apk
   ```

   The second digest must equal the manifest's `sha256`. They are both raw
   digests of the APK bytes. Never substitute the Hosting API's per-file hash:
   that is a digest of the gzip upload stream.

## Restore

Restoring is a **separately authorized production write**. It needs explicit
approval under the channel's approval rule; a recovery artifact existing is not
approval to use it.

### Option A — redeploy the captured payload (preferred)

Republishes exactly the captured bytes through the normal path.

1. Check out the repository at the run's commit.
2. Create `ota/public/releases/` and copy in the captured files:

   ```sh
   mkdir -p ota/public/releases
   cp release-recovery/manifest.json ota/public/manifest.json
   cp release-recovery/releases/*.apk ota/public/releases/
   # SHA256SUMS paths are relative to the archive root, which is the payload
   # root: verify it from ota/public.
   ( cd ota/public && sha256sum --check --strict ../../release-recovery/SHA256SUMS )
   ```

3. Deploy hosting only, with the production token, from a protected branch:

   ```sh
   npx --yes firebase-tools@13.35.1 deploy --only hosting \
     --project spendsense-ota-2026 --non-interactive
   ```

4. Verify: `/manifest.json` serves the captured `latestVersion`/`sha256`, the
   APK at `downloadUrl` returns 200, and `/releases/latest.apk` redirects to it.

### Option B — roll the live channel back to a retained version

Use this only when Option A cannot run. The API can point the live channel at a
version that is still retained; it cannot fetch that version's bytes.

```sh
# 1. List releases, newest first, and find a DEPLOY from before the bad publish.
TOKEN=$(... a short-lived OAuth access token with the firebase scope ...)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://firebasehosting.googleapis.com/v1beta1/projects/spendsense-ota-2026/sites/spendsense-ota-2026/channels/live/releases?pageSize=20"

# 2. Create a release on the live channel pointing at that version.
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"type":"ROLLBACK","version":{"name":"projects/spendsense-ota-2026/sites/spendsense-ota-2026/versions/<id>"}}' \
  "https://firebasehosting.googleapis.com/v1beta1/projects/spendsense-ota-2026/sites/spendsense-ota-2026/channels/live/releases"
```

Then verify the same three facts as Option A. A rollback restores the site's
tree; it does **not** undo the function deployment.

## What must be true afterwards

- `/manifest.json` serves the intended `latestVersion`, `latestBuildNumber` and
  `sha256`, and `downloadUrl` names an APK that is actually served.
- `/releases/latest.apk` redirects to a versioned APK.
- The page chrome (`/`, `/legal/`, `/site/assets/*`) is intact.
- An installed build reads the manifest and offers the intended version.

## Why this matters for the next staging run

If any staging publish omits the captured production bytes, production is
deleted. The workflow now refuses to publish in that case:

- `HOSTING_INVENTORY_*` failures stop the run before the payload exists.
- `PRODUCTION_ASSET_MISSING` / `PRODUCTION_ASSET_ALTERED` stop it after the
  restore step.
- `PRODUCTION_MANIFEST_ALTERED` stops it if the staging manifest overwrote
  production's own file, and again after deploy if live production no longer
  matches the baseline.
- `HOSTING_INVENTORY_METADATA_MISMATCH` stops it if the artifact does not match
  its `SHA256SUMS`.
- `PRODUCTION_MANIFEST_GONE`, `PRODUCTION_APK_GONE`, `PRODUCTION_APK_ALTERED`
  and `PRODUCTION_PAGE_GONE` stop it when a staging deploy has already removed
  or changed production's manifest, APK bytes or `/legal/` pages. The APK is
  downloaded and hashed against the baseline `sha256`, so a truncated or
  replaced body is caught as well as a missing file. These run after the deploy,
  so recovery is the only remaining action; see the restore steps above.

If a run fails on any of these, fix the cause. Deploying without them publishes
a site that deletes production.
