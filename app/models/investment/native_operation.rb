# Presentation and taxonomy invariants for managed portfolios. Accounting kinds,
# amounts and transfer boundaries remain governed by the existing ledger.
class Investment::NativeOperation
  def self.transfer_type(from, to)
    return unless from && to
    if from.managed_portfolio? && to.managed_portfolio?
      "transfer"
    elsif to.managed_portfolio?
      "contribution"
    elsif from.managed_portfolio?
      "withdrawal"
    end
  end

  def self.transfer_name(from, to)
    type = transfer_type(from, to)
    return unless type
    I18n.t("investment_values.operations.#{type}_name", locale: to.family.locale,
      portfolio: type == "withdrawal" ? from.name : to.name, from: from.name, to: to.name)
  end

  def self.normalize_entry(entry)
    return unless entry&.transaction?
    transaction = entry.transaction
    type = transaction.native_managed_operation
    return unless type

    name = if type == "valuation"
      Investment::ValueUpdate.name_for(entry.date, locale: entry.account.family.locale) if entry.date
    elsif (transfer = transaction.paired_transfer)&.managed_operation
      transfer.native_name
    else
      I18n.t("investment_values.operations.#{type}_name", locale: entry.account.family.locale, portfolio: entry.account.name)
    end
    assign(entry, type, name)
  end

  def self.assign(entry, type, name)
    entry.name = name if name
    entry.transaction.category_id = nil
    entry.transaction.extra = entry.transaction.extra.to_h.merge("native_managed_operation" => type)
  end
end
