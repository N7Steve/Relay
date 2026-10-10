require "test_helper"

class SharedExpensesCalculatorTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "Checking", balance: 0, currency: "USD", accountable: Depository.new)
    @calculator = SharedExpensesCalculator.new(@family)
    @period = Period.custom(start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 30))
  end

  test "native outflows count half and settlements count in full without tags" do
    expense(101)
    expense(-20)
    expense(80, shared: false)
    assert_equal BigDecimal("30.5"), @calculator.calculate_debt[:pending_debt].amount
    assert @calculator.calculate_debt[:has_data]
    assert_equal BigDecimal("130.5"), @calculator.calculate_adjusted_expenses(@period).amount
  end

  test "settlements cannot produce negative debt and empty history has no data" do
    assert_not @calculator.calculate_debt[:has_data]
    expense(-20)
    assert_equal 0, @calculator.calculate_debt[:pending_debt].amount
    assert @calculator.calculate_debt[:has_data]
  end

  test "old tag has no runtime meaning and removing it does not remove native classification" do
    tag = @family.tags.create!(name: "Gastos compartidos", color: "#123456")
    ordinary = expense(100, shared: false)
    ordinary.transaction.tags << tag
    shared = expense(60)
    shared.transaction.tags << tag
    tag.destroy!
    assert_equal 30, @calculator.calculate_debt[:pending_debt].amount
  end

  test "debt uses all history while adjusted spending uses the selected period" do
    expense(100, date: Date.new(2026, 8, 1))
    expense(60)
    assert_equal 80, @calculator.calculate_debt[:pending_debt].amount
    assert_equal 30, @calculator.calculate_adjusted_expenses(@period).amount
  end

  test "account access family boundaries and analytical exclusions remain in force" do
    expense(100)
    expense(500, excluded: true)
    expense(500).transaction.update!(forecast_behavior: "exceptional_once")
    expense(500).transaction.update!(kind: "funds_movement")
    inaccessible = @family.accounts.create!(name: "Private", balance: 0, currency: "USD", accountable: Depository.new)
    expense(500, account: inaccessible)
    hidden = @family.accounts.create!(name: "Hidden", balance: 0, currency: "USD", status: "disabled", accountable: Depository.new)
    expense(500, account: hidden)
    suppressed = @family.accounts.create!(name: "Suppressed", balance: 0, currency: "USD", exclude_from_reports: true, accountable: Depository.new)
    expense(500, account: suppressed)
    expense(500, account: accounts(:depository))
    calculator = SharedExpensesCalculator.new(@family, accounts: @family.accounts.where(id: [ @account.id, hidden.id, suppressed.id ]))
    assert_equal 50, calculator.calculate_debt[:pending_debt].amount
    assert_equal 50, calculator.calculate_adjusted_expenses(@period).amount
  end

  test "splits inherit classification and excluded parent is not double counted" do
    entry = expense(100)
    children = entry.split!([ { name: "First", amount: 60 }, { name: "Second", amount: 40 } ])
    assert children.all? { |child| child.transaction.shared_expense? }
    assert_equal 50, @calculator.calculate_debt[:pending_debt].amount
  end

  test "foreign amounts use stored rates on their own date and missing rates fail explicitly" do
    @family.update!(currency: "USD")
    date = Date.new(2026, 9, 10)
    ExchangeRate.find_or_initialize_by(from_currency: "EUR", to_currency: "USD", date: date).update!(rate: 2)
    expense(100, currency: "EUR", date: date)
    assert_equal 100, @calculator.calculate_debt[:pending_debt].amount
    assert_equal 100, @calculator.calculate_adjusted_expenses(@period).amount
    ExchangeRate.where(from_currency: "EUR", to_currency: "USD", date: date).delete_all
    assert_raises(Money::ConversionError) { @calculator.calculate_debt }
    assert_raises(Money::ConversionError) { @calculator.calculate_adjusted_expenses(@period) }
  end

  private
    def expense(amount, shared: true, **attributes)
      account = attributes.delete(:account) || @account
      account.entries.create!({ name: "Expense", amount: amount, currency: "USD", date: Date.new(2026, 9, 10),
        entryable: Transaction.new(shared_expense: shared) }.merge(attributes))
    end
end
