module Provider::ExternalRequestGuard
  def perform_request(*args, **kwargs, &block)
    ExternalAccess.require!(:bank_sync)
    super
  end
end
