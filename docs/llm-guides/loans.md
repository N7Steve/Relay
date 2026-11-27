# Loans and mortgages

Read [architecture](architecture.md) and the [financial effects matrix](financial-effects.md)
first. Loan code lives in [`Loan`](../../app/models/loan.rb) and `app/models/loan/`.
This guide covers the model, the decisions behind it (approved by the owner in
November 2026), the invariants to preserve and the operating procedures.

## Why it exists

Spanish variable mortgages were the driver: a fixed opening period, then an
index (12-month Euribor) plus a spread, discounted by bonuses for holding
other products with the lender, revised yearly, with interest accrued per day.
A plain loan account cannot represent that: each instalment transfer reduced
the debt by its full amount (interest included), so the balance drifted from
the lender's by every euro of interest paid, and nothing explained the rate.
The goal is to reproduce the lender's statement **to the cent**, keep past
figures frozen, project the future, and protect the account from mistakes.

Validated reference case (a real Bankinter mortgage; the numbers are in
[`StructuredLoanTestHelper`](../../test/support/structured_loan_test_helper.rb)):
157,500 over 360 months from 12 Dec 2025, 1.50% the first year, daily accrual,
instalment 543.56. After 11 instalments the debt is **153,665.10** — the
lender's figure — with 3,834.90 of principal and 2,144.26 of interest repaid.
Monthly accrual (rate / 12) gives 153,662.55 instead. Keep these assertions.

## Glossary

| Term | Meaning in code |
| --- | --- |
| Tramo | `Loan::RatePeriod`: fixed (`base_rate`) or variable (`reference_index` + `spread`), with `floor_rate`, `review_interval_months`, `applies_bonuses`, optional `lender_name` |
| Bonificación | `Loan::RateBonus`: points off the rate while a product is held; `annual_cost` lets the UI show whether it pays for itself |
| Revisión | `Loan::RateRevision`: the rate from one date on, frozen with all its inputs |
| Euríbor | `ReferenceRate` (`index_key = "euribor_12m"`), monthly averages |
| Cuota | The level instalment; on a managed loan, paid by the loan's Agenda series |
| Amortización anticipada | `Loan::Prepayment` with `reduce_payment` or `reduce_term` |
| Novación / subrogación | A new `RatePeriod` (to fixed, or with another lender) — never an edit of past periods |

## Two ways a loan gets its rate

- **Columns** (any loan without rate periods): `interest_rate`, `rate_type` and
  the `variable_rate_schedule` JSON. [`Loan::RateResolver`](../../app/models/loan/rate_resolver.rb)
  reads them exactly as before this work. Such loans must behave as they always did.
- **Structured** (`Loan#structured_rate?`, true once a period exists):
  [`Loan::RateReviewer`](../../app/models/loan/rate_reviewer.rb) builds one
  revision per review date across all periods, and the resolver reads only
  revisions (binary search; the daily simulator asks for every day).

Revision rate = max(base − bonus points, floor), where base is the fixed rate or
the index value (three decimals, as published) + spread, and bonus points are
the active bonuses' points when the period `applies_bonuses`.

### Recorded vs projected revisions

- A revision whose date has arrived is **recorded** (`record_due!`, daily job or
  any terms change) and then read back as stored. Later changes to bonuses or
  index values never move it: that is how interest already charged stays fixed.
- Revisions still ahead are **projected** on every read from the current
  periods, bonuses and an [`IndexScenario`](../../app/models/loan/index_scenario.rb)
  (latest published value held flat, optionally shifted).
- A revision takes the index average of **the month before its own month** (the
  deed's "último índice publicado"). It is recorded once that month is stored,
  or after `INDEX_GRACE_DAYS` with the latest stored month. Projected revisions
  are labelled with the month their value really comes from.
- A review date with no index value at all is an **index gap**
  (`first_index_gap`): the ledger posts nothing past it and the Agenda
  instalment after it keeps its last amount until the value arrives.
- Editing or deleting a period re-records the *calculated* revisions from its
  start (`prune!(from:)`); "Recalcular no confirmadas" re-records all of them.
  **Confirmed** revisions (corrected from the lender's notice) are never touched.

## The engine

[`Loan::Simulator`](../../app/models/loan/simulator.rb) walks payment periods:

- `day_count: :actual_365` charges each day at the rate in force that day over
  the days of its year (366 in leap years) and rounds once per period — the
  deed formula "capital × rédito × días / 36.500 (36.600 bisiesto)". Days are
  grouped into runs of equal rate and year length (`accrued_interest`).
  `:monthly` (rate / 12) remains the default for other loans.
- Instalments are always sized with the annuity formula at rate / 12, as deeds
  define them, so the last payment absorbs the convention difference.
- `payment_sizing: :period_opening` (structured loans): a revision effective on
  a payment date leaves that day's instalment unchanged and resizes the next.
- `prepayments:` lower the balance from their date. `reduce_payment` re-sizes
  over the payments left; `reduce_term` keeps the instalment and brings the end
  (`term_end`) forward, and later revisions re-size over the shortened term. A
  revision landing with a reduce-term prepayment sizes the instalment on the
  balance before the prepayment, then keeps it.

[`AmortizationSchedule.for(loan, rate_reviewer:, prepayments:)`](../../app/models/loan/amortization_schedule.rb)
is the contractual schedule (recorded prepayments included); `Loan::Scenario`
passes hypothetical reviewers/prepayments to it.

## Posted interest (the ledger)

With `loans.interest_tracking`, [`Loan::InterestLedger`](../../app/models/loan/interest_ledger.rb)
posts each period's interest to the loan account as a `loan_interest`
Transaction (entry `source = "loan_interest"`, `external_id` = payment date ISO).

- It runs in `Account::Recalculator` before balances are materialized, i.e. on
  every sync of the loan account (any movement, revision or terms change).
- It recomputes the whole history each time from the account's real movements
  and is idempotent: one entry per payment date, updated or removed as needed.
- An instalment-sized transfer within four days of its due date counts on the
  due date (value date); other money counts from the day it lands.
- An account whose history starts after origination (opening valuation later)
  starts at the payment date on or before that valuation, with its amount —
  nothing is invented for earlier years.
- Each entry stores how it was worked out in `transactions.extra["loan_interest"]`
  (`from`, `to`, `days`, `average_balance`, `rates`, `accrual`) for its read-only
  detail view (`loans/interest_entries/show`, rendered by `TransactionsController#show`).
- `loan_interest` is excluded from budgets/income statements (the `loan_payment`
  instalment is already the expense — counting interest too would double it),
  from uncategorized lists, splitting, transfer matching and rules. Net worth is
  correct because the debt now includes interest.

## Contract-managed loans (closed account)

Owner decision: a loan that posts its interest is a **closed contract**
(`Loan#contract_managed?` == `interest_tracking?`). Its account only takes:

1. the opening principal (opening-anchor valuation);
2. the interest the ledger posts;
3. the instalment from the Agenda series the loan owns;
4. prepayments recorded from the loan (which create their own transfer).

[`Entry::LoanContractGuard`](../../app/models/entry/loan_contract_guard.rb)
rejects every other create, change (except notes) or removal, from any path;
`Transaction` rejects category/merchant changes on contract entries. The loan's
own flows write inside [`Loan::ContractWrites.allow`](../../app/models/loan/contract_writes.rb):
the ledger, `ScheduledPaymentEntry#with_payment_lock` for a loan-owned series,
and `Loan::PrepaymentRecorder`. Whole-account deletion works
(`destroyed_by_association`); "foreign" entries left from before the loan was
managed can be removed and are listed on the Interest rate tab
(`Loan#foreign_entries`). Up front, transfers exclude managed loans, bulk
edits/deletions skip their contract entries and rules skip their transactions;
[`LoanContractProtection`](../../app/controllers/concerns/loan_contract_protection.rb)
turns any remaining rejected write into an alert. **A new case is added as code
in `ContractWrites`, never opened up as a manual edit.**

### The instalment series

`scheduled_payments.loan_id` (unique) marks the Agenda series the loan owns
(`Loan#adopt_instalment_series!` adopts an existing monthly transfer into the
loan or creates one). Each occurrence pays `ScheduledPayment#amount_for(date)`,
the schedule's instalment for that month (plus any premium), ignoring typed
overrides. Owner decision: the series is the contract's payment order, so
Agenda (web and API/MCP) shows it read-only (`scheduled_payments/loan_series`)
and cannot edit, pause or delete it; confirming an occurrence only picks the
date and shows the contract's amount. `Loan#sync_scheduled_payments!` keeps the stored
amount at the next occurrence's instalment (daily job, terms changes). A series
into a managed loan that the loan does not own is invalid.

## Net worth

Owner decision: a mortgage (`Loan#mortgage?`) is part of the finances but not
of net worth. It stays listed under loans and feeds reports and Agenda, while
`BalanceSheet` totals and the net worth series skip it
(`Account.included_in_net_worth`). A mortgage cannot be "outside my finances";
`IncludeMortgagesInFinances` moved existing ones back in and reclassified
their transfers.

## Prepayments and scenarios

[`Loan::PrepaymentRecorder`](../../app/models/loan/prepayment_recorder.rb)
records a `Loan::Prepayment` and creates the transfer from a same-currency
account (with the fee on the paying side); on a managed loan the source account
is required, and `remove` deletes the transfer too. On unmanaged loans it can
instead link an existing movement.

[`Loan::Scenario`](../../app/models/loan/scenario.rb) (Scenarios tab, lazy turbo
frame, stateless GET form) compares the loan with a hypothetical period (final
rate, optional bonuses, one-off cost) and/or a prepayment under an index shift,
plus a sensitivity table for Euribor −1/0/+1/+2. Hypothetical periods and
projected revisions are built **by `loan_id`, never through the association**:
with `has_many` inversing (`load_defaults 8.1`) an unsaved record built via
`loan:` joins the loan's collections in memory and would leak into real figures.

## Index values

[`ReferenceRate`](../../app/models/reference_rate.rb) is instance-wide, like
`ExchangeRate`. Owner decision: Euribor is downloaded automatically.
`ImportReferenceRatesJob` (daily 05:00 UTC) imports the ECB monthly series
(`FM/M.U2.EUR.RT.MM.EURIBOR1YD_.HSTA`, matches the BOE/Banco de España figure
to three decimals) through [`Provider::Ecb`](../../app/models/provider/ecb.rb)
only when the `reference_rates` external capability is on (Settings ›
Self-hosting, or `RELAY_EXTERNAL_REFERENCE_RATES_ENABLED`; off by default like
every external capability). It fetches back to the earliest period that needs
it, then runs `ReviewLoanRatesJob` (record due revisions, sync instalments,
resync accounts). Super admins can type values by hand — index values affect
every family. This capability fetches only the index; prices and FX still have
no provider (phase 9A).

## Product decisions (November 2026)

- Reproduce the lender exactly: daily accrual for Spanish mortgages.
- Revisions are frozen history; only unrecorded ones move. Confirmed revisions
  come from the lender's notice and are never recalculated.
- Budgets keep the full instalment as the housing expense; interest is shown in
  the loan (overview split, entry detail), not double-counted in reports.
- Automatic Euribor download approved (opt-in capability).
- Managed loans are closed contracts; the instalment is owned by the loan, not
  typed in Agenda (read-only there); prepayments are managed from the loan.
- Mortgages are kept out of net worth, not out of the finances. Edge cases are added
  as code after discussing them.

## Operating procedures

**Set up a Spanish variable mortgage**: edit the loan (original balance, start
date, term, rate type variable, accrual Daily, Post interest on). On the
Interest rate tab add the fixed period from origination (rate *before* bonuses),
the variable period from the first revision (index + spread before bonuses) and
each bonus with its annual cost. Link the Agenda instalment (Instalment and
movements › Link). The debt must then match the lender's statement.

**Wrong result**: check the periods (a missing fixed opening period is the
usual cause), then "Recalcular no confirmadas". A stray balance valuation or
manual movement on the account is listed under "Movements outside the
contract"; remove it. Confirm each revision against the lender's letter.

**Verify after changes**: the reference case above; `bin/rails test
test/models/loan test/controllers/loans` plus the full suite.

## Tests

Use [`StructuredLoanTestHelper`](../../test/support/structured_loan_test_helper.rb)
(`build_structured_mortgage`, `store_euribor`, `mortgage_payment_dates`). Writes
to a managed loan's account in tests must go through `Loan::ContractWrites.allow`.
Main files: `test/models/loan/{structured_rate,interest_ledger,prepayment,scenario,contract}_test.rb`,
`test/models/reference_rate/importer_test.rb`, `test/controllers/loans/rate_terms_controller_test.rb`.
New migrations touching these tables are appended to
`test/migrations/remove_retired_product_persistence_migration_test.rb`.

## Known limits and next steps

- Late-payment interest and fees on missed instalments are not modelled; a
  missed instalment simply leaves the debt higher.
- No "check against the lender" action yet (enter the bank's figure, show the
  difference without overwriting); manual balance edits are blocked instead.
- Bonus compliance (annual control dates) is a manual on/off per bonus.
- Insurance premiums paid separately are bonus costs, not loan cash flows.
