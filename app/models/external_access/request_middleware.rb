class ExternalAccess::RequestMiddleware < Faraday::Middleware
  def initialize(app, capability)
    super(app)
    @capability = capability
  end

  def call(env)
    if @capability == :ai
      raise ExternalAccess::Disabled, "AI features have been retired"
    else
      ExternalAccess.require!(@capability)
    end
    @app.call(env)
  end
end
