# SpendSense

SpendSense is a local-first expense tracker for Android. It reads bank and UPI
transaction messages from the device inbox, parses them on the phone, and turns
them into a searchable ledger with budgets, bills, recurring plans and spending
insights.

The ledger is encrypted and stored on the device. The standard Android build
uses an account for sign-in. SMS text stays on the device by default. If you
explicitly enable **AI Provider Settings → Send ambiguous SMS to AI providers**,
redacted low-confidence messages are sent to the provider you configured; read
that screen before enabling it.

## What it does

- **Local SMS import** — scans the Android inbox for transaction messages,
  classifies debits and credits, and extracts amount, merchant, bank and
  category. Messages stay on the device unless cloud SMS parsing is explicitly
  enabled as described above.
- **Email import (Gmail)** — opt-in, on-device reading of bank alert emails
  with read-only Gmail access, for banks that alert by email instead of SMS.
  See [docs/email-import.md](docs/email-import.md).
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
- **Appearance** — four curated premium palettes and additional themes, each in
  light and dark mode.
- **OTA updates** — released builds can check for and install signed updates
  from Settings → Software update.

## Install

Android 7.0 or newer.

1. Open the [latest release](https://github.com/Chaitanysai/Spendsense/releases/latest).
2. Download the `.apk`.
3. Allow installs from the browser or file manager when prompted.
4. Install. Updating over an existing build with the same signing key preserves
   local data.

## Build from source

Requirements:

- Flutter 3.47 or newer with the Android toolchain
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

- **Accounts** require a Firebase project; see
  [docs/firebase.md](docs/firebase.md).
- **Cloud assistant** requires the proxy in
  [backend/assistant_proxy](backend/assistant_proxy/README.md) and an API key
  stored server-side.
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
backend/assistant_proxy/    optional assistant proxy
docs/                       architecture and setup notes
ota/                        OTA hosting layout
```

## Privacy

- Transaction SMS text is parsed on the device and is not uploaded.
- The local database is encrypted; the key is kept in platform secure storage.
- The optional assistant sends only the typed question, recent chat text and
  validated tool calls to its proxy — never the database, raw SMS or account
  tokens beyond the request's short-lived authentication token.

## Contributing

Issues and pull requests are welcome. Run `flutter analyze` and `flutter test`
before opening a pull request, and keep changes scoped to one concern.

## Documentation

- [Assistant architecture](docs/assistant.md)
- [OTA updates](docs/OTA_UPDATES.md)
- [Firebase setup](docs/firebase.md)
- [Spending semantics](docs/spending-semantics.md)
- [Typography](docs/typography.md)
- [Sound credits](assets/sounds/CREDITS.md)
