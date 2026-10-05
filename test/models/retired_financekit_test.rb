require "test_helper"
require_relative "../support/historical_financekit_helper"

class RetiredFinancekitTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include HistoricalFinancekitHelper

  setup do
    @item, @lineage = create_historical_financekit_link
  end

  test "publisher runtime is gone while historical models keep their relationships" do
    %w[Financekit Financekit::Processor Financekit::Purge Provider::FinancekitAdapter Demo::FinancekitGenerator
       ProviderDisconnectable Api::V1::Financekit::BatchesController].each do |name|
      assert_nil name.safe_constantize, "#{name} should be retired"
    end
    assert_not FinancekitItem.included_modules.include?(Syncable)
    assert_nil Provider::Factory.create_adapter(@lineage)
    assert_equal [ accounts(:depository) ], @item.accounts.to_a
    assert_equal @lineage, accounts(:depository).account_providers.sole.provider
  end

  test "old serialized FinanceKit jobs finish without changing data or enqueueing work" do
    @item.update!(purge_requested_at: 1.hour.ago)
    before = [ @item.reload.attributes, @lineage.reload.attributes, AccountProvider.count, Entry.count ]

    assert_no_enqueued_jobs do
      [ FinancekitInboxJob.new, FinancekitInboxJob.new(@item.id), FinancekitPurgeJob.new(@item) ].each do |job|
        ActiveJob::Base.execute(job.serialize)
      end
    end

    assert_equal before, [ @item.reload.attributes, @lineage.reload.attributes, AccountProvider.count, Entry.count ]
  end

  test "an old FinanceKit sync is finalized as retired" do
    parent = Sync.create!(syncable: @item.family, status: "syncing")
    sync = Sync.create!(syncable: @item, parent: parent)

    SyncJob.perform_now(sync)

    assert sync.reload.stale?
    assert_equal "Account connector retired", sync.error
    assert_equal "active", @item.reload.status
  end

  test "serialized destruction keeps the historical connection" do
    assert_no_difference [ "FinancekitItem.count", "FinancekitAccountLineage.count", "AccountProvider.count" ] do
      DestroyJob.perform_now(@item)
      DestroyJob.perform_now(@lineage)
    end
  end

  test "family destruction removes historical FinanceKit rows with the family" do
    family = Family.create!(name: "Historical FinanceKit family")
    user = family.users.create!(first_name: "Wallet", last_name: "Owner", email: "historical-wallet@example.com",
      password: "password123", role: :admin, onboarded_at: Time.current)
    account = family.accounts.create!(name: "Historical Wallet", balance: 10, currency: "USD", accountable: Depository.new)
    create_historical_financekit_link(family: family, user: user, account: account)

    assert_difference [ "FinancekitItem.count", "FinancekitAccountLineage.count", "FinancekitAccount.count" ], -1 do
      family.destroy!
    end
  end
end
