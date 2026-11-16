# Design: Staging OTA Release Readiness

## Payload flow

1. Validate resolves one channel and derives one directory prefix.
2. For staging, capture the live production manifest and every APK in the live
   production release inventory into the production paths of `ota/public`.
3. Verify every downloaded APK against its manifest/inventory hash and capture
   immutable manifest, inventory, and APK byte hashes in the validate artifact.
4. Build and validate the staging APK and manifest under `ota/public/staging`.
5. Upload the complete `ota/public` tree as the sole deploy artifact.
6. Deploy downloads that artifact and compares its production files against the
   baseline captured by validate, not a fresh live download, then publishes only
   after all checks pass.

## Verification

Post-deploy checks derive URLs from the selected channel and manifest, rather
than hard-coding production. Staging checks must prove the staging manifest is
reachable, references `/staging/releases/`, and serves the expected APK. The
production baseline must remain byte-identical after a staging deployment.

## Approval model

Only the deploy job uses a GitHub Environment with required reviewers; validate
must remain runnable without deployment approval. The release
branch requires the configured CI/security checks. Repository configuration is
treated as external release work and is verified by read-back evidence; source
YAML alone is not evidence that protection or reviewers are active.

## Security boundaries

- Never print credentials, keystore contents, or API keys.
- Keep the certificate pin and signature verification unchanged.
- Refuse missing, malformed, non-HTTPS, mismatched, or ambiguous artifacts.
- Do not silently accept a missing live staging manifest except when the
  workflow explicitly identifies and authorizes a first publish.
- Do not use a staging artifact as a production artifact; promotion is a
  production-channel rebuild.
- Retain the captured baseline as a retrievable artifact before deployment. If
  post-deploy checks fail, stop release progression and use the separately
  authorized Firebase restore procedure.

## Files expected to change

- `.github/workflows/ota-publish.yml`
- `tool/validate_yaml.js`
- `docs/OTA_RELEASE_WORKFLOW.md`
- `docs/OTA_UPDATES.md`
- `docs/release/staging-ota-test.md` (new)
- `ota/README.md`
- `ota/public/staging/.gitkeep`

GitHub branch protection and Environment reviewer configuration are external
administrative actions, not repository-file changes.
