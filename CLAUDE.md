# SpendSense — project notes

Flutter app with a static-hosted OTA update channel. Read
[docs/OTA_RELEASE_WORKFLOW.md](docs/OTA_RELEASE_WORKFLOW.md) before touching
anything under `.github/workflows/ota-publish.yml`, `tool/*ota*` or
`ota/`.

## Toolchain

Flutter stable 3.47.8 / Dart 3.13.7 is **not on `PATH`**. Invoke it by absolute
path:

```
E:\tools\flutter-3.47.8\flutter\bin\flutter.bat
```

## Conventions

- All money is integer paise (`amountMinor`). Never use floating point for an
  amount, a total or a budget figure.
- Shell is PowerShell. When piping Flutter's output, use
  `flutter analyze | cat` so the tool's own paging cannot swallow the result.
- Tests use `sqflite_common_ffi` (`sqfliteFfiInit()`), and set
  `AppTypography.debugSkipFontLoading = true`.
- A test file failing with `Connection closed before test suite loaded` is a
  known flake, not a real failure. Re-run that file alone.

## Things that will bite you

- **`firebase deploy` replaces the whole Hosting release.** The staging channel
  under `ota/public/staging/` is published by the same command as production, so
  it must be tracked in Git — a directory that exists only on the live site is
  dropped by the next deploy.
- **The APK's manifest URL is compiled in.** A staging build polls staging
  forever; promoting it to production is a rebuild at the same version with
  `channel: production`, never a file move.
- **`apksigner verify` is not redundant.** Gradle falls back to debug signing
  when no signing configuration is visible, and the manifest generator writes
  `signingCertSha256` from the pinned constant rather than from the artifact.
  Only the signature check catches that mismatch. Never relax the pin to make a
  build install.
- **Version monotonicity is checked in CI, not by the manifest validator.**
  `tool/validate_ota_manifest.dart` is deliberately offline; the comparison
  against the live manifest is `tool/check_ota_monotonicity.dart`, and it must
  keep mirroring `AppVersion.compareTo`. `sort -V` is not a substitute — it
  disagrees with the app on pre-release ordering and on rebuilds of the current
  version.
- **Both subtrees under `ota/public/` are published.** Adding a file anywhere
  below it publishes that file.
