class FamilyResetJob < ApplicationJob
  queue_as :low_priority

  def perform(family)
    Family::FinancialDataReset.new(
      family: family,
      dry_run: false,
      confirmed: true
    ).call

    family.sync_later
  end
end
