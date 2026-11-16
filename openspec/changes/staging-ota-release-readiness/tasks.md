# Tasks: Staging OTA Release Readiness

Evidence convention: `[x]` means the result was observed. The line after each
completed task records how. A task that needs CI credentials, a dispatch, a
deploy or a device stays unchecked and says what is missing.

## Specification gate

- [ ] Obtain independent review of this OpenSpec package.
      Not done: this package has not had a review pass since the implementation.
- [ ] Resolve review findings; Code Reviewer confirms the revised package is
      internally consistent; obtain explicit implementation approval.
      Partially done: implementation review and QA of the validator/harness/
      `pr-build.yml` patch are complete (Code Reviewer PASS, QA PASS, both on
      the frozen bytes recorded below). The OpenSpec text itself has not had a
      separate review pass, and implementation approval is still a separate
      decision.

## Implementation

- [x] Enumerate the newest Firebase Hosting `DEPLOY` release through the
      Releases API; capture `/manifest.json` and every `/releases/*.apk`,
      verify API hash and size plus manifest references, and fail closed on
      unauthorized, missing, or mismatched files. Exclude generated `/__/firebase/*`
      and `/site/*` files.
      Evidence: `tool/capture_hosting_inventory.js` run against production found
      release `63cae69e71e11446` (2026-11-11T13:07:44.480Z) on the first page and
      captured `/manifest.json` (527 B) + `/releases/spendsense-2.0.25+50.apk`
      (65,373,753 B). Both `apiHashReproduced: true`.
      Completeness is compared against the API's own `version.fileCount`, not
      against counts derived from the same listing: the live capture recorded
      `declaredFileCount 23 === listedFileCount 23`, with `listedPages 1`,
      `activeFileCount 23`, and empty `inactivePaths`/`duplicatePaths`.
      The comparison is against the RAW paginated entries, before any status
      filter, because `fileCount` counts entries. A gate simulation showed that
      dropping 1 or 3 files, an absent `fileCount`, a non-integer `fileCount`
      and an understated `fileCount` each fail with
      `HOSTING_INVENTORY_FILE_COUNT_MISMATCH` or
      `HOSTING_INVENTORY_FILE_COUNT_MISSING`; a non-ACTIVE entry fails
      `HOSTING_INVENTORY_INACTIVE_FILE` and a repeated path fails
      `HOSTING_INVENTORY_DUPLICATE_PATH`, both after the raw count passes, so a
      healthy version with a duplicate or stale entry is not misreported as a
      count mismatch. `/releases/latest.apk` is excluded
      as a Hosting rewrite (`HOSTING_INVENTORY_RESERVED_PATH`).
      Per-file size is not exposed by the API; the manifest's `sha256` and
      `downloadUrl` remain the authority for APK bytes.
- [x] Run a read-only Hosting API credential preflight before inventory
      retrieval and report a named failure without invoking deployment.
      Evidence: `--preflight` performs a real releases read and, for the newest
      live `DEPLOY`, one page of `versions/{id}/files`, so a token with
      releases-read but no files-read fails here rather than after the APK is
      signed. Live run: `releases_readable=true files_readable=true
      version=63cae69e71e11446 files_on_first_page=23`.
      A missing token exits `HOSTING_INVENTORY_AUTH_MISSING`; an invalid token
      exits `HOSTING_INVENTORY_AUTH_INVALID` (with the OAuth error code). The
      token value never appears in output (checked by grep in the fixture suite).
      Not verified: the CI `FIREBASE_TOKEN` itself; this used the local developer
      login.
- [x] Upload the validated production baseline as `release-recovery` with
      90-day retention before any deploy; document retrieval and integrity checks.
      Evidence: validate uploads `ota/recovery-baseline` (manifest, APKs,
      `inventory.json`, `SHA256SUMS`) with `if-no-files-found: error` and
      `retention-days: 90`; deploy downloads the same artifact and verifies it
      against `SHA256SUMS` before comparing. A live capture produced
      `inventory.json` + `SHA256SUMS` that `sha256sum --check --strict` passes.
      Documented in `docs/release/staging-ota-restore.md`.
- [x] Create `docs/release/staging-ota-restore.md` with artifact owner/location,
      retention, checks, and separately authorized recovery steps.
      Evidence: file exists; covers owner (release manager for the publishing
      run), location (Actions artifact), retention (90 days, repository cap, and
      what happens after it), retrieval, integrity checks, redeploy restore and
      channel-rollback restore.
- [x] Update `.github/workflows/ota-publish.yml` with production baseline capture,
      byte/hash checks, complete payload handoff, and channel-aware verification.
      Evidence: restore step copies production bytes into `ota/public` before the
      staging manifest is written; verification is manifest-driven; deploy
      downloads `release-recovery` and compares against it; post-deploy asserts
      published version, sha256, channel path, APK reachability and the
      `/releases/latest.apk` redirect. A staging run also compares live
      production's manifest to the captured baseline and requires 200 for the
      production APK and `/legal/`; the block was exercised against the live
      site, passing with the real baseline and failing
      `PRODUCTION_MANIFEST_ALTERED` with a mutated one. The production APK is
      fetched and hashed, not merely status-checked: against live production the
      downloaded 65,373,753-byte APK hashed to the baseline `sha256`
      (`3c56d47d9634…`), and a mutated baseline failed
      `PRODUCTION_APK_ALTERED`. The redirect loop no
      longer ends the step early: production checks run first and it is the
      last success path, using `--max-redirs 0`. 11 shell scenarios reproduced the gate:
      restored payload passes; unrestored, deleted, altered APK, overwritten
      manifest, missing metadata, corrupt baseline, absent artifact and empty
      baseline all fail closed.
- [x] Keep `tool/validate_yaml.js` limited to structural workflow assertions;
      add executable behavioral checks in the workflow/test harness as needed.
      Evidence: `validate_yaml.js` now identifies the payload by hosting path
      and asserts the `release-recovery` upload/download pair. It parses 11 YAML
      files and passes. It was run with a local `yaml` shim because the module is
      not installed in this checkout; no dependency was added to the repository.
- [ ] Correct `docs/OTA_RELEASE_WORKFLOW.md`, `docs/OTA_UPDATES.md`,
      `ota/README.md`, and `ota/public/staging/.gitkeep` wording.
      Partially done: the signing job's `environment: release` gate is restored,
      so the workflow now matches the documented approval model. The remaining
      prose corrections to the three docs are not in this change and stay open.
- [x] Add `docs/release/staging-ota-test.md` with release and device criteria.
      Evidence: file exists with preconditions, C1-C23 release criteria mapped to
      the named failure codes, and D1-D6 device criteria.
- [x] Make the pre-publish APK digest check in `ota-publish.yml` a hard
      structural requirement, and run it from PR builds.
      Evidence: `digestGuard` in `tool/validate_yaml.js` no longer matches any
      `sha256sum` + `manifest.json` pair. It stays fail-closed on: comment lines
      being dropped for every match; exactly one deploy step (a line running
      `npx … firebase-tools… deploy` or `firebase deploy`, with `[ \t]` rather
      than `\s` so a block cannot match as one line); and one run block that
      hashes `"$APK"` into `SHA`, greps that `$SHA` out of
      `"$DIR/manifest.json"`, and states the refusal wording
      `does not carry the sha256`. The `DIR` that grep reads is the last
      `DIR=` assignment before the grep line (a later assignment does not
      count), and its `${SUBDIR:+/$SUBDIR}` suffix is stripped and compared for
      equality with the hosting directory from `firebase.json` — so
      `ota/publicx`, `ota/public-backup` and `ota/elsewhere` all fail, not just
      a path that differs by prefix. A literal path such as
      `ota/recovery-baseline/manifest.json`, a `DIR` that is not exactly the
      hosting directory, or a block with no resolvable `DIR` does not qualify.
      The guard step must be strictly earlier than the single deploy step, or,
      when it is the deploy step itself, its digest refusal must come before the
      deploy line. The failure message is `no deploy step re-checks the payload
      APK digest against ota/public/manifest.json before publishing`.
      `tool/test_validate_yaml_ota_guard.js` copies `ota-publish.yml` into a temp
      tree and runs the validator with `YAML_ROOT` set to it; each case records
      whether the mutant parsed and what rejected it. Seventeen cases, all 17
      pass on the current validator:
      authentic → pass; guard block removed → digest guard; only the
      recovery-baseline checksum remains → digest guard; guard moved to a later
      step after the deploy → digest guard; a decoy step resolving its own
      `$DIR` → accepted (known limitation, below); guard grepping
      `ota/recovery-baseline/manifest.json` → digest guard; guard step with no
      resolvable `DIR` → digest guard; guard step whose `DIR` is
      `ota/elsewhere` → digest guard; stray `DIR_BACKUP=`/`export DIR=` lines
      before the payload `DIR` → pass (the later payload assignment is the one
      the grep reads); `DIR="ota/publicx"` → digest guard;
      `DIR="ota/public-backup"` → digest guard; a second deploy command added
      after the guard refusal → the unique-deploy rule; a guard inside the
      deploy step before the deploy line → pass; a guard inside the deploy step
      after the deploy line → digest guard; refusal wording removed → digest
      guard; unrelated `sha256sum` + `manifest.json` only → digest guard;
      malformed YAML → parse, labelled `other` by the harness because that
      failure has no line:column parse message (by design).
      Under the previous loose predicate (`sha256sum` + `manifest.json`
      substring match) the guard-specific cases are accepted; the exact count
      depends on the harness fixture and was not reproducible across
      independent rebuilds, so it is not stated here. Known structural
      limitation: the validator requires a guard step that verifies `$APK`
      against the payload manifest through its own `DIR` and precedes the single
      deploy step; a separate step that re-derives the same `DIR` and performs
      that same check is indistinguishable from the assert step the deploy
      consumes, so that case is accepted by design. That accepted limitation is
      checked at the line-text level only — the case asserts the decoy's own
      lines still hash `$APK` and grep `$DIR/manifest.json` — and the harness
      fails if it stops verifying `$APK` (checked with
      `OTA_GUARD_WEAKEN_DECOY=1`); it does not prove the decoy's shell would run
      correctly. Holding a
      `node_modules` copy locally for this run is ignored by `.gitignore`; PR
      builds install `yaml` themselves. `.github/workflows/pr-build.yml` now
      lists `tool/validate_yaml.js`, `tool/test_validate_yaml_ota_guard.js`,
      `tool/validate_ota_manifest.dart`, `tool/capture_hosting_inventory.js` and
      `tool/check_ota_monotonicity.dart`, and runs the guard test after the YAML
      validation step. Observed in CI: PR #56 run 43823791665 (Release Branch
      CI, `build` job): `OK: 11 YAML file(s)` and `OK: 17 OTA guard case(s)`.
      PR Build's copy of the same step has not run on this change.

## Verification

- [x] Run narrow static workflow/configuration checks first.
      Evidence: `node --check` on both changed scripts; PyYAML parse of 11 YAML
      files (0 failures); `node tool/validate_hosting_headers.js` exit 0;
      `node tool/validate_yaml.js` exit 0 (11 files) and
      `node tool/test_validate_yaml_ota_guard.js` exit 0 (17 cases), both run
      locally with an npm-installed `yaml` in the git-ignored `node_modules`.
- [x] Run OTA, hosting-header, redirect, and relevant unit tests.
      Partially done: hosting-header validation passes. The inventory fixture
      suite (7 cases) and the gate suite (11 cases) pass. The OTA Dart test suite
      was not run: `dart run` fails in this workspace with `Invalid SDK hash`.
      `dart tool/validate_ota_manifest.dart` was executed directly instead and
      passed all 5 `--expect-path` cases.
- [ ] Obtain independent code review.
      Partially done: Code Reviewer PASS on the narrow validator patch
      (`tool/validate_yaml.js` `1DF4BA9C…`, harness `C987647B…`,
      `pr-build.yml` `A6189EE3…`, `ota-publish.yml` `E8AA5978…` unchanged),
      checked against its own mutant set. The earlier M1-M3 recovery work was
      reviewed separately and also passed. The OpenSpec package text is not
      covered by that review.
- [ ] Obtain QA evidence for local and CI checks.
      Partially done: QA PASS on local evidence for the validator patch
      (17/17 harness cases, critical guard-removal reproduction failing closed,
      independent escape probes caught). CI evidence does not exist, because no
      workflow was dispatched.
- [ ] Release Manager obtains authorized read-back evidence for release-branch
      required checks and Environment reviewers; missing evidence blocks release.
      Blocked: `release/2.0.26+51` is unprotected and the `release` environment
      has no required reviewers. Administrative, not a code change.
- [ ] With separate authorization, run validation only; do not deploy yet.
      Not done: no dispatch authorized.
- [ ] With separate deployment authorization, execute staging deployment and
      collect production/staging URL and byte-preservation evidence.
      Not done: no deploy authorized.
- [ ] Complete physical-device installation and in-app OTA criteria.
      Not done: no device evidence.

## Release handoff

- [x] Report remaining blockers separately from implementation/test results.
      Evidence: the consolidated report was posted after Code Review, QA and
      release-scope checks passed, with blockers listed apart from
      implementation and validation results.
- [ ] Do not promote to production without a separately authorized production
      rebuild and approval.
      Standing constraint; unchanged.
