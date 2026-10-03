class ExternalAccess::RequestMiddleware < Faraday::Middleware
  def initialize(app, capability)
    super(app)
    @capability = capability
  end

  def call(env)
    if @capability == :ai
      raise ExternalAccess::Disabled, "AI features are disabled" unless Setting.ai_features_enabled?
    else
      ExternalAccess.require!(@capability)
    end
    @app.call(env)
  end
end
