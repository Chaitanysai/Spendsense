# SpendSense

SpendSense is an offline-first Flutter expense tracking app purpose-built for Indian bank and UPI transaction workflows. It reads transaction SMS messages from the Android device inbox, parses them locally using a regex-first smart parser with optional LLM fallback, and presents spending insights, budget tracking, and manual transaction management through a modern glassmorphic UI.

## Features

- **SMS-based Sync**: Automatic transaction ingestion from the device inbox via `flutter_sms_inbox`
- **Smart Transaction Parsing**: Regex-first `smart_parser` with strict debit filtering, bank recognition, and confidence scoring; optional LLM fallback for ambiguous messages
- **Recurring Payment Detection**: Identifies and flags recurring transactions via `recurring_detector_service`
- **Budget Monitoring**: Salary-cycle aware budget tracking with adaptive insights and local notifications via `budget_monitor_service`
- **Manual Transactions**: Full create/update/delete support for user-entered expenses
- **Offline-First**: No login, no Firebase, no cloud sync — 100% local with SQLite caching
- **Glassmorphic Design System**: Premium palette with gradient hero cards, glass cards, glossy pills, and adaptive launcher icon
- **AI Chat & Insights**: Local reasoning for spending analytics; optional cloud AI providers (Groq, Cerebras, Gemini, OpenRouter) for edge cases

## Tech Stack

- **State Management**: `provider` ^6.1.1
- **Database**: `sqflite` ^2.3.2 with `path_provider` ^2.1.2
- **Secure Storage**: `flutter_secure_storage` ^9.0.0 for encrypted API key storage
- **SMS Access**: `flutter_sms_inbox` ^1.0.3 + `permission_handler` ^11.3.0
- **Charts**: `fl_chart` ^0.66.0
- **Typography**: `google_fonts` ^6.1.0
- **Forms**: `reactive_forms` ^17.0.0
- **Sound**: `audioplayers` ^6.8.1 for transaction cues
- **Notifications**: `flutter_local_notifications` ^18.0.0 for budget alerts
- **Code Push**: Shorebird for hot updates

## Project Structure

```text
lib/
  main.dart                    App entrypoint, routing, and initialization
  config/
    app_config.dart            Central API key access (Secure Storage > --dart-define)
  models/
    ai_chat_message.dart       AI chat message model
    transaction_model.dart     Transaction data model with v2.0 fields
  providers/
    auth_provider.dart         Authentication and session state
    period_provider.dart       Date/period filters for UI
    sound_provider.dart        Sound effects state
    theme_provider.dart        Dynamic theme and glassmorphic design system
    transaction_provider.dart  Core: SMS sync, parsing logic, caching, CRUD
  screens/ (12)
    activity_screen.dart       Transaction list with filtering
    add_transaction_screen.dart Manual transaction entry
    ai_settings_screen.dart    AI provider configuration (Groq, Cerebras, Gemini, OpenRouter)
    appearance_screen.dart     Theme and UI appearance settings
    cards_screen.dart          Visual spending cards
    home_screen.dart           Main dashboard with insights
    insights_screen.dart       Analytics and spending patterns
    login_screen.dart          Auth screen
    recurring_screen.dart      Recurring transaction management
    settings_screen.dart       App configuration
    sound_settings_screen.dart Sound preferences
    transaction_details_screen.dart Transaction detail view
  services/ (12)
    ai_query_service.dart      Cloud AI query orchestration
    ai_service.dart            Local AI reasoning for insights
    budget_monitor_service.dart Budget tracking and notifications
    cache_service.dart         Caching abstraction
    database_service.dart      SQLite database operations
    gemini_service.dart        LLM fallback parsing (Gemini, Groq, Cerebras, OpenRouter)
    recurring_detector_service.dart Recurring payment detection
    secure_storage_service.dart Encrypted key storage (Android Keystore / iOS Keychain)
    smart_parser.dart          Regex-first transaction parser with confidence scoring
    sms_service.dart           Android SMS inbox access
    sound_service.dart         Sound effects management
    transaction_cache_service.dart Transaction caching
  utils/ (7)
    app_colors.dart            Color definitions
    app_palette.dart           Premium palette system
    app_spacing.dart           Spacing constants
    app_text_styles.dart       Typography styles
    bank_recognizer.dart       Indian bank identification from SMS
    category_style.dart        Category styling
    formatters.dart            Currency and date formatting
  widgets/ (20)
    animated_amount.dart       Animated amount display
    app_background.dart         Gradient/glass background
    app_button.dart            Styled buttons
    app_logo.dart              App logo
    app_page_route.dart        Custom page transitions
    app_states.dart            Empty/error/loading states
    budget_gauge.dart          Budget progress gauge
    category_bubble.dart       Category bubble widget
    category_bubble_cluster.dart Category bubble cluster
    fade_indexed_stack.dart    Fade animation stack
    fade_slide_in.dart         Fade slide animation
    floating_nav_bar.dart      Floating navigation
    glass_card.dart            Glassmorphic card
    glossy_pill.dart           Glossy pill button
    gradient_hero_card.dart    Gradient hero card
    pressable.dart             Pressable wrapper
    profile_avatar.dart        Profile avatar
    salary_day_prompt.dart     Salary day prompt
    section_header.dart        Section header
    sms_import_prompt.dart     SMS import prompt
    sound_scope.dart           Sound scope widget
    transaction_tile.dart      Transaction list tile
```

## Setup & Build

### 1. Install Flutter dependencies

```bash
flutter pub get
```

### 2. Configure AI Provider Keys (Optional)

SpendSense supports **Groq**, **Cerebras**, **Gemini**, and **OpenRouter** for intelligent transaction parsing.

**Recommended:** Configure keys at runtime via in-app settings:
1. Launch the app
2. Go to **Settings → AI Provider Settings**
3. Enter your API keys (stored in platform-encrypted storage via `flutter_secure_storage`)
4. Keys never leave your device and are not bundled in the APK

**Alternative (Development Only):** Use `.env` files:
1. Copy `.env.example` to `.env`
2. Fill in your keys (e.g., `GROQ_API_KEY`, `CEREBRAS_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY`)
3. `.env` is gitignored and never committed

**Priority:** Secure Storage > .env > --dart-define (CI/CD)

### 3. Android permissions

The app requires SMS read permission on Android for transaction sync. Test on a real device with transaction SMS messages available in the inbox.

### 4. Running the App

```bash
flutter run
```

Or with AI keys via dart-define:
```bash
flutter run \
  --dart-define=GROQ_API_KEY=your_key \
  --dart-define=CEREBRAS_API_KEY=your_key \
  --dart-define=GEMINI_API_KEY=your_key \
  --dart-define=OPENROUTER_API_KEY=your_key
```

## CI/CD

This repository uses GitHub Actions workflow `.github/workflows/android-release.yml` that:

- **Triggers**: On push to `feat/spendsense-sync-20261017` branch, on `v*.*.*` tags, or via manual dispatch
- **Security Gate**: Runs Semgrep secrets + security audit scan on `lib/`, `android/`, and `.github/` — build fails if secrets are detected
- **Build Pipeline**:
  1. Checks out code
  2. Sets up Java 17 and Flutter stable
  3. Provisions Android SDK components (platform-tools, platforms;android-36, build-tools;36.0.0)
  4. Runs `flutter pub get`
  5. Runs `flutter analyze` for static analysis
  6. Runs `flutter test` for unit tests
  7. Prepares keystore for release signing from `SIGNING_KEY` secret (base64-encoded upload-keystore.jks)
  8. Builds release APK with signing keys (`KEY_ALIAS`, `KEY_PASSWORD`, `STORE_PASSWORD`)
  9. **Fallback**: If no signing keys provided, builds debug-signed sideload APK with warning
  10. Verifies APK metadata and signing certificate
  11. **Security Verification**: Scans APK for `.env` entries and known API key patterns (Gemini `AIza...`, Groq `gsk_...`, Cerebras `csk-...`, OpenRouter `sk-or-...`) — fails if any are bundled
  12. Uploads APK artifact named `spendsense-release.apk` (or `spendsense-debug-signed-sideload.apk` for fallback)
  13. Uploads build logs on failure

### Required GitHub Secrets

- `SIGNING_KEY`: Base64-encoded upload-keystore.jks
- `KEY_ALIAS`: Keystore alias
- `KEY_PASSWORD`: Keystore key password
- `STORE_PASSWORD`: Keystore store password

If secrets are missing, the workflow safely falls back to debug keystore for testing.

## Security

- **No Bundled Secrets**: API keys are never embedded in the app. They enter exclusively via in-app Settings (encrypted storage) or `--dart-define` at build time. The CI workflow explicitly scans the APK to ensure no `.env` files or API key patterns are bundled.
- **Android Backup Lockdown**: Android configuration prevents backup of sensitive data.
- **Encrypted Key Storage**: API keys stored via `flutter_secure_storage` use Android EncryptedSharedPreferences and iOS Keychain.
- **CI Security Gate**: The `security` job runs Semgrep with `p/secrets` and `p/security-audit` configs before any build can proceed. The `build` job requires `security` to pass (`needs: security`).

## Version

Current app version in `pubspec.yaml`:
- `2.0.0+20`

Recent design refresh (glassmorphic UI) and security hardening delivered in commits `f5c445f` (glassmorphic redesign) and `f020ff4` (secret bundling elimination + Android backup lockdown).
