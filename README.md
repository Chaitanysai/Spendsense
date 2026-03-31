# SpendSense

SpendSense is a Flutter expense tracking app focused on Indian bank and UPI transaction workflows. It reads transaction SMS messages from the device, extracts expense entries, caches them locally, and presents spending activity, insights, budget tracking, and manual transaction management in a mobile UI.

## Features

- SMS-based transaction sync from the device inbox
- Smart transaction parsing with regex-first parsing and AI fallback
- Local caching for faster startup and incremental sync
- Monthly budget tracking
- Activity, home, insights, and settings screens
- Manual transaction entry
- Firebase authentication with login flow
- AI-powered finance query support

## Tech Stack

- Flutter
- Provider for state management
- Firebase Core and Firebase Auth
- Google Sign-In
- Shared Preferences
- `flutter_sms_inbox` for inbox access
- `permission_handler` for runtime SMS permission
- `fl_chart` for insights and charts
- `http` for AI provider requests

## Project Structure

```text
lib/
  main.dart                         App entrypoint and navigation shell
  models/transaction_model.dart     Transaction model definitions
  providers/
    auth_provider.dart              Authentication state
    transaction_provider.dart       Transaction sync, cache, budget state
  screens/
    home_screen.dart
    activity_screen.dart
    add_transaction_screen.dart
    insights_screen.dart
    login_screen.dart
    settings_screen.dart
    transaction_details_screen.dart
  services/
    sms_service.dart                SMS permission and inbox fetch
    smart_parser.dart               Fast rule-based parser
    gemini_service.dart             SMS parsing fallback via AI providers
    ai_service.dart                 User-facing AI finance queries
    cache_service.dart
    transaction_cache_service.dart  Local transaction persistence
  utils/
    app_colors.dart
    formatters.dart
  widgets/
    summary_card.dart
    transaction_tile.dart
```

## Setup

### 1. Install Flutter dependencies

```bash
flutter pub get
```

### 2. Add Firebase config

This repository intentionally does not include local Firebase secrets.

- Place your Android Firebase config at `android/app/google-services.json`
- Ensure your Firebase project matches the Android package configured for the app
- If you support iOS later, add the matching `GoogleService-Info.plist`

### 3. Configure AI keys locally

The code uses placeholders instead of committed secrets.

Update the provider keys in:

- `lib/services/ai_service.dart`
- `lib/services/gemini_service.dart`

Replace the placeholder values such as `YOUR_GROQ_KEY`, `YOUR_GEMINI_KEY`, and `YOUR_OPENROUTER_KEY` with local values only. Do not commit real keys.

### 4. Android permissions

The app requires SMS read permission on Android devices for transaction sync. Test on a real device with transaction SMS messages available in the inbox.

## Running the App

```bash
flutter run
```

## Development Commands

Analyze:

```bash
flutter analyze
```

Format:

```bash
dart format .
```

Test:

```bash
flutter test
```

## How It Works

1. The app initializes Firebase and Provider state in `lib/main.dart`.
2. `TransactionProvider` loads cached transactions and budget settings on startup.
3. During sync, `SmsService` fetches inbox messages after SMS permission is granted.
4. Messages are filtered to likely financial transactions.
5. `SmartParser` attempts a fast local parse first.
6. If parsing fails or merchant detection is weak, AI parsing is used as a fallback.
7. Parsed transactions are cached locally and surfaced in the UI.

## Important Notes

- This project is Android-first because SMS inbox access is part of the core workflow.
- Generated build artifacts and local secret files are excluded from version control.
- Previously exposed keys should be rotated and kept out of source control permanently.

## Version

Current app version in `pubspec.yaml`:

- `1.0.4+4`
