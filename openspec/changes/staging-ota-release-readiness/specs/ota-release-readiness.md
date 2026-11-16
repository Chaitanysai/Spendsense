# OTA Release Readiness Specification

## P0 — Production asset preservation

### Requirement: staging payload preserves production assets

When a staging deployment is prepared, the payload MUST contain the live
production `manifest.json` and every APK in the live production release tree,
at the production paths. Validate MUST capture this complete inventory and its
byte/hash baseline into the same retained artifact used for deployment.

#### Scenario: production baseline is available

- GIVEN the live production manifest and release inventory are reachable
- WHEN staging validation assembles the deployment payload
- THEN it downloads the manifest and every inventoried APK
- AND verifies each manifest-referenced APK SHA-256
- AND records byte hashes for the manifest, inventory, and every APK
- AND fails closed on any mismatch or missing file

### Requirement: deploy artifact is revalidated

Before Firebase deployment, the deploy job MUST re-check that the downloaded
artifact contains the validated production files and staging files, and MUST
compare every production byte against the baseline captured by validate. It
MUST NOT use a fresh live download as the equality authority.

#### Scenario: artifact is incomplete or altered

- WHEN any required production or staging file is absent or altered
- THEN deployment MUST stop before Firebase is invoked

### Requirement: post-deploy preservation evidence

Before deployment, the complete baseline MUST be retained as a retrievable
artifact with a documented restore procedure. After an authorized staging
deployment, verification MUST prove the production manifest and every
inventoried production APK remain byte-identical. If any check fails, the
workflow MUST fail the release, prevent promotion, retain evidence, and direct
the separately authorized restore procedure.

### Requirement: staging client identity decision

Before physical-device acceptance, the release owner MUST record whether the
shared Android application/Firebase identity can safely coexist with production
on the test device. If it cannot, staging MUST use a separately configured
Firebase Android app/package identity or an explicitly approved isolated-device
strategy.

## P1 — Approval gates

### Requirement: protected release branch

The release branch MUST require the documented CI and security checks before
merge or release readiness is considered complete.

### Requirement: genuine environment approval

The deploy job MUST pause on a GitHub Environment configured with at least one
required reviewer. A YAML `environment` declaration alone MUST NOT be treated
as proof; release evidence MUST include GitHub configuration/read-back or a
workflow approval event.

The Release Manager owns this pre-condition and MUST record read-back evidence
for the release branch required checks and Environment reviewers. Missing
evidence blocks implementation acceptance and staging deployment.

### Requirement: no implicit authorization

Validation, approval, deployment, signing, and publication MUST remain distinct
actions. A successful validation run MUST NOT deploy without the environment
approval and explicit deployment intent.

## P2 — Channel-aware verification

### Requirement: selected-channel URLs

All manifest, APK, redirect, and post-deploy checks MUST derive their target
paths from the selected channel. Staging MUST verify `/staging/manifest.json`
and `/staging/releases/...`; production MUST verify the root paths.

### Requirement: compiled URL matches manifest URL

The generated manifest URL, manifest download URL, staged path, and compiled
`OTA_MANIFEST_URL` MUST identify the same channel.

## P2 — Documentation accuracy

### Requirement: operational documentation matches implementation

Documentation MUST describe the complete payload handoff, production
preservation checks, reviewer gate, channel-specific verification, and the
fact that staging-to-production promotion requires a production rebuild.

### Requirement: device test procedure

Documentation MUST define clean staging installation, in-app OTA installation,
signature compatibility, version checks, data preservation, abort criteria, and
evidence capture.

## Testing and security acceptance

- `node tool/validate_yaml.js` exits 0 and reports all workflow documents valid;
  its OTA assertions remain structural only.
- `node tool/validate_hosting_headers.js` exits 0 and the redirect test suite
  reports 11/11 passing.
- The OTA manifest and monotonicity test commands exit 0.
- No secrets are printed or committed.
- APK signature pin verification remains mandatory.
- CI evidence contains the retained validate baseline and deploy-side `cmp`/hash
  results for every production APK.
- Authorized staging verification returns HTTP 200 for the staging manifest and
  expected APK, with staging paths in both URLs, while production manifest and
  every inventoried APK match the baseline bytes.
- Physical-device test confirms install, update, launch, identity coexistence,
  and data retention.
