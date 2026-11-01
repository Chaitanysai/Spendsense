# SpendSense

## What it is

An offline-first Android expense tracker for Indian bank and UPI SMS. It reads the
transaction messages a bank already sent you, parses them on the phone, and turns
them into a searchable ledger with budgets and insights. The ledger is encrypted on
the device with AES-256-GCM; the key lives in the Android Keystore.

Distributed as a signed APK from GitHub Releases, with self-update through a
signed-manifest OTA channel at `https://spendsense-ota-2026.web.app`.

## Audience

Indian Android users who already receive UPI and bank debit SMS and want a record
of what they spent without handing bank credentials to an aggregator. They are
sceptical of finance apps that want a login, want an account, want to connect a
bank, or want a subscription. Many have been burned by an app that lost their
history or started charging.

## The mechanism that is actually ours

**The phone already contains the ledger.** Every UPI payment, card swipe and
account debit has already been delivered to the user as an SMS. SpendSense reads
what is already there rather than asking for access to anything new. That is why
there is no bank login, no aggregator, no OAuth-to-your-bank, and no reason for the
data to leave the device.

## What is true, and what is not

True, and demonstrable in the product:

- Reads SMS from the device inbox; parses on device.
- Local SQLite ledger, AES-256-GCM encrypted, key in the Android Keystore.
- Works offline. Opens and records without a network.
- No advertising. No advertising SDK. No analytics SDK. No crash-reporting SDK.
- No data sale.
- No bank credentials, card numbers or UPI PIN ever requested.
- Optional cloud features are each off by default: account + sync, AI-assisted SMS
  parsing, the assistant, and Gmail import.
- Gmail import uses read-only scope (`gmail.readonly`) and never sends or modifies mail.
- Free. No subscription, no in-app purchase, no ads.

Not true, and must not appear anywhere:

- Any user count, download count, App Store rating, testimonial, or press mention.
- "Bank-grade security", "military-grade encryption", "unhackable".
- Any claim of automatic categorisation accuracy.
- Any claim that it is a budgeting *adviser*, or that it gives financial advice.
- Any claim that data is backed up for the user. It is not. The ledger is on the
  device; the user must export if they want a copy.

## Constraints

- Android 7.0+ only. There is no iOS build and no web app.
- Install is side-loaded from GitHub Releases, not from Google Play (yet).
- `applicationId` is still `com.example.spendsense`; unknown when evaluated.
- No payments of any kind, now or planned for this surface.
- The OTA manifest and `releases/` paths on the hosting domain must not be touched
  by any page work; installed builds depend on them.

## Surface in hand

`https://spendsense-ota-2026.web.app/` — currently a plain typographic landing page.
Mode: **Persuade**. The visitor is deciding whether to install a finance app that
reads their SMS. The page must make that decision easy by proving the app asks for
less than they expect, and then hand them the download.

## Brand commitments

- Palettes in the app are named and premium (`premium_blue` ships `#141E30` dark
  card on `#0B1220` canvas). The product's own visual world is dark navy glass.
- Icons are drawn, consistent stroke. No emoji as iconography.
- Type in the app is Poppins / Space Grotesk / Geist / Inter, all SIL OFL and
  bundled.
