# frozen_string_literal: true

class Mcp::ParityCatalog
  def self.definitions
    c = Mcp::Catalog
    [
      c.definition("get_capabilities", {}, read: true),
      c.definition("get_transaction", { transaction_id: c::ID }, required: [ "transaction_id" ], read: true),
      c.definition("list_transfers", c::PAGE, read: true),
      c.definition("get_transfer", { transfer_id: c::ID }, required: [ "transfer_id" ], read: true),
      c.definition("list_rejected_transfers", c::PAGE, read: true),
      c.definition("list_local_securities", c::PAGE, read: true),
      c.definition("get_local_security", { security_id: c::ID }, required: [ "security_id" ], read: true),
      c.definition("refresh_insights", {})
    ]
  end
end
