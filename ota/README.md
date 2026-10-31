# OTA hosting directory

The static site in `ota/public/` is what installed builds read for updates.
`firebase.json` points the hosting configuration at this directory.

Generated layout:

```
ota/public/
├── manifest.json                              # generated from the signed APK
└── releases/
    ├── spendsense-<version>+<build>.apk       # immutable, versioned
    └── spendsense-<version>+<build>.apk.sha256 # optional checksum sidecar
```

`manifest.json` and the APKs are generated artifacts and are ignored by Git.
They are produced by the release workflow, or locally with
`tool/generate_ota_manifest.dart`, from an APK that has already passed signature
and SHA-256 verification.

See [docs/OTA_UPDATES.md](../docs/OTA_UPDATES.md) for the trust model and
publishing process.
