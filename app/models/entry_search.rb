class EntrySearch
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :search, :string
  attribute :amount, :string
  attribute :amount_operator, :string
  attribute :types, :string
  attribute :status, array: true
  attribute :uncategorized, :boolean
  attribute :accounts, array: true
  attribute :account_ids, array: true
  attribute :start_date, :string
  attribute :end_date, :string

  class << self
    def apply_search_filter(scope, search)
      return scope if search.blank?

      terms = search.to_s.split.filter_map do |term|
        sanitized = ActiveRecord::Base.sanitize_sql_like(term)
        "%#{sanitized}%" if sanitized.present?
      end

      return scope if terms.blank?

      query = scope
        .joins(<<~SQL.squish)
          LEFT JOIN transactions search_transactions
            ON search_transactions.id = entries.entryable_id
            AND entries.entryable_type = 'Transaction'
        SQL
        .joins("LEFT JOIN merchants search_merchants ON search_merchants.id = search_transactions.merchant_id")

      terms.each do |term|
        query = query.where(
          "entries.name ILIKE :term OR entries.notes ILIKE :term OR search_merchants.name ILIKE :term",
          term: term
        )
      end

      query
    end

    def apply_date_filters(scope, start_date, end_date)
      return scope if start_date.blank? && end_date.blank?

      query = scope
      query = query.where("entries.date >= ?", start_date) if start_date.present?
      query = query.where("entries.date <= ?", end_date) if end_date.present?
      query
    end

    def apply_amount_filter(scope, amount, amount_operator)
      return scope if amount.blank? || amount_operator.blank?

      query = scope

      case amount_operator
      when "equal"
        query = query.where("ABS(ABS(entries.amount) - ?) <= 0.01", amount.to_f.abs)
      when "less"
        query = query.where("ABS(entries.amount) < ?", amount.to_f.abs)
      when "greater"
        query = query.where("ABS(entries.amount) > ?", amount.to_f.abs)
      end

      query
    end

    def apply_accounts_filter(scope, accounts, account_ids)
      return scope if accounts.blank? && account_ids.blank?

      query = scope
      query = query.where(accounts: { name: accounts }) if accounts.present?
      query = query.where(accounts: { id: account_ids }) if account_ids.present?
      query
    end

    # Uncategorized means what it means everywhere else (the Transactions
    # "Uncategorized" filter, the uncategorized badge, Quick Categorize):
    # Entry.uncategorized_transactions, which skips transfers and excluded entries.
    def apply_uncategorized_filter(scope, uncategorized)
      return scope unless uncategorized

      scope.where(id: Entry.uncategorized_transactions.select(:id))
    end
  end

  def build_query(scope)
    query = scope.joins(:account)
    query = self.class.apply_search_filter(query, search)
    query = self.class.apply_date_filters(query, start_date, end_date)
    query = self.class.apply_amount_filter(query, amount, amount_operator)
    query = self.class.apply_accounts_filter(query, accounts, account_ids)
    query = self.class.apply_uncategorized_filter(query, uncategorized)
    query
  end
end
