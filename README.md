# SpendSense

SpendSense is an offline-first Flutter expense tracking app focused on Indian bank and UPI transaction workflows. It reliably reads transaction SMS messages from the Android device inbox, extracts expense entries locally, caches them locally, and presents spending activity, insights, budget tracking, and manual transaction management in a mobile UI.

## Features

- Local-first SMS-based transaction sync from the device inbox
- Smart transaction parsing with strict regex-first rule validation and debit filtering
- Optional local AI fallback strictly for ambiguous debit messages matching context
- Persistent local SQLite caching with real-time UI updates
- Monthly budget tracking & historical insights
- Offline-first architecture - works without internet, no Firebase login required 
- Full manual transaction entry and history search
- Fast start times and automatic background synchronization

## Tech Stack

- Flutter & Dart
- Provider for state management
- `sqflite` for robust local database caching
- `flutter_dotenv` for configurable API keys (kept out of source control)
- `shared_preferences` for fast local configurations
- `flutter_sms_inbox` & `permission_handler` for local text extraction
- `fl_chart` for insights and charts

## Project Structure

```text
lib/
  main.dart                         App entrypoint and initialization
  models/transaction_model.dart     Transaction data configurations
  providers/
    transaction_provider.dart       Heart of transactions: sync, logic & caching
    theme_provider.dart             Dynamic theme and appearance logic
    period_provider.dart            Date/period filters for UI
  screens/
    home_screen.dart                Main dashboard
    activity_screen.dart            List of synced and manual transactions
    insights_screen.dart            Analytics and categorization
    settings_screen.dart            App config and backup
  services/
    smart_parser.dart               Strict rule-based debit parser
    sms_service.dart                Android inbox access
    gemini_service.dart             LLM fallback for edge extraction
    database_service.dart           SQLite driver
    transaction_cache_service.dart  Db operations
```

## Setup & Build

### 1. Install Flutter dependencies

```bash
flutter pub get
```

### 2. Configure AI Provider Keys (Optional)

SpendSense supports multiple AI providers for intelligent transaction parsing: **Groq**, **Cerebras**, **Gemini**, and **OpenRouter**.

**🔐 Recommended:** Configure keys at runtime via the in-app settings:
1. Launch the app
2. Go to **Settings → AI Provider Settings**
3. Enter your API keys securely (stored in platform-encrypted storage)
4. Keys never leave your device and are not compiled into the APK

**Alternative (Development Only):** Use `.env` files:
1. Copy `.env.example` to `.env`
2. Fill in your keys (e.g., `GROQ_API_KEY`, `CEREBRAS_API_KEY`)
3. `.env` remains untracked via `.gitignore`

**Priority:** Secure Storage > .env > --dart-define (CI/CD)

### 3. Android permissions

The app requires SMS read permission on Android devices for transaction sync. Test on a real device with transaction SMS messages available in the inbox.

### 4. Running the App

```bash
flutter run
```

### 5. Automated Cloud Android Builds

This repository is configured with a GitHub Actions workflow `.github/workflows/android-release.yml` that:
- Checks out the latest code
- Runs static analysis (`flutter analyze`) and tests (`flutter test`)
- Generates `android/app/google-services.json` from the `FIREBASE_ANDROID_GOOGLE_SERVICES` secret (the file is gitignored and never committed)
- Builds a signed Release APK
- Verifies the APK's signature and scans its contents for bundled secrets

It runs on `v*` tags, on pushes to `feat/spendsense-sync-20261017`, and by manual
dispatch. It does **not** run on pull requests, because its build job can reach
release-signing secrets.

To sign, the workflow requires these GitHub Action Secrets:
- `SIGNING_KEY` (Base64 of your upload-keystore.jks)
- `KEY_ALIAS`
- `KEY_PASSWORD`
- `STORE_PASSWORD`
- `FIREBASE_ANDROID_GOOGLE_SERVICES` (content of `google-services.json`, or its base64)

**The build fails closed.** If signing credentials are missing or the keystore
cannot be decoded, the workflow stops with an error. It never falls back to the
debug keystore, so a debug-signed APK can never be mistaken for a release.

The workflow does **not** create a GitHub Release or push a tag. Publishing is a
separate, explicit step.

## Version

Current app version in `pubspec.yaml`:

- `2.0.0+20`

### Versioning policy

The version has two parts, and they are not interchangeable:

- `version:` in `pubspec.yaml` is `name+build`, e.g. `2.0.0+20`. Flutter maps
  this to Android `versionName` = `2.0.0` and `versionCode` = `20`.
  **`versionCode` must increase on every published build.**
- Git tags mark a published release. Use **`v<name>`**, matching `versionName`
  (`v2.0.0`), to fit the `v*` trigger.

Tags already present: `v2.0.0`, `v2.0.1`, `v2.0.2`, `v1.0.4+4`, `v1.0.5+5`,
plus a legacy `2.1.0` tag that does not match this policy.

Not every `pubspec.yaml` change is a release. Until a public release version is
chosen and merged, the value stays at whatever the last published source used.
