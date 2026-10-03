# STI queries on SureImport must include RelayImport even with lazy loading.
# Rebuild the subclass tree after development reloads as well as at boot.
Rails.application.config.to_prepare do
  RelayImport
end
