# Release readiness and Firebase configuration

Status of the pieces a release depends on that code alone cannot prove. Everything
in "Implemented" is in the repository and covered by the checks named. Everything
in "Requires Console or account access" needs a human with the relevant account.

Last reviewed against `main` at the merge of PR #6.

---

## 1. Android application identity

| Item | Value |
| --- | --- |
| `namespace` / `applicationId` | `com.example.spendsense` |
| Kotlin package | `com.example.spendsense` |
| Manifest `package` | `com.example.spendsense` |
| Firebase Android app id | `1:35486869641:android:62072850e90abafabc7e58` |
| Firebase project | `spendsense-ota-2026` |

**Known limitation, recorded deliberately.** `com.example.*` is the Android
placeholder namespace. Google Play **rejects** applications using it, so Play Store
distribution is blocked by this identifier. It has been chosen as the project's
permanent identity for internal purposes (Firebase registration, Play Integrity,
OTA), which is fine for sideload and direct distribution.

It cannot be changed in place for installed users. Changing it later requires:

1. a new Firebase Android app registered under the new id,
2. a regenerated `google-services.json` uploaded as the
   `FIREBASE_ANDROID_GOOGLE_SERVICES` secret,
3. reissuing Play Integrity configuration, and
4. accepting that existing installs cannot upgrade in place.

If Play distribution is ever intended, decide this **before** the first public
release, not after.

`android/app/google-services.json` is gitignored and must never be committed. It is
materialised at build time by `tool/write_google_services.dart` from the
`FIREBASE_ANDROID_GOOGLE_SERVICES` secret.

---

## 2. Implemented in the repository

- **Firebase init before App Check.** `lib/main.dart` initialises Firebase, then
  activates App Check through the shared gate, and still opens the local ledger if
  either fails.
- **Play Integrity in release builds.** `lib/services/app_check/app_check_bootstrap.dart`
  selects `AndroidPlayIntegrityProvider` whenever `kDebugMode` is false. A debug
  token can only influence a debug build.
- **No debug token committed.** The token is read solely from
  `--dart-define=FIREBASE_APP_CHECK_DEBUG_TOKEN` via `String.fromEnvironment`.
- **One activation.** Startup and the assistant token provider share
  `AppCheckBootstrap.shared`; concurrent callers share one pending future, success
  never re-activates, and failures are not cached so a retry is deliberate.
- **Sanitized failures.** `AppCheckBootstrapException` and `AssistantAuthException`
  carry a stable code and a fixed message; no exception details, Firebase config, or
  token contents are logged.
- **Build-time configuration.** The release workflow generates
  `google-services.json` and fails before Gradle if the secret is absent or invalid.
- **Fail-closed signing.** `Require release signing` stops the build when any
  credential is missing or undecodable. There is no debug-keystore fallback.
- **Secret scanning.** The release workflow scans APK contents for provider key
  families and fails closed when the archive cannot be read.

---

## 3. Requires Console or account access — not verified here

Nothing below has been confirmed. Do not enable enforcement until each item is
checked against the real accounts.

### Firebase Console

- [ ] The Android app registered for `com.example.spendsense` matches the project
      the app talks to (`spendsense-ota-2026`).
- [ ] The SHA-256 signing fingerprint registered for the app matches the
      **release** keystore used by CI — not a debug key.
- [ ] App Check provider for Android is configured (Play Integrity).
- [ ] Play Integrity is linked to the same Google Cloud project as the Firebase
      project.
- [ ] Any debug tokens are registered only if genuinely needed, and every such
      token is supplied via `--dart-define` in local builds — never committed and
      never passed to a release build.
- [ ] Current enforcement state per service (Firestore, Identity Toolkit, and any
      other service the app calls) is known. Enforcement is **not** enabled by this
      repository.

### Google Cloud / Play

- [ ] The API key used by the client has application restrictions (Android package
      name + SHA-1) and API restrictions. The key in `lib/firebase_options.dart` is
      a public client identifier, not a credential; its safety depends entirely on
      those Console-side restrictions.
- [ ] Play Integrity API is enabled for the project.
- [ ] If Play distribution is intended: the application id must change first (see
      §1).

### GitHub Actions

Configured secrets (names verified, values never read):

- `SIGNING_KEY`, `KEY_ALIAS`, `KEY_PASSWORD`, `STORE_PASSWORD`
- `FIREBASE_ANDROID_GOOGLE_SERVICES`

Presence of a secret proves nothing about its validity. Only a real release build
verifies that the keystore decodes to a valid JKS and that the passwords match it.

---

## 4. What a release build does not prove

- A green CI check does not prove production attestation works. Unit tests use
  injected fakes.
- The APK secret gate counts occurrences of provider key patterns in the extracted
  APK stream. It is proven against synthetic payloads; it has not yet been exercised
  against a real release artifact.
- The first `workflow_dispatch` run should be treated as validation, not shipping.
