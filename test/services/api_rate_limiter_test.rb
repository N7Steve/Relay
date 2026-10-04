require "test_helper"

class ApiRateLimiterTest < ActiveSupport::TestCase
  test "self-hosted factory does not connect to Redis or impose a commercial quota" do
    Redis.expects(:new).never
    limiter = ApiRateLimiter.limit(api_keys(:active_key))

    assert_instance_of NoopApiRateLimiter, limiter
    101.times { limiter.increment_request_count! }
    assert_not limiter.rate_limit_exceeded?
    assert_equal 0, limiter.current_count
    assert_equal Float::INFINITY, limiter.rate_limit
  end

  test "usage remains unlimited even with legacy deployment flags" do
    with_env_overrides("SELF_HOSTED" => "false", "SELF_HOSTING_ENABLED" => "false") do
      info = ApiRateLimiter.usage_for(api_keys(:active_key))

      assert_equal 0, info[:current_count]
      assert_equal Float::INFINITY, info[:rate_limit]
      assert_equal Float::INFINITY, info[:remaining]
      assert_equal :noop, info[:tier]
    end
  end
end
