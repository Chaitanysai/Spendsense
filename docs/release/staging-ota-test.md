# Staging OTA test plan

Covers a staging publish of the OTA channel: what must be true before dispatch,
what to check on the live site after it, and what to check on a device.

See [staging-ota-restore.md](staging-ota-restore.md) for recovery and artifact
handling.

## Preconditions

| # | Condition | Evidence |
|---|---|---|
| P1 | The release branch is protected and the `release` environment has required reviewers | GitHub settings read-back, recorded by the release manager |
| P2 | The `release/2.0.26+51` branch is protected | branch protection read-back |
| P3 | `FIREBASE_TOKEN` is a valid CI credential | the `Preflight read-only Hosting inventory access` step passes |
| P4 | Live production serves 2.0.25+50 and its APK is downloadable | `/manifest.json` + `HEAD` on `downloadUrl` |
| P5 | The workflow diff has independent review and QA sign-off | review and QA reports |

Anything missing blocks the dispatch. Do not work around P1-P3 in the workflow.

## Release criteria — staging dispatch

Run with `channel=staging`, `minimum_version=<current>`, and `confirm=deploy`
only after the deployment approval. The `validate` job must fail closed if any
step below fails.

### Inventory capture

| # | Check | Failure code if wrong |
|---|---|---|
| C1 | The token exchanges for an access token; no token appears in the log | `HOSTING_INVENTORY_AUTH_INVALID` |
| C2 | The preflight proves both releases-read and files-read against the newest `DEPLOY` version | `HOSTING_INVENTORY_UNAUTHORIZED` |
| C3 | The newest `DEPLOY` release is found after paginating | `HOSTING_INVENTORY_NO_DEPLOY` |
| C4 | The live version has `/manifest.json` and at least one `/releases/*.apk` | `HOSTING_INVENTORY_NO_MANIFEST`, `HOSTING_INVENTORY_NO_APK` |
| C5 | The APK the manifest names is in the version and is captured | `HOSTING_INVENTORY_APK_NOT_IN_VERSION` |
| C6 | The captured APK's raw SHA-256 equals the manifest's `sha256` | `HOSTING_INVENTORY_APK_HASH_MISMATCH` |
| C6a | The raw paginated entry count equals `version.fileCount`, before any status filter | `HOSTING_INVENTORY_FILE_COUNT_MISMATCH`, `HOSTING_INVENTORY_FILE_COUNT_MISSING` |
| C6b | No path is listed twice, and no entry is non-ACTIVE | `HOSTING_INVENTORY_DUPLICATE_PATH`, `HOSTING_INVENTORY_INACTIVE_FILE` |
| C7 | `inventory.json` and `SHA256SUMS` exist and the sums verify | `HOSTING_INVENTORY_NO_METADATA`, `HOSTING_INVENTORY_METADATA_MISMATCH` |

`GET /__/firebase/init.js` and `init.json` appear in the API file list but are
generated at serve time. They are counted, not captured. A run that tries to
fetch them fails.

### Payload preservation

| # | Check | Failure code |
|---|---|---|
| C8 | Production `manifest.json` and the APK are copied into `ota/public` at their production paths **before** the staging manifest is written | `HOSTING_INVENTORY_NO_BASELINE` |
| C9 | The payload's production files are byte-identical to the capture | `PRODUCTION_ASSET_MISSING`, `PRODUCTION_ASSET_ALTERED` |
| C10 | The staging manifest is written to `/staging/manifest.json`, never to `/manifest.json` | `PRODUCTION_MANIFEST_ALTERED` |
| C11 | The staging manifest's `downloadUrl` lives under `/staging/releases/` | validator `--expect-path` |
| C12 | The staging APK's digest matches the staging manifest | validator |
| C13 | The staging version advances the staging manifest (a 404 on `/staging/manifest.json` counts as a first publish) | monotonicity tool |

### Deploy gate

| # | Check | Failure code |
|---|---|---|
| C14 | The deploy job downloads `release-recovery` | `HOSTING_INVENTORY_NO_BASELINE` |
| C15 | The artifact matches its `SHA256SUMS` | `HOSTING_INVENTORY_METADATA_MISMATCH` |
| C16 | The baseline holds at least one production APK | `HOSTING_INVENTORY_NO_APK` |
| C17 | Every baseline APK is present in the payload and byte-identical | `PRODUCTION_ASSET_MISSING`, `PRODUCTION_ASSET_ALTERED` |

The comparison is against the captured artifact, not a fresh download, so it
still holds if production changes between validate and deploy.

### Post-deploy

| # | Check |
|---|---|
| C18 | `/staging/manifest.json` serves this run's `latestVersion`, `latestBuildNumber` and `sha256` |
| C19 | Its `downloadUrl` is under `/staging/releases/` and ends in `.apk` |
| C20 | That URL returns 200 |
| C21 | `/manifest.json` still serves the captured production version and digest | `PRODUCTION_MANIFEST_GONE`, `PRODUCTION_MANIFEST_ALTERED` |
| C21a | The production APK's downloaded bytes hash to the baseline `sha256` | `PRODUCTION_APK_GONE`, `PRODUCTION_APK_ALTERED` |
| C21b | `/legal/` and `/legal/style.css` return 200 | `PRODUCTION_PAGE_GONE` |
| C22 | `/releases/latest.apk` still redirects to a versioned APK | `DOWNLOAD_LINK_BROKEN` |
| C23 | `/`, `/legal/`, and every `/site/assets/*` referenced by `index.html` still return 200 |

## Device criteria

Run on a physical device with a production 2.0.25+50 install.

| # | Check | Expected |
|---|---|---|
| D1 | Installed app checks production | sees 2.0.25+50, no update offered |
| D2 | Build with `--dart-define=OTA_MANIFEST_URL=https://spendsense-ota-2026.web.app/staging/manifest.json` | offers 2.0.26+51 |
| D3 | Install from the staging manifest | signature verifies against the pinned certificate; install completes |
| D4 | Relaunch the staging build | reports 2.0.26+51, no update offered |
| D5 | Open the staging build while the production manifest is served | does not offer to go backwards |
| D6 | A build pointed at a tampered staging manifest (wrong `sha256`) | refuses to install |

D6 is destructive-testing only: use a scratch device or emulator.

## Not covered here

- Branch protection and environment reviewers: administrative, tracked by the
  release manager.
- CI credential validity: proven only by the preflight step actually passing.
- Production promotion: a separate, separately authorized production rebuild.

## Evidence to capture

For each criterion: the step name, its result, and the run URL. A criterion
without a step result is not evidence. Do not claim device results that were
not observed on the device.
