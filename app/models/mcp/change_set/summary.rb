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
    transaction_ids = @change_sets.flat_map { |set| set.operations.flat_map { |row| Array(row.dig("arguments", "transaction_id")) + Array(row.dig("arguments", "transaction_ids")) } }
      .reject { |id| id.start_with?("pending:") }
    @transactions = Entry.where(account_id: access.accounts.select(:id), entryable_type: "Transaction", entryable_id: transaction_ids)
      .includes(entryable: :tags).to_h do |entry|
        [ entry.entryable_id, { account_id: entry.account_id, amount: entry.amount, currency: entry.currency,
          snapshot: entry.attributes.slice(*Mcp::Catalog::TRANSACTION.keys.map(&:to_s)).merge(
            entry.transaction.attributes.slice(*Mcp::Catalog::TRANSACTION.keys.map(&:to_s)),
            "tag_ids" => entry.transaction.tag_ids, "account_id" => entry.account_id) } ]
      end
    @labels = {
      "account_id" => @accounts.transform_values { |account| account[:name] },
      "category_id" => actor.family.categories.pluck(:id, :name).to_h,
      "merchant_id" => actor.family.available_merchants_for(actor).pluck(:id, :name).to_h,
      "tag_ids" => actor.family.personal_tags_for(actor).pluck(:id, :name).to_h
    }
  end

  def groups(change_set)
    @groups ||= {}
    @groups[change_set.id] ||= change_set.operations.map { |operation| describe(operation, change_set) }
      .group_by { |row| row.values_at(:type, :action, :accounts, :currency) }
      .map do |_, rows|
        amounts = rows.map { |row| row[:amount] }
        rows.first.slice(:type, :action, :accounts, :currency).merge(
          count: rows.sum { |row| row[:details].size }, names: rows.flat_map { |row| row[:names] }.uniq,
          amount: amounts.all? ? amounts.sum : nil,
          details: rows.flat_map { |row| row[:details] },
          states: rows.flat_map { |row| row[:details] }.group_by { |detail| detail[:state] }.transform_values(&:size)
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
        amount: currency.present? ? amount&.abs : nil, state: state,
        details: details_for(operation, change_set, transaction, state)
      }
    end

    # Explicit display fields avoid exposing upload tokens, passwords or other
    # secrets from the much wider administration/process tool arguments.
    REVIEW_FIELDS = (Mcp::Catalog::TRANSACTION.keys.map(&:to_s) + %w[account_id source_account_id destination_account_id title color icon]).freeze

    def details_for(operation, change_set, transaction, state)
      args = operation.fetch("arguments")
      if operation["name"].in?(%w[bulk_update_transactions bulk_delete_transactions]) && args["transaction_ids"].is_a?(Array)
        return args["transaction_ids"].map do |id|
          row = operation.merge("arguments" => args.fetch("attributes", {}).merge("transaction_id" => id))
          detail(row, change_set, @transactions[id], state)
        end
      end
      [ detail(operation, change_set, transaction, state) ]
    end

    def detail(operation, change_set, transaction, state)
      args = operation.fetch("arguments")
      before = transaction&.fetch(:snapshot)
      organization_field = { "merchant_id" => "merchant_id", "category_id" => "category_id", "tag_id" => "tag_ids" }.find { |key, _| args.key?(key) }
      if !before && organization_field && operation["name"].match?(/\A(update|delete)_(merchant|category|tag)\z/)
        key, label_key = organization_field
        label = @labels[label_key][args[key]]
        before = { "name" => label } if label
      end
      fields = args.slice(*REVIEW_FIELDS)
      fields["currency"] ||= transaction&.fetch(:currency) || args["currency"] || @accounts[args["account_id"]]&.fetch(:currency) if fields.key?("amount")
      if operation["name"].in?(%w[delete_transaction bulk_delete_transactions])
        fields = before || {}
      end
      changes = fields.map do |field, value|
        { field: field, before: before && before.key?(field) ? display_value(field, before[field], change_set) : (operation["name"].start_with?("create_") ? nil : { unavailable: true }),
          after: operation["name"].in?(%w[delete_transaction bulk_delete_transactions]) ? nil : display_value(field, value, change_set) }
      end
      { name: before&.fetch("name", nil) || args["name"] || args["title"],
        operation: operation.fetch("name"), state: state, changes: changes,
        context: (before || args).slice("date", "amount", "currency", "account_id").map { |field, value| display_value(field, value, change_set) },
        error: operation["error_message"] }
    end

    def display_value(field, value, change_set)
      return nil if value.nil?
      return value.map { |item| display_value(field, item, change_set) } if value.is_a?(Array)
      reference = Mcp::ChangeSet::REFERENCE.match(value.to_s)
      if reference
        source = change_set.operations.find { |row| row["id"] == reference[1] }
        return { proposed: source&.dig("arguments", "name") || source&.dig("arguments", "title") }
      end
      label_field = field.in?(%w[source_account_id destination_account_id]) ? "account_id" : field
      return { label: @labels[label_field][value] } if @labels.key?(label_field)
      value
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
