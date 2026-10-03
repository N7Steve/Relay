# Share backup behavior while keeping SureImport readable for legacy records
# and queued GlobalIDs. New backup writers use RelayImport.
class RelayImport < SureImport
end
