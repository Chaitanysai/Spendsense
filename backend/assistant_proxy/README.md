# SpendSense assistant proxy

Optional server-side proxy for the SpendSense in-app assistant. The model API
key lives only on the server; the Android app never receives it.

Every request must present:

1. an App Check token for the registered SpendSense Android app, and
2. a Firebase Authentication ID token for the signed-in account.

The proxy verifies both before validating the request or calling the model.
There is no unauthenticated path.

## What the proxy does

1. Applies a per-address flood limit and a per-instance cap.
2. Verifies the App Check token and the expected Android app id.
3. Verifies the Firebase ID token, including revocation, then applies a
   per-account quota.
4. Accepts a small JSON request: the typed question, at most eight recent chat
   turns, and validated local tool calls/results.
5. Rejects unknown tools, malformed arguments, oversized bodies, excess rounds
   and excess calls.
6. Calls the model with a server-owned system prompt and a fixed tool allowlist.
7. Returns text or validated function calls that the app executes locally.
8. Never mutates the ledger. Apply/undo tools are absent from the model's tool
   declarations; only an explicit in-app confirmation can change data.
9. Persists no prompts, transactions or chat history.

## Security controls

- App Check and Firebase Auth are mandatory and fail closed. Missing,
  malformed, expired, revoked, wrong-app or wrong-project credentials are
  rejected.
- The user id is derived only from the verified ID token, never from the request
  body.
- The model key is a server-side secret. It is never logged, returned, placed in
  a URL or committed.
- Fixed tool declarations and an allowlist; no SQL, filesystem access, generated
  code or arbitrary HTTP.
- Request caps for body size, history turns, tool rounds, calls per round,
  question length and output length.
- Separate limits per client address, per function instance and per verified
  account. The in-memory limiter is per instance; use a shared store if a true
  cross-instance cap is required.
- The socket peer is used when it is public. Behind a managed proxy, the last
  forwarded hop is used instead; a spoofed leading header cannot reset the
  limit.
- Logs contain only event name, request id, status and latency. Tokens, prompts
  and financial rows are never logged.

## Setup

Prerequisites: a Firebase project with Blaze billing, Cloud Functions, Cloud
Build, Artifact Registry, Secret Manager and the model API enabled.

```bash
cd backend/assistant_proxy
npm install
```

Store the model key as a function secret (the CLI prompts for the value; never
commit it):

```bash
firebase functions:secrets:set GEMINI_API_KEY
```

Non-secret configuration:

- `SPENDSENSE_ANDROID_APP_ID` must match the Android app registered for App
  Check. If it does not match, requests fail closed.
- Optionally set the allowed CORS origin for browser clients. Android does not
  depend on CORS.

Register the Android app in Firebase, add the release signing certificate
fingerprints, and enable App Check (Play Integrity). For debug builds, register
a debug token and pass it as a local `--dart-define`; never commit it.

Deploy:

```bash
firebase deploy --only functions:assistantProxy
```

Point the app at the deployed function:

```bash
flutter build apk --release \
  --dart-define=SPENDSENSE_AI_PROXY_URL=https://<region>-<project>.cloudfunctions.net/assistantProxy
```

If the proxy URL is absent, Firebase is unavailable, or the user is signed out,
cloud assistance stays disabled and the app remains local-only.

## Verification

- Missing or invalid App Check token: rejected, no model call.
- Missing, malformed, expired or revoked ID token: rejected.
- Valid credentials from the registered app and signed-in account: accepted.
- Logs contain only request metadata.

```bash
npm test
```

The backend tests cover the tool allowlist, credential checks, request
validation, secret handling, rate limiting, forwarding-header handling and
upstream failures. They call no model endpoint and need no credentials.

## Distribution note

Play Integrity's recognized-app verdict is intended for Play-distributed
installs. If SpendSense is distributed outside Play (for example as a signed
sideload or OTA APK), validate that App Check produces a usable verdict for that
installation path before relying on it in production.
