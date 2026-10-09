class NormalizeManagedOperationNamesAndCategories < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      #{normalization_sql}
      UPDATE transactions t SET
        category_id = NULL,
        extra = COALESCE(t.extra, '{}'::jsonb) || jsonb_build_object(
          'native_managed_operation', n.operation,
          'native_operation_original', COALESCE(t.extra->'native_operation_original', jsonb_build_object(
            'version', 1, 'name', e.name, 'category_id', t.category_id,
            'category_name', (SELECT name FROM categories WHERE id = t.category_id)
          ))
        )
      FROM normalized n JOIN entries e ON e.id = n.entry_id
      WHERE t.id = n.transaction_id
    SQL
    execute <<~SQL
      #{normalization_sql}
      UPDATE entries e SET name = n.name
      FROM normalized n WHERE e.id = n.entry_id
    SQL
  end

  def down
    execute <<~SQL
      UPDATE entries e SET name = t.extra->'native_operation_original'->>'name'
      FROM transactions t WHERE e.entryable_type = 'Transaction' AND e.entryable_id = t.id
        AND t.extra->'native_operation_original'->>'version' = '1'
    SQL
    execute <<~SQL
      UPDATE transactions t SET category_id = (
        SELECT id FROM categories WHERE id = (t.extra->'native_operation_original'->>'category_id')::uuid
      ), extra = t.extra - 'native_operation_original' - 'native_managed_operation'
      WHERE t.extra->'native_operation_original'->>'version' = '1'
    SQL
  end

  private
    # Work on persisted domain types and paired legs, never on legacy titles or
    # category names. Neither entries nor monetary relationships are recreated.
    def normalization_sql
      <<~SQL
        WITH managed AS (
          SELECT a.id, a.name, a.family_id FROM accounts a
          JOIN investments i ON a.accountable_type = 'Investment' AND i.id = a.accountable_id
          WHERE CASE WHEN NULLIF(to_jsonb(i)->>'tracking_mode', '') IS NOT NULL
            THEN to_jsonb(i)->>'tracking_mode' = 'managed'
            ELSE i.subtype IN ('roboadvisor', 'managed_fund') OR a.managed_portfolio END
        ), normalized AS (
          SELECT e.id AS entry_id, t.id AS transaction_id,
            CASE WHEN t.kind = 'investment_value_adjustment' THEN 'valuation'
              WHEN e.amount < 0 THEN 'contribution' ELSE 'withdrawal' END AS operation,
            CASE WHEN t.kind = 'investment_value_adjustment' THEN
              (CASE WHEN f.locale LIKE 'es%' THEN 'Valoración ' ELSE 'Valuation ' END) || to_char(e.date, 'DD/MM/YYYY')
            ELSE (CASE WHEN e.amount < 0 THEN
              CASE WHEN f.locale LIKE 'es%' THEN 'Aportación · ' ELSE 'Contribution · ' END
            ELSE CASE WHEN f.locale LIKE 'es%' THEN 'Retirada · ' ELSE 'Withdrawal · ' END END) || a.name END AS name
          FROM entries e JOIN transactions t ON e.entryable_type = 'Transaction' AND e.entryable_id = t.id
          JOIN managed a ON a.id = e.account_id JOIN families f ON f.id = a.family_id
          WHERE t.kind = 'investment_value_adjustment' OR (
            t.kind = 'investment_contribution' AND NOT EXISTS (
              SELECT 1 FROM transfers x WHERE x.inflow_transaction_id = t.id OR x.outflow_transaction_id = t.id
            )
          )
          UNION ALL
          SELECT legs.entry_id, legs.transaction_id,
            CASE WHEN fm.id IS NOT NULL AND tm.id IS NOT NULL THEN 'transfer'
              WHEN tm.id IS NOT NULL THEN 'contribution' ELSE 'withdrawal' END,
            CASE WHEN fm.id IS NOT NULL AND tm.id IS NOT NULL THEN
              (CASE WHEN f.locale LIKE 'es%' THEN 'Traspaso · ' ELSE 'Portfolio transfer · ' END) || fa.name || ' → ' || ta.name
            WHEN tm.id IS NOT NULL THEN
              (CASE WHEN f.locale LIKE 'es%' THEN 'Aportación · ' ELSE 'Contribution · ' END) || ta.name
            ELSE (CASE WHEN f.locale LIKE 'es%' THEN 'Retirada · ' ELSE 'Withdrawal · ' END) || fa.name END
          FROM transfers x
          JOIN entries oe ON oe.entryable_type = 'Transaction' AND oe.entryable_id = x.outflow_transaction_id
          JOIN entries ie ON ie.entryable_type = 'Transaction' AND ie.entryable_id = x.inflow_transaction_id
          JOIN accounts fa ON fa.id = oe.account_id JOIN accounts ta ON ta.id = ie.account_id AND ta.family_id = fa.family_id
          JOIN families f ON f.id = fa.family_id
          LEFT JOIN managed fm ON fm.id = fa.id LEFT JOIN managed tm ON tm.id = ta.id
          CROSS JOIN LATERAL (VALUES (oe.id, x.outflow_transaction_id), (ie.id, x.inflow_transaction_id)) legs(entry_id, transaction_id)
          WHERE fm.id IS NOT NULL OR tm.id IS NOT NULL
        )
      SQL
    end
end
