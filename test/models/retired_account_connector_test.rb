require "test_helper"

class RetiredAccountConnectorTest < ActiveSupport::TestCase
  test "retired connector credentials cannot recreate runtime providers or routes" do
    RetiredAccountConnector::PREFIXES.each do |prefix|
      key = prefix.underscore
      assert_nil "Provider::#{prefix}".safe_constantize
      assert_nil "Provider::#{prefix}Adapter".safe_constantize
      assert_not Provider::Factory.registered?("#{prefix}Account")
      assert_not "#{prefix}Item".safe_constantize&.respond_to?(:table_name)
      assert_nil "#{prefix}Account".safe_constantize
      assert_not Rails.application.routes.routes.any? { |route| route.defaults[:controller] == "#{key}_items" }
    end
    assert_empty Rails.application.routes.routes.select { |route| route.defaults[:controller].to_s.start_with?("webhooks/") }
    assert Provider::Factory.registered?("EnableBankingAccount")
    assert_not Provider::Factory.registered?("FinancekitAccountLineage")
    assert_equal "enable_banking_items", Rails.application.routes.recognize_path("/enable_banking_items/callback", method: :get)[:controller]
  end
end
