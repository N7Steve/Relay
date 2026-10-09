class Provider::Factory
  class AdapterNotFoundError < StandardError; end
  class << self
    # Creates an adapter for a given provider account
    # @param provider_account [ApplicationRecord] The provider-specific account
    # @param account [Account] Optional account reference
    # @return [Provider::Base] An adapter instance
    def create_adapter(provider_account, account: nil)
      return nil if provider_account.nil?

      provider_type = provider_account.class.name
      adapter_class = find_adapter_class(provider_type)

      raise AdapterNotFoundError, "No adapter registered for provider type: #{provider_type}" unless adapter_class

      adapter_class.new(provider_account, account: account)
    end

    # Creates an adapter from an AccountProvider record
    # @param account_provider [AccountProvider] The account provider record
    # @return [Provider::Base] An adapter instance
    def from_account_provider(account_provider)
      return nil if account_provider.nil?

      create_adapter(account_provider.provider, account: account_provider.account)
    end

    # Get list of registered provider types
    # @return [Array<String>] List of registered provider type names
    def registered_provider_types
      [ "EnableBankingAccount" ]
    end

    # Check if a provider type has a registered adapter
    # @param provider_type [String] The provider account class name
    # @return [Boolean]
    def registered?(provider_type)
      find_adapter_class(provider_type).present?
    end

    # Get all registered adapter classes
    # @return [Array<Class>] List of registered adapter classes
    def registered_adapters
      [ Provider::EnableBankingAdapter ]
    end

    # Get adapters that support a specific account type
    # @param account_type [String] The account type class name (e.g., "Depository", "CreditCard")
    # @return [Array<Class>] List of adapter classes that support this account type
    def adapters_for_account_type(account_type)
      registered_adapters.select do |adapter_class|
        adapter_class.supported_account_types.include?(account_type)
      end
    end

    # Check if any provider supports a given account type
    # @param account_type [String] The account type class name
    # @return [Boolean]
    def supports_account_type?(account_type)
      adapters_for_account_type(account_type).any?
    end

    # Get all available provider connection configs for a given account type
    # @param account_type [String] The account type class name (e.g., "Depository")
    # @param family [Family] The family to check connection availability for
    # @return [Array<Hash>] Array of connection configurations from all providers
    def connection_configs_for_account_type(account_type:, family:)
      adapters_for_account_type(account_type).flat_map do |adapter_class|
        adapter_class.connection_configs(family: family)
      end
    end

    private
      # Resolve the sole supported connector at call time so Rails reloads do
      # not leave a cached class or depend on an adapter's load order.
      def find_adapter_class(provider_type)
        Provider::EnableBankingAdapter if provider_type == "EnableBankingAccount"
      end
  end
end
