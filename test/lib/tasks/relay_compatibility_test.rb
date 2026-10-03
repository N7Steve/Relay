require "test_helper"

class RelayCompatibilityTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("relay:encrypt_access_urls")
    %w[relay:encrypt_access_urls sure:encrypt_access_urls relay:simplefin:encrypt_access_urls sure:simplefin:encrypt_access_urls].each do |name|
      Rake::Task[name].reenable
    end
  end

  test "all legacy aliases preserve named arguments" do
    canonical_tasks = Rake::Task.tasks.select { |task| task.name.start_with?("relay:") }
    assert canonical_tasks.any?
    canonical_tasks.each do |canonical|
      legacy = Rake::Task[canonical.name.sub(/\Arelay:/, "sure:")]
      assert_equal canonical.arg_names, legacy.arg_names
      assert_includes legacy.prerequisites, canonical.name
    end
  end

  test "Relay flags override Sure flags and keep dry run safe" do
    result = run_encryption_task({
      "RELAY_BATCH_SIZE" => "7", "SURE_BATCH_SIZE" => "99",
      "RELAY_LIMIT" => "1", "SURE_LIMIT" => "2",
      "RELAY_DRY_RUN" => "true", "SURE_DRY_RUN" => "false"
    }, batch: 7)
    assert_equal 1, result["limit"]
    assert result["dry_run"]
    assert_equal 0, result["updated"]
  end

  test "legacy flags remain supported" do
    result = run_encryption_task({ "SURE_BATCH_SIZE" => "8", "SURE_LIMIT" => "1", "SURE_DRY_RUN" => "true" }, batch: 8)
    assert_equal 1, result["limit"]
    assert result["dry_run"]
  end

  test "blank or invalid Relay flags do not recover destructive legacy flags" do
    [ "", "invalid" ].each do |value|
      Rake::Task["relay:encrypt_access_urls"].reenable
      result = run_encryption_task({
        "RELAY_BATCH_SIZE" => value, "SURE_BATCH_SIZE" => "99",
        "RELAY_LIMIT" => value, "SURE_LIMIT" => "1",
        "RELAY_DRY_RUN" => value, "SURE_DRY_RUN" => "false"
      }, batch: 100)
      assert_nil result["limit"]
      assert result["dry_run"]
    end
  end

  test "existing unprefixed flags retain precedence over Relay flags" do
    result = run_encryption_task({ "BATCH_SIZE" => "4", "RELAY_BATCH_SIZE" => "7" }, batch: 4)
    assert_equal 4, result["batch_size"]
  end

  test "legacy nested alias forwards explicit arguments ahead of environment flags" do
    result = run_encryption_task(
      { "BATCH_SIZE" => "4", "RELAY_BATCH_SIZE" => "7", "RELAY_DRY_RUN" => "true" },
      batch: 3, task_name: "sure:simplefin:encrypt_access_urls", arguments: [ "3", "1", "false" ], writes: true
    )
    assert_equal 1, result["limit"]
    assert_not result["dry_run"]
    assert_equal 1, result["updated"]
  end

  test "invoking Relay and Sure names in one process does not repeat maintenance" do
    run_encryption_task({}, batch: 100, arguments: [ "100", "1", "false" ], writes: true)

    output = capture_io { Rake::Task["sure:encrypt_access_urls"].invoke("100", "1", "false") }.first
    assert_empty output
  end

  private
    def run_encryption_task(overrides, batch:, task_name: "relay:encrypt_access_urls", arguments: [], writes: false)
      names = %w[BATCH_SIZE LIMIT DRY_RUN RELAY_BATCH_SIZE RELAY_LIMIT RELAY_DRY_RUN SURE_BATCH_SIZE SURE_LIMIT SURE_DRY_RUN]
      item = mock("SimpleFin item")
      if writes
        item.stubs(:access_url).returns("https://example.com/test-access")
        item.expects(:update!).with(access_url: "https://example.com/test-access")
      else
        item.expects(:update!).never
      end
      scope = mock("SimpleFin scope")
      scope.expects(:in_batches).with(of: batch).yields([ item ])
      SimplefinItem.stubs(:encryption_ready?).returns(true)
      SimplefinItem.stubs(:order).with(:id).returns(scope)

      output = with_env_overrides(names.index_with { nil }.merge(overrides)) do
        capture_io { Rake::Task[task_name].invoke(*arguments) }.first
      end
      JSON.parse(output)
    end
end
