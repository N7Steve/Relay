namespace :financial_domain do
  desc "Read-only aggregate financial inventory on an explicitly isolated database"
  task inventory: :environment do
    abort "Use an isolated database copy and set RELAY_FINANCIAL_INVENTORY_ISOLATED=1" unless ENV["RELAY_FINANCIAL_INVENTORY_ISOLATED"] == "1"
    family = Family.find(ENV.fetch("FAMILY_ID"))
    puts JSON.pretty_generate(Family::FinancialInventory.new(family).call)
  end
end
