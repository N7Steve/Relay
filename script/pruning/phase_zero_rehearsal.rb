# Run with Rails runner only in the isolated Docker test database.
require "zip"
require "digest"
require "json"

config = ActiveRecord::Base.connection_db_config
abort "Only the local Docker test database is supported" unless Rails.env.test? &&
  config.database == "relay_test" && config.configuration_hash[:host] == "db" &&
  ENV["REDIS_URL"] == "redis://redis:6379/0"

output = ARGV.fetch(0)
abort "Output must be in tmp" unless File.expand_path(output).start_with?(Rails.root.join("tmp").to_s + "/")
FileUtils.mkdir_p(File.dirname(output))
ActiveJob::Base.queue_adapter = :test
Rails.logger.level = Logger::FATAL

def financial_reference(family)
  {
    accounts: family.accounts.order(:name).map { |a| [ a.name, a.currency, a.balance, a.financial_treatment ] },
    entries: family.entries.order(:name).pluck(:name, :date, :currency, :amount),
    balances: family.accounts.order(:name).map { |a| [ a.name, a.balances.order(:date).pluck(:date, :currency, :balance) ] },
    holdings: family.accounts.order(:name).map { |a| [ a.name, a.holdings.order(:date).pluck(:date, :currency, :qty, :price, :amount) ] },
    agenda: family.scheduled_payments.order(:title).map do |payment|
      [ payment.title, payment.amount, payment.next_run_date, payment.account.name,
        payment.target_account&.name, payment.scheduled_payment_entries.order(:scheduled_date).pluck(:scheduled_date, :status) ]
    end,
    transfers: Transfer.joins(outflow_transaction: :entry).where(entries: { account_id: family.accounts.select(:id) }).count
  }.as_json
end

def export_content(family)
  archive = Family::DataExporter.new(family).generate_export
  content = nil
  Zip::File.open_buffer(archive) { |zip| content = zip.read("all.ndjson") }
  content
end

result = { dataset: "synthetic only", restores: [] }
existing_counts = [ Family.count, Account.count, Entry.count, ActiveStorage::Blob.count ]
ActiveRecord::Base.transaction(requires_new: true) do
  source = Family.create!(name: "Pruning synthetic reference", currency: "EUR", country: "ES", timezone: "Europe/Madrid")
  source.users.create!(email: "pruning-source-#{SecureRandom.hex(8)}@example.com", password: SecureRandom.hex(20), role: "admin")
  checking = source.accounts.create!(name: "Checking", accountable: Depository.new, currency: "EUR", balance: 900)
  savings = source.accounts.create!(name: "Savings", accountable: Depository.new, currency: "EUR", balance: 100, financial_treatment: "tracking")
  investment = source.accounts.create!(name: "Investment", accountable: Investment.new, currency: "EUR", balance: 200)
  date = Date.new(2026, 10, 1)
  [ checking, savings, investment ].each { |a| a.balances.create!(date: date, currency: "EUR", balance: a.balance, flows_factor: 1) }
  security = Security.create!(ticker: "PRUNE#{SecureRandom.hex(4)}", name: "Synthetic security", offline: true)
  investment.holdings.create!(security: security, date: date, currency: "EUR", qty: 2, price: 100, amount: 200)
  outflow = checking.entries.create!(name: "Transfer out", date: date, currency: "EUR", amount: 100, entryable: Transaction.new(kind: "funds_movement"))
  inflow = savings.entries.create!(name: "Transfer in", date: date, currency: "EUR", amount: -100, entryable: Transaction.new(kind: "funds_movement"))
  Transfer.create!(outflow_transaction: outflow.transaction, inflow_transaction: inflow.transaction, status: "confirmed")
  payment = source.scheduled_payments.create!(account: checking, target_account: savings, title: "Monthly saving", amount: 100,
    currency: "EUR", payment_type: "transfer", frequency: "monthly", frequency_day: 1,
    start_date: date, next_run_date: date.next_month, auto_confirm: false)
  payment.scheduled_payment_entries.create!(scheduled_date: date, status: "confirmed", entry: outflow, transfer_entry: inflow)
  payment.scheduled_payment_entries.create!(scheduled_date: date.prev_month, status: "rejected", rejection_reason: "Synthetic example")
  bytes = File.binread(Rails.root.join("test/fixtures/files/imports/sample_bank_statement.pdf"))
  blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: "receipt.pdf", content_type: "application/pdf")
  outflow.transaction.attachments.attach(blob)
  outflow.transaction.save!
  raise "Synthetic original not saved" unless outflow.transaction.reload.attachments.sole.download == bytes
  expected = financial_reference(source)
  result[:financial_reference] = expected
  content = export_content(source)
  result[:source_snapshot_sha256] = Digest::SHA256.hexdigest(content)
  File.write(File.join(File.dirname(output), "pruning-source.ndjson"), content)

  2.times do |iteration|
    ActiveRecord::Base.transaction(requires_new: true) do
      target = Family.create!(name: "Pruning rehearsal destination")
      target.users.create!(email: "pruning-target-#{SecureRandom.hex(8)}@example.com", password: SecureRandom.hex(20), role: "admin")
      restored = Family::DataImporter.new(target, content).import!
      raise "Financial reference mismatch" unless financial_reference(target) == expected
      receipt = target.entries.find_by!(name: "Transfer out").transaction.attachments.sole.download
      raise "Original bytes mismatch" unless receipt == bytes
      verification = restored.fetch(:verification)
      raise "Restore not matched" unless verification["status"] == "matched"
      result[:restores] << verification.slice("status", "verified_records", "verified_attachments", "checked_counts")
      if iteration.zero?
        content = export_content(target)
        File.write(File.join(File.dirname(output), "pruning-reexport.ndjson"), content)
      end
      raise ActiveRecord::Rollback
    end
  end
  raise ActiveRecord::Rollback
end
raise "Database rollback failed" unless existing_counts == [ Family.count, Account.count, Entry.count, ActiveStorage::Blob.count ]
result[:database_rollback] = "matched"
result[:routes_registered_in_test] = Rails.application.routes.routes.size
result[:note] = "Test route set, not live production routes; no worker or external provider invoked"
FileUtils.mkdir_p(File.dirname(output))
File.write(output, JSON.pretty_generate(result) + "\n")
puts "Two synthetic restores, financial reference and original bytes matched; database rolled back"
