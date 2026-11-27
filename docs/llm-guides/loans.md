# Loans: schedules, structured rates and posted interest

Read [architecture](architecture.md) and the [financial effects matrix](financial-effects.md)
first. Loan code lives in [`Loan`](../../app/models/loan.rb) and `app/models/loan/`.

## Two ways a loan gets its rate

- **Columns** (every loan before November 2026, and any loan without rate periods):
  `interest_rate`, `rate_type` and the `variable_rate_schedule` JSON of
  `date → rate` changes. [`Loan::RateResolver`](../../app/models/loan/rate_resolver.rb)
  reads them as it always has.
- **Structured** (`Loan#structured_rate?`, true once the loan has a
  [`Loan::RatePeriod`](../../app/models/loan/rate_period.rb)): fixed or
  index-linked periods (index + spread), a floor, a review interval, and
  [`Loan::RateBonus`](../../app/models/loan/rate_bonus.rb) discounts.
  [`Loan::RateReviewer`](../../app/models/loan/rate_reviewer.rb) turns them into
  one revision per review date. The resolver then reads only revisions.

Revisions whose date has arrived are recorded as
[`Loan::RateRevision`](../../app/models/loan/rate_revision.rb) rows with every
input frozen (index month and value, spread, bonus points). Later changes to
periods, bonuses or index values move only unrecorded revisions; recorded
interest never changes after the fact. A user can confirm or correct a recorded
revision from the lender's notice (`status = confirmed`) or delete it so it is
recorded again. Future revisions are projected by
[`Loan::IndexScenario`](../../app/models/loan/index_scenario.rb), by default the
latest published value held flat.

A revision takes the index average of the month before its own month (the
Spanish "último índice publicado"). It is recorded once that month is stored,
or with the latest stored month after `RateReviewer::INDEX_GRACE_DAYS`.

## Accrual conventions

`loans.interest_accrual` is `monthly` (rate / 12 per period, the historical
default) or `daily` (each day at rate / 365, 366 in leap years, rounded once per
period: Spanish deeds). [`Loan::Simulator`](../../app/models/loan/simulator.rb)
takes `day_count:` (`:monthly`/`:actual_365`) and `payment_sizing:`.
Structured loans use `:period_opening` sizing, so a revision effective on a
payment date leaves that payment unchanged and resizes the next one. Instalments
are always sized with the annuity formula at rate / 12.

## Posted interest

With `loans.interest_tracking`, [`Loan::InterestLedger`](../../app/models/loan/interest_ledger.rb)
posts each period's interest to the loan account as a `loan_interest`
Transaction (entry `source = "loan_interest"`, `external_id` = payment date).
It runs inside `Account::Recalculator` before balances are materialized. It
accrues daily on the account's real history (payments, extra payments and
valuations), treats an instalment transfer within four days of its due date as
paid on it, and never overwrites a `user_modified` entry. Instalment transfers
are untouched: the debt falls by principal because interest was charged first.

`loan_interest` is excluded from budgets, income statements, uncategorized
lists, splitting and transfer matching. The `loan_payment` outflow remains the
budget expense, so the interest is not counted twice.

## Index values

[`ReferenceRate`](../../app/models/reference_rate.rb) is instance-wide, like
`ExchangeRate`. `ImportReferenceRatesJob` (daily, `config/schedule.yml`) imports
the monthly 12-month Euribor from the ECB through [`Provider::Ecb`](../../app/models/provider/ecb.rb)
only when the `reference_rates` external capability is enabled (Settings ›
Self-hosting, or `RELAY_EXTERNAL_REFERENCE_RATES_ENABLED`). It then runs
`ReviewLoanRatesJob`, which records due revisions, updates the amount of
active Agenda transfers into the loan for their next occurrence
(`Loan#sync_scheduled_payments!`) and recalculates accounts with new
revisions. Administrators can type index values by hand on the loan's
Interest rate tab.

Security prices and exchange rates still have no provider (phase 9A); this
capability fetches only the index series.

## Prepayments and scenarios

[`Loan::Prepayment`](../../app/models/loan/prepayment.rb) records an extra
repayment and the borrower's choice: `reduce_payment` (same term, re-sized
instalment) or `reduce_term` (same instalment, earlier end; later revisions
re-size over the shortened term). [`Loan::PrepaymentRecorder`](../../app/models/loan/prepayment_recorder.rb)
creates the transfer from a chosen account (with the fee) or links an existing
movement. The simulator takes them as `prepayments:` and, under daily accrual,
charges the period on the balance each day carried. The money itself is an
entry, so posted interest and the balance follow it whether or not the choice
is recorded; only instalment-sized transfers are snapped to a due date.

[`Loan::Scenario`](../../app/models/loan/scenario.rb) compares the loan with a
hypothetical period (fixed or variable, final rate, optional bonuses, one-off
cost) and/or prepayment under an index shift, plus a sensitivity table for
Euribor -1/0/+1/+2. Nothing is saved: hypothetical periods and projected
revisions are built by `loan_id`, never through the association, because with
has_many inversing they would join the loan's collections in memory.
