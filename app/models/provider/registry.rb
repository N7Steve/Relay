class Provider::Registry
  Error = Class.new(StandardError)

  class << self
    def get_provider(name)
      send(name)
    rescue NoMethodError
      raise Error.new("Provider '#{name}' not found in registry")
    end

    private
      def github
        Provider::Github.new
      end
  end
end
