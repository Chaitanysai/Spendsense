# Email import (Gmail)

SpendSense can read bank **alert emails** from Gmail in addition to SMS. This is
for banks that send transaction alerts by email instead of SMS.

## What it does

- Read-only Gmail access (`gmail.readonly`). SpendSense cannot send, delete,
  label or modify mail.
- Messages are fetched **directly to the phone**; there is no SpendSense email
  backend and no mailbox upload.
- Only messages whose `From` domain is on the sender allowlist, and whose
  subject looks like a debit/payment alert, are considered.
- The email body is converted to plain text in memory, parsed with the same
  local `SmartParser` used for SMS, and discarded. The ledger stores the derived
  transaction with `source = "Email-Gmail"`.
- Dedupe key is `gmail:<messageId>`, so a repeated sync imports each message at
  most once.
- Email import is **off by default** and has its own consent dialog, separate
  from SMS cloud parsing.

## What it does not do

- It does not read other people's mailboxes, spam folders, or sent mail.
- It does not store Gmail credentials. The OAuth token is held by
  `google_sign_in` for the app process; Disconnect signs out of Google and
  clears the consent flag.
- It does not run in the background. Sync happens when the person taps
  **Sync now** (or when the screen is opened and they press the button).

## Setup (one-time, Google Cloud)

1. Open **Google Cloud Console → APIs & Services** for the Firebase project
   (`spendsense-ota-2026`).
2. Enable **Gmail API**.
3. **OAuth consent screen**:
   - User type: External (or Internal if a Workspace org).
   - Add scope `https://www.googleapis.com/auth/gmail.readonly`.
   - Add test users while the app is in Testing.
   - Note: `gmail.readonly` is a **restricted scope**. Publishing beyond test
     users requires Google verification and a CASA security assessment.
4. **Credentials → Create credentials → OAuth client ID → Android**:
   - Package name: `com.example.spendsense`
   - SHA-1 of the **release** signing certificate:
     `f065b50f45c47da34adda47f9bab6d5b002bcb52`
     (DN: `CN=chaitanya.sai, OU=me, O=Mine, L=Hyderabad, ST=Telangana, C=IN`;
     SHA-256: `42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367`)
   - Also add the debug keystore SHA-1 if you want to test locally.
5. The Android OAuth client does **not** expose a client secret. SpendSense
   reads the client configuration from Google Play services; no secret needs to
   be shipped. The optional `GMAIL_SERVER_CLIENT_ID` define is only needed if
   the Google project uses a separate web/server OAuth client (for example, to
   test on the Android emulator).
6. To ship the define in OTA builds, set the repository variable
   `GMAIL_SERVER_CLIENT_ID` to that client ID. The OTA workflow passes it as
   `--dart-define`. Leave the variable unset to ship with email import
   configured off.

## Testing

1. Connect Gmail in **Settings → Email import**.
2. Confirm the consent dialog lists the read-only scope and the sender domains.
3. Send yourself a test email from an allowlisted sender with a debit subject
   (or use a Gmail filter to copy a sample bank alert).
4. Tap **Sync now**; the transaction should appear with source `Email-Gmail`.
5. Tap **Sync now** again; it must not create a duplicate.
6. **Disconnect**; the consent flag and Google session are cleared.

## Notes and limits

- Bank HTML emails vary. Add a bank domain only after checking a real alert's
  sender address; the allowlist compares exact domains, so
  `hdfcbank.net.evil.example` is rejected.
- Email alerts can be delayed or batched by the bank; this feature does not
  guarantee real-time capture.
- If a bank sends both SMS and email for the same transaction, both can be
  imported because they are different sources. Review duplicates in the
  ledger; a future matching pass can reconcile them.
- Google may require app verification before non-test users can consent to a
  restricted scope. Plan for that lead time before public distribution.
