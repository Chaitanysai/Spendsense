# Ledger sync design

Cloud sync for transactions on top of the existing local-first ledger. Budgets,
bills and recurring plans are a later phase; the account profile already syncs
(`users/{uid}`).

## What syncs

One Firestore document per transaction at
`users/{uid}/transactions/{syncId}`. Documents are written by the device that
made the change and read by every signed-in device.

Not uploaded: `originalSms` (the raw bank message), the encryption key, the
device key, and anything derived (totals, statuses, monthly equivalents).

## Identity

- `syncId` — 32 hex characters, generated once per transaction, stored in the
  encrypted local record. This is the document id. It is deliberately not the
  local `id`: SMS ids are inbox row numbers and manual ids are timestamps, so
  both can collide across devices or change when an inbox is re-indexed.
- `updatedAtMs` — client clock, stamped by `TransactionProvider` on every
  mutation. `0` means "legacy record, older than anything else".

## Conflict resolution

Last-write-wins on `updatedAtMs`, with `deviceId` as a deterministic tie-break
when two devices land on the same millisecond. The rule is applied per record,
never per collection, so two devices editing different transactions never
interfere.

Consequences that are accepted and documented rather than hidden:
an edit made offline on an old clock can lose to a newer edit from another
device. Clock skew is bounded in practice by both devices being online when
they sync; there is no server-side version field to arbitrate further.

## Deletion

Deleting writes a tombstone document (`deletedAtMs` set, transaction fields
absent) instead of removing the row, so a device that was offline cannot
resurrect it. Tombstones are pruned locally and remotely after 30 days.

Locally, deleting is still immediate for the user: the transaction leaves the
UI and the totals at once, and the tombstone is bookkeeping only.

## Pull

`TransactionSyncRepository.watch` streams the account's documents. For each
remote record the service compares `updatedAtMs` with the local value:

| Remote | Local | Action |
| --- | --- | --- |
| newer | older, present | upsert the local record, then reload the provider |
| older | newer | ignore: the local copy will be pushed |
| tombstone | present | remove locally, without creating a second tombstone |
| any | absent | upsert; this is a fresh install catching up |

## Push

Each sync cycle pushes local records whose `updatedAtMs` is newer than the last
successfully pushed stamp (persisted per account), in batches of 400 writes.
Pushes are debounced after local mutations and are skipped entirely when
signed out or offline.

## Guarantees this does not provide

- No real-time collaborative editing of the same transaction.
- No cross-account sharing.
- No encryption of the cloud copy beyond Firestore's at-rest encryption: a
  literal end-to-end model would need a key that survives device loss, which is
  a separate product decision (see "Open question" below).

## Open question

The local ledger is encrypted with a device-bound Keystore key. Syncing
plaintext records means the cloud copy is protected by Firebase Auth plus
Firestore rules and at-rest encryption, not by the ledger key. A future option
is a passphrase-derived sync key so the cloud only ever holds ciphertext —
that trades "works silently on a new phone" for "the user must remember one
more secret". Not implemented in this phase.
