# Reader compatibility for Relay STI records and GlobalIDs. Web/API writers
# still use Import.storage_type until all workers and session constraints are
# ready for the write transition. Keep SureImport for existing records/jobs.
class RelayImport < SureImport
end
