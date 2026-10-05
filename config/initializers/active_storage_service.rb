# Relay stores Active Storage files on local disk only. Remote services were
# removed in pruning phase 9E; fail at boot instead of serving missing files.
configured_service = ENV["ACTIVE_STORAGE_SERVICE"].presence

if configured_service && !Rails.env.test? && configured_service != "local"
  raise "ACTIVE_STORAGE_SERVICE=#{configured_service} is no longer supported. " \
        "Relay stores uploads on local disk; move existing files before upgrading " \
        "(see docs/migration/pruning-phase-9.md)."
end
