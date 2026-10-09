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
end
