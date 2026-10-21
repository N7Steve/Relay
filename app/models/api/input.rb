# frozen_string_literal: true

module Api::Input
  Invalid = Class.new(StandardError)

  def self.date(value, name:)
    raise Invalid, "#{name} must be an ISO 8601 date" unless value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.iso8601(value.to_s)
  rescue Date::Error
    raise Invalid, "#{name} must be an ISO 8601 date"
  end

  def self.decimal(value, name:)
    number = BigDecimal(value.to_s, exception: false)
    raise Invalid, "#{name} must be a finite decimal number" unless number&.finite?

    number
  end
end
