# Exclusions / corrections — SpendSense

The MIT grant in `LICENSE` covers original SpendSense source on `main`.
Listing a file here does not grant rights, change ownership, or make a
third-party file MIT-licensed.

## Excluded material

No third-party code, image, logo, font, sound, or bundled asset was found on
`main` that requires exclusion from the MIT grant. Platform template files are
covered by the BSD-3-Clause notices in THIRD_PARTY_NOTICES.md rather than by
this repository's MIT grant.

The sound assets on `release/2.0.13+38` are project-original CC0 1.0 files and
are not excluded; they are not on `main` at audit time. Any future third-party
asset merged from a release branch must be reviewed and added here first.

## Required corrections before applying the LICENSE (not exclusions)

These are `flutter create` placeholders, not real third-party copyright claims:

- `macos/Runner/Configs/AppInfo.xcconfig`:
  `PRODUCT_COPYRIGHT = Copyright © 2026 com.example. All rights reserved.`
- `windows/runner/Runner.rc`:
  `VALUE "LegalCopyright", "Copyright (C) 2026 com.example. All rights reserved."`
- `macos/Runner/Info.plist` `NSHumanReadableCopyright` resolves via
  `$(PRODUCT_COPYRIGHT)` and inherits the same placeholder.

The placeholder copyright strings have been replaced with the verified
copyright line. Bundle identifiers and `CompanyName` values were left
unchanged because they are application identifiers, not copyright claims.

## Provenance note

The 2026-03-31 commit `5b1237c3` ("Initial clean import", 152 files) is
authored by the repository owner and contains the stock Flutter template plus
first-party code; no external upstream license declaration was found. The 30
commits by `rhoggs-bot-test-account` are covered by the repository owner's
attestation of control and direction; that attestation is not independent
identity verification.
