# frozen_string_literal: true

# A review summary, not a domain preview. Resolve labels only through the
# reviewer's current account permissions, never by trusting proposed IDs.
class Mcp::ChangeSet::Summary
  def initialize(change_sets:, actor:)
    @change_sets = change_sets.to_a
    access = Api::Access.new(user: actor, scopes: %w[read])
    @accounts = access.accounts.pluck(:id, :name, :currency).to_h do |id, name, currency|
      [ id, { name: name, currency: currency } ]
    end
    transaction_ids = @change_sets.flat_map { |set| set.operations.filter_map { |row| row.dig("arguments", "transaction_id") } }
      .reject { |id| id.start_with?("pending:") }
    @transactions = Entry.where(account_id: access.accounts.select(:id), entryable_type: "Transaction", entryable_id: transaction_ids)
      .pluck(:entryable_id, :account_id, :amount, :currency).to_h do |id, account_id, amount, currency|
        [ id, { account_id: account_id, amount: amount, currency: currency } ]
      end
  end

  def groups(change_set)
    @groups ||= {}
    @groups[change_set.id] ||= change_set.operations.map { |operation| describe(operation, change_set) }
      .group_by { |row| row.values_at(:type, :action, :accounts, :currency) }
      .map do |_, rows|
        amounts = rows.map { |row| row[:amount] }
        rows.first.slice(:type, :action, :accounts, :currency).merge(
          count: rows.size, names: rows.flat_map { |row| row[:names] }.uniq,
          amount: amounts.all? ? amounts.sum : nil,
          states: rows.group_by { |row| row[:state] }.transform_values(&:size)
        )
      end
  end

  private
    def describe(operation, change_set)
      name = operation.fetch("name")
      args = operation.fetch("arguments")
      transaction = @transactions[args["transaction_id"]]
      account_id = args["account_id"] || transaction&.fetch(:account_id)
      type = type_for(name, args, transaction)
      account_ids = name.include?("transfer") ? [ args["source_account_id"], args["destination_account_id"] ].compact : Array(account_id)
      currency = args["currency"] || @accounts[account_ids.first]&.fetch(:currency) || transaction&.fetch(:currency)
      # Only sum new, explicit amounts. Edits, deletions and dependent amounts
      # must not be presented as a known financial delta.
      amount = decimal(args["amount"]) if name.in?(%w[create_transaction create_transfer])
      state = operation.fetch("status")
      state = "rejected" if change_set.status == "rejected" && state != "applied"
      {
        type: type, action: Mcp::ChangeSet.action_for(name), currency: currency,
        accounts: account_ids.map { |id| account_label(id, change_set) },
        names: type.in?(%w[categories merchants tags rules accounts goals agenda]) ? Array(args["name"] || args["title"]).reject { |value| value.start_with?("pending:") } : [],
        amount: currency.present? ? amount&.abs : nil, state: state
      }
    end

    def type_for(name, args, transaction)
      return "transfers" if name.include?("transfer")
      if name.include?("transaction")
        amount = decimal(args["amount"]) || transaction&.fetch(:amount)
        return "expenses" if amount&.positive?
        return "income" if amount&.negative?
        return "transactions"
      end
      case name
      when /categor/ then "categories"
      when /merchant/ then "merchants"
      when /tag/ then "tags"
      when /rule/ then "rules"
      when /scheduled|occurrence/ then "agenda"
      when /goal|pledge/ then "goals"
      when /trade/ then "trades"
      when /holding/ then "holdings"
      when /valuation/ then "valuations"
      else Mcp::ChangeSet.domain_for(name)
      end
    end

    def account_label(id, change_set)
      return { name: @accounts.fetch(id).fetch(:name), proposed: false } if @accounts.key?(id)

      reference = Mcp::ChangeSet::REFERENCE.match(id.to_s)
      if reference
        source = change_set.operations.find { |row| row["id"] == reference[1] && row["name"] == "create_account" }
        proposed_name = source&.dig("arguments", "name")
        return { name: proposed_name, proposed: true } if proposed_name.present? && !proposed_name.start_with?("pending:")
      end
      { name: nil, proposed: false }
    end

    def decimal(value)
      return unless value.is_a?(String) && value.match?(/\A-?\d+(\.\d+)?\z/)
      BigDecimal(value)
    end
end
