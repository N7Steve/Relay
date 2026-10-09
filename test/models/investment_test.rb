require "test_helper"

class InvestmentTest < ActiveSupport::TestCase
  # Tax treatment derivation tests

  test "tax_treatment returns tax_deferred for US retirement accounts" do
    %w[401k 403b 457b tsp ira sep_ira simple_ira].each do |subtype|
      investment = Investment.new(subtype: subtype)
      assert_equal :tax_deferred, investment.tax_treatment, "Expected #{subtype} to be tax_deferred"
    end
  end

  test "tax_treatment returns tax_exempt for Roth accounts" do
    %w[roth_401k roth_ira].each do |subtype|
      investment = Investment.new(subtype: subtype)
      assert_equal :tax_exempt, investment.tax_treatment, "Expected #{subtype} to be tax_exempt"
    end
  end

  test "tax_treatment returns tax_advantaged for special accounts" do
    %w[529_plan hsa].each do |subtype|
      investment = Investment.new(subtype: subtype)
      assert_equal :tax_advantaged, investment.tax_treatment, "Expected #{subtype} to be tax_advantaged"
    end
  end

  test "tax_treatment returns taxable for standard accounts" do
    %w[brokerage cash_management mutual_fund angel trust ugma utma other].each do |subtype|
      investment = Investment.new(subtype: subtype)
      assert_equal :taxable, investment.tax_treatment, "Expected #{subtype} to be taxable"
    end
  end

  test "tax_treatment returns taxable for nil subtype" do
    investment = Investment.new(subtype: nil)
    assert_equal :taxable, investment.tax_treatment
  end

  test "tax_treatment returns taxable for unknown subtype" do
    investment = Investment.new(subtype: "unknown_type")
    assert_equal :taxable, investment.tax_treatment
  end

  # UK account types

  test "tax_treatment returns tax_exempt for UK ISA accounts" do
    %w[isa lisa].each do |subtype|
      investment = Investment.new(subtype: subtype)
      assert_equal :tax_exempt, investment.tax_treatment, "Expected #{subtype} to be tax_exempt"
    end
  end

  test "tax_treatment returns tax_deferred for UK pension accounts" do
    %w[sipp workplace_pension_uk].each do |subtype|
      investment = Investment.new(subtype: subtype)
      assert_equal :tax_deferred, investment.tax_treatment, "Expected #{subtype} to be tax_deferred"
    end
  end

  # Canadian account types

  test "tax_treatment returns tax_deferred for Canadian retirement accounts" do
    %w[rrsp lira rrif].each do |subtype|
      investment = Investment.new(subtype: subtype)
      assert_equal :tax_deferred, investment.tax_treatment, "Expected #{subtype} to be tax_deferred"
    end
  end

  test "tax_treatment returns tax_exempt for Canadian TFSA" do
    investment = Investment.new(subtype: "tfsa")
    assert_equal :tax_exempt, investment.tax_treatment
  end

  test "tax_treatment returns tax_advantaged for Canadian RESP" do
    investment = Investment.new(subtype: "resp")
    assert_equal :tax_advantaged, investment.tax_treatment
  end

  # Australian account types

  test "tax_treatment returns tax_deferred for Australian super accounts" do
    %w[super smsf].each do |subtype|
      investment = Investment.new(subtype: subtype)
      assert_equal :tax_deferred, investment.tax_treatment, "Expected #{subtype} to be tax_deferred"
    end
  end

  # European account types

  test "tax_treatment returns tax_deferred for European pension accounts" do
    %w[pillar_3a riester].each do |subtype|
      investment = Investment.new(subtype: subtype)
      assert_equal :tax_deferred, investment.tax_treatment, "Expected #{subtype} to be tax_deferred"
    end
  end

  test "tax_treatment returns tax_advantaged for French PEA" do
    investment = Investment.new(subtype: "pea")
    assert_equal :tax_advantaged, investment.tax_treatment
  end

  test "tax_treatment returns tax_advantaged for French AV" do
    investment = Investment.new(subtype: "assurance_vie")
    assert_equal :tax_advantaged, investment.tax_treatment
  end
  # Generic account types

  test "tax_treatment returns tax_deferred for generic pension and retirement" do
    %w[pension retirement].each do |subtype|
      investment = Investment.new(subtype: subtype)
      assert_equal :tax_deferred, investment.tax_treatment, "Expected #{subtype} to be tax_deferred"
    end
  end

  # Subtype metadata tests

  test "all subtypes have required metadata keys" do
    Investment::SUBTYPES.each do |key, metadata|
      assert metadata.key?(:short), "Subtype #{key} missing :short key"
      assert metadata.key?(:long), "Subtype #{key} missing :long key"
      assert metadata.key?(:tax_treatment), "Subtype #{key} missing :tax_treatment key"
      assert metadata.key?(:region), "Subtype #{key} missing :region key"
    end
  end

  test "all subtypes have valid tax_treatment values" do
    valid_treatments = %i[taxable tax_deferred tax_exempt tax_advantaged]

    Investment::SUBTYPES.each do |key, metadata|
      assert_includes valid_treatments, metadata[:tax_treatment],
        "Subtype #{key} has invalid tax_treatment: #{metadata[:tax_treatment]}"
    end
  end

  test "all subtypes have valid region values" do
    valid_regions = [ "us", "uk", "ca", "au", "eu", "in", nil ]

    Investment::SUBTYPES.each do |key, metadata|
      assert_includes valid_regions, metadata[:region],
        "Subtype #{key} has invalid region: #{metadata[:region]}"
    end
  end

  # India account types

  test "India pension subtypes have tax_advantaged treatment" do
    %w[nps apy].each do |subtype|
      investment = Investment.new(subtype: subtype)
      assert_equal :tax_advantaged, investment.tax_treatment, "Expected #{subtype} to be tax_advantaged"
    end
  end

  test "India equity subtypes are taxable" do
    %w[indian_stocks indian_equity indian_etf].each do |subtype|
      investment = Investment.new(subtype: subtype)
      assert_equal :taxable, investment.tax_treatment, "Expected #{subtype} to be taxable"
    end
  end

  test "life insurance is tax_advantaged" do
    investment = Investment.new(subtype: "life_insurance")
    assert_equal :tax_advantaged, investment.tax_treatment
  end

  test "India subtypes all belong to the 'in' region" do
    india_keys = Investment::SUBTYPES.keys.select { |k| Investment::SUBTYPES.dig(k, :region) == "in" }
    assert india_keys.any?, "Expected at least one India subtype"
    india_keys.each do |key|
      assert_equal "in", Investment::SUBTYPES.dig(key, :region), "Expected #{key} to have region 'in'"
    end
  end

  test "new accounts offer the short catalogue while editing retains their historical subtype" do
    options = Investment.subtypes_grouped_for_select(currency: "INR").flat_map(&:last).map(&:last)
    assert_equal %w[brokerage roboadvisor pension other], options
    legacy = Investment.subtypes_grouped_for_select(current_subtype: "401k").flat_map(&:last).map(&:last)
    assert_includes legacy, "401k"
    assert_equal 5, legacy.size
  end

  test "tax treatment and tracking can change independently without destroying trades" do
    account = accounts(:investment)
    trade_ids = account.trades.pluck(:id)
    assert trade_ids.any?

    account.accountable.update!(subtype: "roboadvisor", tax_treatment: "tax_exempt", tracking_mode: "positions")

    assert_equal trade_ids.sort, account.reload.trades.pluck(:id).sort
    assert_equal :tax_exempt, account.tax_treatment
    assert_not account.managed_portfolio?
    assert account.supports_trades?
    assert_includes account.family.tax_advantaged_account_ids, account.id
  end
end
