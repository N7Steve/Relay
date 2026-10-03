class ExternalAccess
  Disabled = Class.new(StandardError)
  CAPABILITIES = %i[bank_sync market_data property_valuations logos google_drive].freeze

  def self.enabled?(capability)
    raise ArgumentError, "Unknown external capability: #{capability}" unless CAPABILITIES.include?(capability)
    return false if capability == :market_data && local_recalculation?

    override = ENV["RELAY_EXTERNAL_#{capability.to_s.upcase}_ENABLED"]
    return %w[true 1].include?(override.downcase) unless override.nil?

    Setting.public_send("external_#{capability}_enabled") == true
  end

  def self.require!(capability)
    raise Disabled, "External capability #{capability} is disabled" unless enabled?(capability)
  end

  def self.local_recalculation?
    ActiveSupport::IsolatedExecutionState[:relay_local_recalculation] == true
  end

  def self.locally
    previous = ActiveSupport::IsolatedExecutionState[:relay_local_recalculation]
    ActiveSupport::IsolatedExecutionState[:relay_local_recalculation] = true
    yield
  ensure
    ActiveSupport::IsolatedExecutionState[:relay_local_recalculation] = previous
  end
end
