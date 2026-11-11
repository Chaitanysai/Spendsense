# OTA hosting directory

The static site in `ota/public/` is what installed builds read for updates.
`firebase.json` points the hosting configuration at this directory.

Generated layout:

```
ota/public/
├── manifest.json                              # generated from the signed APK
├── releases/
│   ├── spendsense-<version>+<build>.apk       # immutable, versioned
│   └── spendsense-<version>+<build>.apk.sha256 # optional checksum sidecar
└── staging/                                   # the staging channel, same shape
    ├── manifest.json
    └── releases/
```

`staging/` carries the `.gitkeep` placeholders only. It must stay *tracked*:
`firebase deploy` uploads what is in the checkout, so a directory that exists
only on the live site is absent from the next release.

`manifest.json` and the APKs are generated artifacts and are ignored by Git.
They are produced by the release workflow, or locally with
`tool/generate_ota_manifest.dart`, from an APK that has already passed signature
and SHA-256 verification.

## The landing page's download link

`/releases/latest.apk` is not a file. It is a Hosting rewrite (see
`firebase.json`) to the `downloadApk` function in `backend/download_redirect/`,
which reads `manifest.json` and redirects to the APK that manifest names. A new
version therefore updates the download button with no page edit and no rebuild,
and the button can never advertise a different build from the one the in-app
updater installs. The function re-checks the manifest's URL — https, this exact
host, `.apk` path — before redirecting, and answers 502 rather than guessing.

Because the rewrite needs the function, the publish workflow deploys with
`--only hosting,functions:downloadApk`. A plain `--only hosting` deploy
publishes the page while the button falls through to the 404 page.

See [docs/OTA_UPDATES.md](../docs/OTA_UPDATES.md) for the trust model and
publishing process.

## Caching

`firebase.json` gives the content-hashed bundles under `/site/assets/` and the
version-named APKs under `/releases/` a one-year `immutable` policy, and makes
every HTML entry point (including `/` and `/legal/`) plus `manifest.json`
revalidate on each request. The download redirect stays `no-store`. The staging
channel repeats both rules under `/staging/`; `/releases/spendsense*.apk` does
not match the nested path, so it needs its own entries.

There is deliberately no catch-all rewrite: Hosting's own 404 handling serves
`404.html` with a real 404 status, so a request for a bundle an old page still
references cannot return a cacheable `200`. Measured live, a stale hashed URL
answers `404` with `no-cache` — it is not cached.

The policy is checked by `tool/validate_hosting_headers.js`, which runs in
`pr-build`, in `release-branch-ci`, and immediately before every publish in
`ota-publish`. Verification readings and the reasoning are in
[docs/hosting-cache-headers.md](../docs/hosting-cache-headers.md).
