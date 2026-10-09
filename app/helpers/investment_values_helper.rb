module InvestmentValuesHelper
  def investment_value_change(entry)
    amount = -entry.amount
    "#{'+' if amount.positive?}#{format_money(Money.new(amount, entry.currency))}"
  end

  def investment_value_color(entry)
    return "text-success" if entry.amount.negative?
    return "text-destructive" if entry.amount.positive?
    "text-secondary"
  end

  def investment_value_icon(entry)
    return "trending-up" if entry.amount.negative?
    return "trending-down" if entry.amount.positive?
    "minus"
  end

  def investment_value_direction(entry)
    return t("investment_values.increase") if entry.amount.negative?
    return t("investment_values.decrease") if entry.amount.positive?
    t("investment_values.unchanged")
  end
end
