# Mortgages are part of the user's finances; they are now kept out of net
# worth by their subtype (Account.included_in_net_worth) instead of being
# placed outside the finances boundary. Mortgage accounts left outside the
# boundary move back in, and the transfers that crossed it are reclassified
# as Transfer.outflow_kind_for / inflow_kind_for would now classify them.
class IncludeMortgagesInFinances < ActiveRecord::Migration[8.1]
  MORTGAGES = <<~SQL.squish
    SELECT accounts.id FROM accounts
    JOIN loans ON loans.id = accounts.accountable_id
    WHERE accounts.accountable_type = 'Loan'
      AND loans.subtype = 'mortgage'
      AND accounts.cashflow_boundary = TRUE
  SQL

  def up
    # Into the mortgage: the outflow is a loan payment, the inflow a movement.
    execute <<~SQL.squish
      UPDATE transactions SET
        kind = CASE WHEN transactions.id = transfers.outflow_transaction_id THEN 'loan_payment' ELSE 'funds_movement' END,
        updated_at = CURRENT_TIMESTAMP
      FROM transfers
      JOIN entries inflow_entries ON inflow_entries.entryable_type = 'Transaction'
        AND inflow_entries.entryable_id = transfers.inflow_transaction_id
      WHERE transactions.id IN (transfers.outflow_transaction_id, transfers.inflow_transaction_id)
        AND transactions.kind = 'transfer_to_excluded'
        AND inflow_entries.account_id IN (#{MORTGAGES})
    SQL

    # Out of the mortgage (a disbursement): classified by its destination.
    execute <<~SQL.squish
      UPDATE transactions SET
        kind = CASE
          WHEN transactions.id = transfers.inflow_transaction_id THEN 'funds_movement'
          WHEN destination.accountable_type = 'Loan' THEN 'loan_payment'
          WHEN destination.classification = 'liability' THEN 'cc_payment'
          WHEN destination.accountable_type IN ('Investment', 'Crypto') THEN 'investment_contribution'
          ELSE 'funds_movement'
        END,
        updated_at = CURRENT_TIMESTAMP
      FROM transfers
      JOIN entries outflow_entries ON outflow_entries.entryable_type = 'Transaction'
        AND outflow_entries.entryable_id = transfers.outflow_transaction_id
      JOIN entries inflow_entries ON inflow_entries.entryable_type = 'Transaction'
        AND inflow_entries.entryable_id = transfers.inflow_transaction_id
      JOIN accounts destination ON destination.id = inflow_entries.account_id
      WHERE transactions.id IN (transfers.outflow_transaction_id, transfers.inflow_transaction_id)
        AND transactions.kind = 'transfer_from_excluded'
        AND outflow_entries.account_id IN (#{MORTGAGES})
    SQL

    execute <<~SQL.squish
      UPDATE accounts SET
        cashflow_boundary = FALSE,
        exclude_from_reports = FALSE,
        financial_treatment = 'included',
        updated_at = CURRENT_TIMESTAMP
      WHERE id IN (#{MORTGAGES})
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
