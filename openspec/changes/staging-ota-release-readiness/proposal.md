# Proposal: 2.0.26+51 Staging OTA Release Readiness

## Goal

Make the staging OTA pipeline safe for a real-device installation test without
deleting or changing the live production OTA manifest or APK.

## Scope

- Preserve and verify the live production manifest and referenced APK in every
  staging deployment payload.
- Require protected release-branch checks and genuine GitHub Environment
  reviewer approval before deployment.
- Verify URLs and artifacts for the selected channel, especially staging.
- Correct workflow and release documentation so it describes the actual gates.
- Define local, CI, live-host, security, and physical-device acceptance tests.
- Preserve the complete live production release inventory, including historical
  APKs still served by Hosting.

## Out of scope

- Application behavior unrelated to OTA.
- APK signing-key changes or signing-key access.
- Production deployment, staging deployment, workflow dispatch, Firebase
  changes, commits, pushes, or GitHub settings changes during implementation.
- Moving a staging APK into the production path; promotion remains a rebuild
  compiled with the production manifest URL.

## Risks addressed

Firebase Hosting replaces the whole hosted tree. A staging payload assembled
from a fresh checkout can omit the live production manifest and APKs, breaking
updates for existing production installs. The deploy job also currently checks
the production download route even when publishing staging.

The staging client identity is an explicit decision: determine whether the
shared Android application/Firebase identity can coexist with production on a
test device, or require a separate staging Firebase Android app/package.

## Approval gates

Implementation requires approval of this specification. GitHub branch
protection, Environment reviewers, workflow dispatch, signing, deployment, and
OTA publication each require their own authorization.
