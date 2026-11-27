# frozen_string_literal: true

class IncomeStatement::TagTotals
  include IncomeStatement::ScopedTransactionsQuery

  TagRow = Data.define(:tag_id, :tag_name, :classification, :total, :transactions_count)

  def initialize(family, transactions_scope:, date_range:, tag_ids:, included_account_ids: nil)
    @family = family
    @transactions_scope = transactions_scope
    @date_range = date_range
    @tag_ids = Array(tag_ids)
    @included_account_ids = included_account_ids

    validate_date_range!
  end

  def call
    return [] if @included_account_ids&.empty? || @tag_ids.empty?

    rows = ActiveRecord::Base.connection.select_all(query_sql)
    validate_conversion_data!(rows)
    rows.map do |row|
      TagRow.new(
        tag_id: row["tag_id"],
        tag_name: row["tag_name"],
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
            tg.id AS tag_id,
            tg.name AS tag_name,
            #{classification_sql("at")} AS classification,
            ABS(SUM(#{converted_amount_sql("at")})) AS total,
            COUNT(ae.id) AS transactions_count,
            #{missing_rate_sql} AS missing_rate
          FROM (#{@transactions_scope.to_sql}) at
          #{entries_join_sql("at")}
          #{accounts_join_sql}
          INNER JOIN taggings tgg ON tgg.taggable_id = at.id AND tgg.taggable_type = 'Transaction'
          INNER JOIN tags tg ON tg.id = tgg.tag_id AND tg.id IN (:tag_ids)
          #{exchange_rates_join_sql}
          WHERE #{budget_inclusion_sql("at")}
            #{investment_activity_label_sql("at")}
            AND ae.excluded = false
            AND a.family_id = :family_id
            AND a.status IN ('draft', 'active')
            AND a.exclude_from_reports = false
            #{exclude_tax_advantaged_sql}
            #{include_finance_accounts_sql}
          GROUP BY tg.id, tg.name, #{classification_sql("at")}
          ORDER BY total DESC, tg.name ASC
        SQL
        sql_params
      ])
    end

    def sql_params
      params = base_sql_params(start_date: @date_range.begin, end_date: @date_range.end, tag_ids: @tag_ids)
      params[:included_account_ids] = @included_account_ids if @included_account_ids
      params
    end
end
