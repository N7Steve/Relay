# frozen_string_literal: true

class IncomeStatement::MerchantTotals
  include IncomeStatement::ScopedTransactionsQuery

  MerchantRow = Data.define(:merchant_id, :merchant_name, :classification, :total, :transactions_count)

  def initialize(family, transactions_scope:, date_range:, included_account_ids: nil)
    @family = family
    @transactions_scope = transactions_scope
    @date_range = date_range
    @included_account_ids = included_account_ids

    validate_date_range!
  end

  def call
    return [] if @included_account_ids&.empty?

    rows = ActiveRecord::Base.connection.select_all(query_sql)
    validate_conversion_data!(rows)
    rows.map do |row|
      MerchantRow.new(
        merchant_id: row["merchant_id"],
        merchant_name: row["merchant_name"],
        classification: row["classification"],
        total: row["total"].to_d,
        transactions_count: row["transactions_count"].to_i
      )
    end
  end

  private
    def query_sql
      ActiveRecord::Base.sanitize_sql_array([
        <<~SQL,
          SELECT
            m.id AS merchant_id,
            m.name AS merchant_name,
            #{classification_sql("at")} AS classification,
            ABS(SUM(#{converted_amount_sql("at")})) AS total,
            COUNT(ae.id) AS transactions_count,
            #{missing_rate_sql} AS missing_rate
          FROM (#{@transactions_scope.to_sql}) at
          #{entries_join_sql("at")}
          #{accounts_join_sql}
          LEFT JOIN merchants m ON m.id = at.merchant_id
          #{exchange_rates_join_sql}
          WHERE #{budget_inclusion_sql("at")}
            #{investment_activity_label_sql("at")}
            AND ae.excluded = false
            AND a.family_id = :family_id
            AND a.status IN ('draft', 'active')
            AND a.exclude_from_reports = false
            #{exclude_tax_advantaged_sql}
            #{include_finance_accounts_sql}
          GROUP BY m.id, m.name, #{classification_sql("at")}
          ORDER BY total DESC, m.name ASC NULLS LAST
        SQL
        sql_params
      ])
    end

    def sql_params
      params = base_sql_params(start_date: @date_range.begin, end_date: @date_range.end)
      params[:included_account_ids] = @included_account_ids if @included_account_ids
      params
    end
end
