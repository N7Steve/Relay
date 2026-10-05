require "test_helper"

class Security::PriceTest < ActiveSupport::TestCase
  setup do
    @security = securities(:aapl)
  end

  test "current price reads today's stored price" do
    @security.prices.where(date: Date.current).delete_all
    price = @security.prices.create!(date: Date.current, price: 314.34, currency: "USD")

    assert_equal Money.new(price.price, "USD"), @security.current_price
  end

  test "current price is unknown without a stored price for today" do
    @security.prices.where(date: Date.current).delete_all

    assert_nil @security.current_price
  end
end
