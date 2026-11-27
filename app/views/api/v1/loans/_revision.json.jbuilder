# frozen_string_literal: true

# Takes revision:, as_of:.
# One rate revision with every part it was built from. `status` is projected
# (still ahead), pending (due, not recorded yet), calculated or confirmed.

json.effective_on revision.effective_on.iso8601
json.rate revision.rate.to_d.to_s("F")
json.rate_kind revision.rate_kind
json.status loan_rate_revision_status(revision, as_of: as_of).to_s
json.base_rate revision.base_rate&.to_d&.to_s("F")
json.reference_index revision.reference_index
json.reference_index_name revision.reference_index && t("reference_rates.indexes.#{revision.reference_index}", default: revision.reference_index.to_s)
json.index_month revision.index_month&.iso8601
json.index_value revision.index_value&.to_d&.to_s("F")
json.spread revision.spread&.to_d&.to_s("F")
json.bonus_points revision.bonus_points.to_d.to_s("F")
json.composition loan_rate_composition(revision)
