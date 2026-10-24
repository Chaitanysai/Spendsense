# SpendSense spending semantics

This document fixes what each money figure on the Home, Payment Instruments
and category screens means. It exists because Home and Payment Instruments used
to answer different questions while both being labelled as spending.

## Canonical scope

A **spending** figure for a period is the sum of `amountMinor` over rows that
satisfy *all* of:

1. `type == TransactionType.expense` (income never counts as spending),
2. `isExcluded == false` (the user's exclusion switch is authoritative),
3. the transaction date falls inside the period, inclusive of both the start
   day and the end day, compared in **local time** as calendar days.

Implemented once in `TransactionProvider.expensesInPeriod` /
`spendingTotalForPeriod`. Every screen that says "spent" for a period must use
it; the only exception is a deliberately all-time roll-up, which must say so.

## Payment instruments

`TransactionProvider.spendingStatsForPeriod(period, keyOf)` groups the **same
row set** by payment method, bank or account. Consequences:

- Summing every `spent` value in the returned map equals the canonical total
  exactly.
- Income rows are ignored entirely, including refunds credited to an
  instrument. A refund is money coming back, not spending.
- Null, blank and the stored `Others` label all collapse into a single
  `Other` bucket.
- Instrument percentages use the scoped total as the denominator, so the bars
  always add up to 100% (or less when some rows have no instrument).

`TransactionProvider.statsBy` remains the all-time, income-inclusive roll-up
used only where an all-time view is intended. Screens must not use it for a
period figure.

## Refunds, reversals and transfers

The stored model has no dedicated refund, reversal or transfer type; direction
is carried by `TransactionType`, and amounts are non-negative magnitudes.

| Case | Rule |
| --- | --- |
| Refund recorded as `income` | Excluded from spending and from instrument spend. |
| Refund recorded as an `expense` (sign lost upstream) | Counts as spending. Documented limitation; correcting it requires a schema change, which is out of scope here. |
| Transfer between own accounts | Must be marked `isExcluded` by the user; there is no transfer flag. Otherwise it counts as spending on both legs. |
| Pending / failed payment | Not modelled; only parsed completed transactions exist. |

## Duplicates

Each stored transaction is counted once per its own `id`. SMS ingestion is
idempotent by message id, so a repeated sync does not add a second row. Two
*distinct* rows with the same merchant and amount are treated as two real
payments; SpendSense does not silently de-duplicate user data.

## Rounding and formatting

All arithmetic is integer paise. No floating-point value is ever used as a
source of truth for money. Formatting happens only at the display boundary
(`Formatters.currency`).

## Period shown

- Home's balance card shows the active period from `PeriodProvider`
  (salary-aligned by default).
- Payment Instruments shows the same period and prints its date range in the
  hero so the scope is visible.
- Activity is unfiltered by default and lets the user choose any range; it is
  a browsing screen, not a spending total.
