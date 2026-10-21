# frozen_string_literal: true

require "test_helper"

class Mcp::CoverageAuditTest < ActiveSupport::TestCase
  test "all maintained capabilities tools and exact routes have an implementation or reviewed boundary" do
    result = Mcp::CoverageAudit.check!
    assert_equal 44, result[:cases]
    assert_equal Mcp::Catalog.all.length, result[:tools]
    assert_equal result[:tools], result[:routes]
    assert_operator result[:boundaries], :>, 0
  end
end
