# OTA hosting directory

`firebase.json` at the repository root points Firebase Hosting at
`ota/public/`. Only generated release files belong there:

```
ota/public/
├── manifest.json                              # generated from the signed APK
└── releases/
    ├── spendsense-2.0.0+20.apk                # immutable, versioned
    └── spendsense-2.0.0+20.apk.sha256         # optional checksum sidecar
```

`manifest.json` and the APKs are **generated artifacts** and are ignored by
git. They are produced by the release workflow (or locally with
`tool/generate_ota_manifest.dart`) from an APK that has already passed signature
and SHA-256 verification.

Nothing in this directory is committed or deployed without explicit
authorization. See `docs/OTA_UPDATES.md` for the full process.
