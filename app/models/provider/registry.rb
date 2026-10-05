class Provider::Registry
  include ActiveModel::Validations

  Error = Class.new(StandardError)

  CONCEPTS = %i[property_valuations]

  validates :concept, inclusion: { in: CONCEPTS }

  class << self
    def for_concept(concept)
      new(concept.to_sym)
    end

    def get_provider(name)
      send(name)
    rescue NoMethodError
      raise Error.new("Provider '#{name}' not found in registry")
    end


    private
      def github
        Provider::Github.new
      end

      def rentcast
        api_key = ENV["RENTCAST_API_KEY"].presence || Setting.rentcast_api_key # pipelock:ignore

        return nil unless api_key.present?

        Provider::Rentcast.new(api_key)
      end

      def realie
        api_key = ENV["REALIE_API_KEY"].presence || Setting.realie_api_key # pipelock:ignore

        return nil unless api_key.present?

        Provider::Realie.new(api_key)
      end
  end

  def initialize(concept)
    @concept = concept
    validate!
  end

  def providers
    available_providers.map { |p| self.class.send(p) }.compact
  end

  # Returns the list of provider key names (symbols) registered for this concept.
  def provider_keys
    available_providers
  end

  def get_provider(name)
    provider_method = available_providers.find { |p| p == name.to_sym }

    raise Error.new("Provider '#{name}' not found for concept: #{concept}") unless provider_method.present?

    self.class.send(provider_method)
  end

  private
    attr_reader :concept

    def available_providers
      case concept
      when :property_valuations
        %i[rentcast realie]
      else
        %i[github]
      end
    end
end
