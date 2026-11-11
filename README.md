# SpendSense

SpendSense is an offline-first expense tracker for Android. It reads bank and
UPI transaction messages from the device inbox, parses them on the phone, and
turns them into a searchable ledger with budgets, bills, recurring plans and
spending insights.

The ledger is encrypted and stored on the device. The standard Android build
uses an account for sign-in. SMS text is parsed on the device. Messages the
on-device parser cannot resolve confidently are sent to the AI provider
configured under **Settings → AI provider settings**, after redaction — see
[Privacy](#privacy) for exactly what that redaction does and does not remove.

## What it does

- **Local SMS import** — scans the Android inbox for transaction messages,
  classifies debits and credits, and extracts amount, merchant, bank and
  category. Messages stay on the device unless a low-confidence message is
  escalated to a configured AI provider, as described in [Privacy](#privacy).
- **Email import (Gmail)** — opt-in, on-device reading of bank alert emails
  with read-only Gmail access, for banks that alert by email instead of SMS.
- **Manual entries** — add income or expense records without SMS.
- **Encrypted ledger** — records are stored in an on-device encrypted store
  protected with AES-256-GCM; the key lives in platform secure storage.
- **Budgets and alerts** — monthly cycle budget, category budgets and warning
  thresholds.
- **Bills and recurring plans** — detects repeat payments and tracks upcoming
  obligations.
- **Insights** — category breakdown, seven-day activity, month-over-month
  comparison and instrument-level spending.
- **Optional assistant** — a local, deterministic finance assistant. Cloud
  assistance is opt-in and proxied through a server that holds the model key.
- **Offline first** — the app opens and works without a network connection.
- **Appearance** — nineteen curated palettes, each in light and dark mode.
- **OTA updates** — released builds can check for and install signed updates
  from Settings → Software update.

## Install

Android 7.0 or newer. The current release is **2.0.25 (build 50)**, and the
minimum supported version is **2.0.24**.

### From the website (recommended)

1. Open <https://spendsense-ota-2026.web.app>.
2. Choose **Download APK**. The button always resolves to the build the live
   manifest names, so it cannot go stale.
3. Allow installs from the browser or file manager when prompted.
4. Install. Updating over an existing build with the same signing key preserves
   local data.

### From GitHub Releases

Every release is published as a GitHub Release asset:

<https://github.com/Chaitanysai/Spendsense/releases/latest>

GitHub Releases are the durable archive of downloadable APKs. The
[latest release](https://github.com/Chaitanysai/Spendsense/releases/latest) is
kept in step with the OTA channel, but an individual release page shows the
build it was published for — always check the version before installing.

Both routes serve the same signed APK. A build installed from either updates
over the other, because the signing certificate is unchanged.

### Verifying a download

| | 2.0.25 (build 50) | 2.0.24 (build 49) |
|---|---|---|
| Package | `com.example.spendsense` | `com.example.spendsense` |
| versionName / versionCode | `2.0.25` / `50` | `2.0.24` / `49` |
| minSdk | 24 (Android 7.0+) | 24 (Android 7.0+) |
| SHA-256 | `3c56d47d9634d8075c8405a2cf7ea2a5704df3a4090d6a6c44527d5432e90551` | `d48fe7ac7edafb4141868a6dfeebaeacfebe808432d1f7d8e046b96b8a04dea5` |
| Signing certificate SHA-256 | `42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367` | `42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367` |

```bash
sha256sum spendsense-2.0.25+50.apk
# 3c56d47d9634d8075c8405a2cf7ea2a5704df3a4090d6a6c44527d5432e90551
```

Installed builds check the downloaded APK's SHA-256, package name and signing
certificate against these values before opening the system installer; the trust
model is documented in [docs/OTA_UPDATES.md](docs/OTA_UPDATES.md).

## Build from source

Requirements:

- Flutter with the Android toolchain
- An Android device or emulator
- JDK 17 for the Android build

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Create a release APK with your own signing configuration:

```bash
flutter build apk --release
```

The repository does not contain signing keys. CI builds are signed from GitHub
Actions secrets; local release builds use your own keystore.

### Optional services

- **Accounts** require a Firebase project configuration.
- **OTA** uses a static manifest and a signed APK; see
  [docs/OTA_UPDATES.md](docs/OTA_UPDATES.md).

The ledger and SMS parsing work offline. A build without Firebase configuration
runs without an account.

## Project layout

```text
lib/
  main.dart                 app shell, navigation and theme
  models/                   transaction, recurring plan and update models
  providers/                ledger, period, theme, planner and update state
  screens/                  home, activity, insights, budgets, bills, settings
  services/                 SMS import, parsing, storage and updates
  utils/                    design tokens, formatting and period math
  widgets/                  shared cards, charts, navigation and controls
assets/                     icons, fonts and sound cues
docs/                       architecture and setup notes
ota/                        OTA hosting layout
```

## Privacy

- Transaction SMS text is parsed on the device. Messages the on-device parser
  cannot resolve confidently — it needs an explicit debit and scores below 0.8 —
  are sent to the AI provider configured under **Settings → AI provider
  settings**, but only once such a provider is configured. There is no separate
  consent switch: configuring a provider is what enables the cloud path.
- Before leaving the device, that text is redacted: 4–6 digit runs (OTPs) become
  `***`, `cvv`/`pin` values are masked, and digit runs of 10–16 characters are
  reduced to their last four digits. **Redaction is not complete.** Digit runs of
  7–9 characters currently pass through unmodified, so an account or reference
  number in that range can reach the provider intact. Treat the cloud path as
  sending redacted-but-not-anonymised text.
- The local database is encrypted; the key is kept in platform secure storage.
- The optional assistant sends only the typed question, recent chat text and
  validated tool calls to its proxy — never the database, raw SMS or account
  tokens beyond the request's short-lived authentication token.

## Contributing

Issues and pull requests are welcome. Run `flutter analyze` and `flutter test`
before opening a pull request, and keep changes scoped to one concern.

## Documentation

Available on this branch:

- [OTA updates](docs/OTA_UPDATES.md) — manifest schema, download verification and
  the pinned signing certificate

On the [`release/2.0.13+38`](https://github.com/Chaitanysai/Spendsense/tree/release/2.0.13%2B38)
branch, but **not yet on `main`** — these are intentionally not written as
relative links here, because the files do not exist on `main` and the links
would 404:

| Document | Path on the release branch |
|---|---|
| Changelog and release history | `CHANGELOG.md` |
| Assistant architecture | `docs/assistant.md` |
| Email import (Gmail) | `docs/email-import.md` |
| Firebase setup | `docs/firebase.md` |
| Hosting cache headers | `docs/hosting-cache-headers.md` |
| Spending semantics | `docs/spending-semantics.md` |
| Typography | `docs/typography.md` |
| Theme system and palettes | `docs/design-redesign/02-theme-implementation.md` |
| Sound credits | `assets/sounds/CREDITS.md` |
| Assistant proxy | `backend/assistant_proxy/README.md` |

Release history and per-release notes live in
[GitHub Releases](https://github.com/Chaitanysai/Spendsense/releases), which is
also the authoritative location for downloadable APKs.
