class ApiRateLimiter
  def self.usage_for(api_key)
    limit(api_key).usage_info
  end

  def self.limit(api_key)
    NoopApiRateLimiter.new(api_key)
  end
end
