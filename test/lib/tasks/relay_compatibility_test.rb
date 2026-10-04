require "test_helper"

class RelayCompatibilityTest < ActiveSupport::TestCase
  test "maintenance no longer exposes connector encryption tasks" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("relay:security:backfill")
    %w[relay:encrypt_access_urls relay:simplefin:encrypt_access_urls sure:encrypt_access_urls].each do |name|
      assert_not Rake::Task.task_defined?(name)
    end
  end
end
