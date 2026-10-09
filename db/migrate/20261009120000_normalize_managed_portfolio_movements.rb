# Data-only normalization: no account names, categories, CSVs or user IDs.
# SQL deliberately avoids application callbacks and preserves every Entry,
# relationship, original amount, exclusion, lock and provider payload.
class NormalizeManagedPortfolioMovements < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE transactions t
      SET kind = CASE
            WHEN t.investment_activity_label IN ('Contribution', 'Withdrawal') THEN 'investment_contribution'
            ELSE 'investment_value_adjustment'
          END,
          extra = COALESCE(t.extra, '{}'::jsonb) || jsonb_build_object('managed_portfolio_migration', jsonb_build_object(
            'version', 1, 'original_kind', t.kind, 'original_activity_label', t.investment_activity_label
          ))
      FROM entries e
      JOIN accounts a ON a.id = e.account_id
      JOIN investments i ON a.accountable_type = 'Investment' AND i.id = a.accountable_id
      WHERE e.entryable_type = 'Transaction' AND e.entryable_id = t.id
        AND CASE WHEN NULLIF(to_jsonb(i)->>'tracking_mode', '') IS NOT NULL
          THEN to_jsonb(i)->>'tracking_mode' = 'managed'
          ELSE i.subtype IN ('roboadvisor', 'managed_fund') OR a.managed_portfolio
        END
        AND t.kind IN ('standard', 'one_time')
        AND (t.investment_activity_label IS NULL OR t.investment_activity_label IN ('Other', 'Dividend', 'Interest', 'Fee', 'Contribution', 'Withdrawal'))
        AND NOT EXISTS (SELECT 1 FROM transfers x WHERE x.inflow_transaction_id = t.id OR x.outflow_transaction_id = t.id)
        AND t.transfer_id IS NULL
        AND NOT EXISTS (SELECT 1 FROM entries child WHERE child.parent_entry_id = e.id)
    SQL
  end

  def down
    # Keep new absolute updates native when rolling back the normalization.
    execute <<~SQL
      UPDATE transactions SET
        kind = extra->'managed_portfolio_migration'->>'original_kind',
        extra = extra - 'managed_portfolio_migration'
      WHERE extra->'managed_portfolio_migration'->>'version' = '1'
        AND kind IN ('investment_value_adjustment', 'investment_contribution')
        AND NOT (extra ? 'investment_value')
    SQL
  end
end
