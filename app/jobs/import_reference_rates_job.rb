# Imports the published values of loan reference indices (Euribor) when the
# installation allows it, then reviews the loans revised against them.
class ImportReferenceRatesJob < ApplicationJob
  queue_as :scheduled

  def perform
    ReferenceRate::Importer.new.import_all! if ReferenceRate::Importer.enabled?
    ReviewLoanRatesJob.perform_later
  end
end
