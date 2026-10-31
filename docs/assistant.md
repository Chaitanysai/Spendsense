# SpendSense Assistant — implementation notes

The assistant is optional. Its local tools always work; cloud assistance is
opt-in and requires a configured proxy. This document describes the design and
trust boundaries, not a deployment status.

## Architecture

```
Flutter UI (AssistantScreen)
  └─ AssistantController (chat state, consent, retry, preview expiry)
       └─ AssistantOrchestrator
            ├─ LocalIntentParser ─────────────► AssistantComposer
            ├─ FinanceToolEngine (deterministic, typed)
            │    ├─ read-only tools
            │    └─ preview tools (never apply)
            ├─ AssistantLedger adapter ──────► TransactionProvider
            │                                  └─ TransactionCacheService
            │                                     (AES-256-GCM, atomic writes)
            ├─ EncryptedAssistantAuditRepository
            └─ GeminiProxyClient ─────────────► backend/assistant_proxy
                                                   └─ Gemini API (server key)
```

- **Local-first.** Every amount, count, date range, bill and preview is computed
  by deterministic Dart over the encrypted local ledger. Gemini never receives
  database access and never supplies an authoritative total.
- **Model proposes, app executes.** The model can call only fixed read and
  preview tools. Apply and undo are *not* in the tool declarations. A preview
  is applied only by an explicit in-app button, then written atomically through
  the existing journalled cache service.
- **One source of truth for spending.** Exclusions are persisted through
  `TransactionProvider`, which notifies Home, Insights, budgets and payment
  instrument totals. The assistant itself has no independent spending math.
- **Preview-only Gemini for changes.** Even a Gemini-originated preview is
  rendered as a pending card; chat text cannot confirm it.

## Deterministic tools

Read-only:

| Tool | Purpose |
|---|---|
| `search_transactions` | Merchant/brand/category/type/date filters, pagination, authoritative totals |
| `get_spending_summary` | Non-excluded expense, income, excluded, investment and transfer totals |
| `group_transactions_by_merchant` | Merchant grouping with counts and totals |
| `get_category_summary` | Category amounts, counts and shares |
| `get_monthly_comparison` | Current vs previous calendar month + category/merchant drivers |
| `list_bills` | Unpaid/paid bills from local plans + deterministic detection |
| `get_transaction_details` | Safe details for stable ids |
| `find_duplicate_transactions` | Likely duplicate groups, stable ids |

Preview-only:

| Tool | Purpose |
|---|---|
| `preview_transaction_exclusion` | Pins exact ids + fingerprints, resulting spending, no mutation |
| `preview_transaction_deletion` | Pins exact ids + fingerprints, permanent-delete warning, no mutation |

Local-only apply/undo (never exposed to Gemini):

- `TransactionProvider.setExclusionForIds` — one journalled write.
- `TransactionProvider.deleteTransactionsByIds` — one journalled index switch.
- `TransactionProvider.restoreExclusionStates` / `restoreTransactions` — undo.

All tools validate types/ranges, reject unknown keys, cap records (200 for a
bulk change, 50 for a page/detail call), resolve exact ids, and return
structured errors.

## Confirmation, audit and undo

- **Preview**: exact records, count, total, resulting spending and precise
  range. Expires after 5 minutes.
- **Confirmation**: only `AssistantOrchestrator.confirmPending(actionId)` from
  the confirmation sheet. Free-text “okay”, “yes”, “confirm” is explicitly
  rejected while a preview is pending.
- **Stale safety**: every preview stores per-record fingerprints; if any row
  changed, apply refuses. Duplicate confirmation fails.
- **Audit**: encrypted with the existing ledger AES-256-GCM key. Contains the
  action type, ids, counts, previous exclusion flags or deleted snapshots.
  Contains **no prompt text**.
- **Transactional behaviour**: a mutation is reversed if its audit record cannot
  be written. A failed write leaves the ledger unchanged.
- **Undo**: restores previous exclusion flags or deleted snapshots and marks the
  audit entry undone. Audit retention is the last 20 changes.

## Privacy and credentials

Sent only when cloud consent is ON and the user's request needs Gemini:

- typed question and up to 8 recent chat text turns;
- only matching rows (merchant, date, category, amount, type, excluded flag)
  and locally computed totals/ranges;
- validated tool names and arguments;
- a short-lived Firebase App Check token used to authenticate the app
  installation;
- a short-lived Firebase Authentication ID token used only by the backend to
  authenticate the signed-in account. Neither token is forwarded to Gemini.

Never sent:

- raw SMS bodies, OTPs;
- account/card/UPI numbers or references;
- full ledger;
- encryption keys, API keys or credentials.

`GeminiProxyClient` sends **no API key**. It obtains a short-lived Firebase App
Check token (Play Integrity on Android) and sends it in
`X-Firebase-AppCheck`, plus the signed-in user's Firebase ID token in
`Authorization: Bearer ...`. The backend verifies both with Firebase Admin:
App Check app-id must match `SPENDSENSE_ANDROID_APP_ID`, and the ID token must
have a valid signature, issuer, audience, expiry and revocation state. No user
ID is accepted from the request body; the UID is derived only from the verified
token. Neither token is forwarded to Gemini. No sign-in UX was added.

The backend reads `GEMINI_API_KEY` from Google Secret Manager and forwards it
to Google only in the `x-goog-api-key` header. The key is never logged,
returned, placed in URLs or embedded in Dart/Android/assets.

Cloud consent is OFF by default in `PreferencesAssistantConsentStore`.
`AssistantPrivacyScreen` explains the data and provides the switch and audit
clear control. Core commands work fully without consent or a backend.

## Backend

`backend/assistant_proxy` is a Firebase Functions v2 proxy:

- fixed system prompt + tool declarations;
- strict request shape (no client system prompt, API key or arbitrary model
  turns);
- 64 KiB body, 8 history turns, 4 tool rounds, 8 calls/round, 2,000-char
  question, 1,024 output tokens;
- per-client 12/min and per-instance 180/min sliding-window limits, checked
  before App Check verification; the client key ignores spoofable leading
  forwarding hops;
- 20 s Gemini timeout, 30 s function timeout, max 10 instances;
- mandatory server-side App Check verification plus exact Android app-id match,
  followed by Firebase Authentication ID-token verification with revocation
  checking (no deployed bypass);
- logs contain request id/status/latency only, never either token.

See `backend/assistant_proxy/README.md` for setup.

## Testing

- `flutter analyze` — clean.
- `flutter test` — full suite.
- `npm test` in `backend/assistant_proxy` — backend core tests without
  credentials or network.

Focused coverage includes aliases/false positives, Groww/Zerodha retrieval,
date ranges/pagination/totals, income/refunds/transfers/excluded, read-only
non-mutation, preview/confirmation gates, bulk exclusion/deletion, undo,
dependent total recalculation, duplicate tool calls, malformed args/ids,
prompt injection, consent/offline/rate/model errors, and 2x-text layout.

## Remaining limitations

1. App Check and Firebase Auth both require external Firebase configuration:
   the Android app must be registered with its signing certificates, Play
   Integrity enabled, and the matching `SPENDSENSE_ANDROID_APP_ID` configured
   server-side. Until then the client deliberately disables cloud assistance
   and remains local-only.
2. Play Integrity recognises Play-distributed installations. If the app is
   distributed another way, validate the App Check verdict for that install
   path. Firebase ID-token auth is additive and does not remove App Check.
3. Rate limits are per function instance; horizontal scaling needs a shared
   limiter (Firestore/Redis) for a true global cap.
4. Per-UID and global daily quotas are enforced, but they are per function
   instance, not shared across instances. Use a shared store for a hard
   cross-instance cap.
5. Gemini streaming is not used; responses arrive after the tool loop and are
   rendered with loading/typing states.
6. Month comparisons use calendar months (the dashboard uses salary cycles);
   the assistant always states the exact range it used.
7. Deletion undo depends on the local encrypted audit record (last 20 changes).
