# SpendSense Assistant Proxy

Trusted server-side proxy for SpendSense's Gemini assistant. The Gemini API key
lives only in Google Secret Manager. The Android app never receives it.

Every deployed request must present both:

1. a Firebase App Check token for the specific SpendSense Android app; and
2. a Firebase Authentication ID token for the signed-in SpendSense account.

The function verifies both with Firebase Admin before request validation or any
Gemini call. The App Check app id must match `SPENDSENSE_ANDROID_APP_ID`; the UID
comes only from the verified ID token. There is no bypass in the deployed
wrapper.

## What the backend does

1. Checks the per-address flood limit and the per-instance cap.
2. Verifies `X-Firebase-AppCheck` and requires the expected app id.
3. Verifies `Authorization: Bearer <Firebase ID token>`, including revocation,
   then applies the per-verified-UID quota.
4. Accepts only a small JSON request containing the typed question, up to 8
   recent chat text turns, and validated local tool calls/results.
5. Rejects unknown tools, malformed arguments, oversized bodies, excess rounds
   and excess calls.
6. Calls Gemini with a backend-owned system prompt and fixed tool allowlist.
7. Returns text or validated function calls the app executes locally.
8. Never applies a mutation. Apply/undo tools are absent from the model's tool
   declarations; only an explicit in-app confirmation can change the ledger.
9. Persists no prompts, transactions or chat history.

## Security controls

- App Check and Firebase Auth are both mandatory and fail-closed. Missing,
  malformed, expired, revoked, wrong-app or wrong-project credentials get 401.
- No user id is trusted from a request body or header; the UID is derived only
  from the server-verified Firebase ID token.
- API key only in Secret Manager (`GEMINI_API_KEY`), sent upstream in
  `x-goog-api-key`; never logged, returned, placed in a URL or committed.
- Fixed tool declarations and allowlist; no SQL, filesystem paths, generated
  code, arbitrary HTTP or database access.
- Request caps: 64 KiB body, 8 history turns, 4 tool rounds, 8 calls/round,
  2,000-character question, 1,024 output tokens.
- Three windows, all checked with a fail-closed default: 12/min per client
  address, 180/min per function instance (process-wide), and 12/min per verified
  Firebase UID. The UID window is consumed only after the ID token has been
  verified, so a rejected caller cannot drain another account's quota; it exists
  because carrier NAT and address rotation make the address window an unsafe
  per-user budget.
- The client address is the socket peer when it is a public address. On Cloud
  Run the peer is the platform's local proxy (`169.254.x.x`), so the last
  `X-Forwarded-For` hop — the address the Google front end appends — is used
  instead; a spoofed leading header cannot reset the limit. The limiter is
  in-memory: the per-UID cap holds per instance, so the effective ceiling across
  `maxInstances: 10` is 10x. A shared store (Redis/Firestore) is required for a
  true cross-instance cap.
- Numeric configuration (`RATE_LIMIT_*`, `UPSTREAM_TIMEOUT_MS`) is parsed
  defensively: a blank, non-numeric or non-positive value falls back to the
  documented default instead of silently disabling the limit.
- 20-second Gemini timeout, 30-second function timeout, `maxInstances: 10`.
- Runtime is `nodejs22`. Node.js 20 reached end of support on 2026-04-30 and is
  decommissioned by Cloud Run on 2026-10-30, after which new deployments on it
  are rejected; `nodejs22` is the supported target.
- CORS headers are emitted only for an explicitly configured origin; Android
  does not depend on CORS.
- Strict top-level request shape: no client-supplied `apiKey`, `systemPrompt`
  or extra model turns.
- Logs contain only event name, request id, status and latency. App Check
  tokens, prompts and financial rows are never logged.

## One-time setup

### 1. Backend dependencies and secret

From the repository root:

```powershell
cd backend/assistant_proxy
npm install
```

Create the secret (Firebase prompts for the value in your terminal; never paste
it into chat or commit it):

```powershell
firebase functions:secrets:set GEMINI_API_KEY --project spendsense-ota-2026
```

### 2. Server-side non-secret configuration

Copy `.env.example` to `.env.spendsense-ota-2026` (ignored by Git) and set:

```text
SPENDSENSE_ANDROID_APP_ID=<the Android Firebase app id>
```

This must exactly match the app id used by the Flutter build. It already
defaults to the SpendSense app id in `src/index.js` — the value is public and is
committed in `firebase_options.dart` — so this file is only needed to override
it. If the configured value does not match the verified App Check token's app
id, requests fail closed. `GEMINI_API_KEY` is not read from this file; it is the
Secret Manager parameter.

### 3. Firebase App Check for the Android app

1. Register Android application id `com.example.spendsense` in Firebase project
   `spendsense-ota-2026`.
2. Add the SHA-256 fingerprints for the upload and release signing certificates.
3. Enable App Check > Apps > Android > Play Integrity.
4. For debug builds, register a debug token in Firebase Console and pass
   `FIREBASE_APP_CHECK_DEBUG_TOKEN` in the local build command. Never commit it.

The app initializes Firebase from `lib/firebase_options.dart` at startup,
activates Play Integrity, and uses the existing Email/Password Firebase Auth
session. `GeminiProxyClient` sends the App Check token as
`X-Firebase-AppCheck` and the user's ID token as `Authorization: Bearer ...`.
Both are short-lived and remain in memory. The backend does not forward the ID
token or UID to Gemini.

### Critical distribution assumption

SpendSense is currently distributed via a self-hosted **OTA sideload** APK, not
Google Play (`docs/OTA_UPDATES.md`). Play Integrity's recognized-app verdict is
intended for Play-distributed installations. Do not assume it will issue a
usable production verdict for sideloaded OTA builds. Validate with a real signed
release installed the same way users install it. If Play Integrity returns an
unrecognized/unevaluated verdict, this authentication design is not viable for
the current distribution and must be changed after approval (for example Play
distribution or a different authenticated backend design).

## Deploy after approval

Confirm the project is on Blaze and these APIs are enabled: Cloud Functions,
Cloud Build, Artifact Registry, Secret Manager and the Gemini API. Set a budget
alert and ensure the runtime service account can access the secret version.

```powershell
firebase deploy --only functions:assistantProxy --project spendsense-ota-2026
```

Target:

- Project: `spendsense-ota-2026`
- Function: `assistantProxy`
- Region: `asia-south1`
- Expected URL:
  `https://asia-south1-spendsense-ota-2026.cloudfunctions.net/assistantProxy`

## Build the app

```powershell
flutter build apk `
  --dart-define=SPENDSENSE_AI_PROXY_URL=https://asia-south1-spendsense-ota-2026.cloudfunctions.net/assistantProxy
```

No Firebase client identifiers are duplicated at build time; the existing
`firebase_options.dart` / Google Services configuration is reused.

For a debug build only, append:

```powershell
--dart-define=FIREBASE_APP_CHECK_DEBUG_TOKEN=<registered-debug-token>
```

If the proxy URL is absent, Firebase is unavailable, or the user is signed out,
cloud assistance stays disabled/returns a safe auth error and the app remains
local-only. The Gemini API key is never part of this build command.

## Verify authentication after deployment

- Request without `X-Firebase-AppCheck`: 401 and no Gemini call.
- Forged/expired App Check token: 401.
- App Check token for a different app in the same project: 401.
- Missing/malformed `Authorization`: 401 `auth_required`.
- Invalid, expired, revoked or wrong-project ID token: 401 `auth_invalid`.
- Both credentials valid from the registered app and signed-in account: 200.
- Check Cloud Logging contains only request id, status and latency.

## Tests

```powershell
npm test
```

The 36 backend tests cover the tool allowlist, required App Check, app-id
matching, ID-token requirements/revocation behavior, missing/malformed/invalid
credentials, log/response redaction, request validation, secret handling, the
per-address, per-instance and per-UID rate limits, spoofed forwarding headers and
private platform peers, malformed numeric configuration, timeouts and upstream
failures. They call no Gemini endpoint and need no credentials.

## Deployment blockers

- Firebase App Check registration and Play Integrity configuration for the
  Android app.
- Confirmation that Play Integrity works for the OTA-sideloaded distribution.
  ID-token auth is additive and does not remove this requirement.
- Secret Manager IAM: the secret currently has no IAM bindings, so the runtime
  service account cannot read the secret version even though the secret exists.
- API enablement: `cloudbuild`, `run`, `artifactregistry`, `eventarc`,
  `generativelanguage` and `cloudbilling` are disabled in `spendsense-ota-2026`,
  so a deploy and a Gemini call both fail today.
- Budget alert and Blaze confirmation (billing is enabled).
- Deployed function and a live request from a signed-in, registered build with
  both credentials.
