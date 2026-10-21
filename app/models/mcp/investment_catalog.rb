# frozen_string_literal: true

class Mcp::InvestmentCatalog
  def self.definitions
    c = Mcp::Catalog
    trade = { trade_id: c::ID }
    holding = { holding_id: c::ID }
    valuation = { valuation_id: c::ID }
    attrs = { name: c::STRING, notes: c::STRING, date: c::DATE, currency: c::STRING,
      qty: c::MONEY, price: c::MONEY, fee: c::MONEY, amount: c::MONEY,
      type: { type: "string", enum: Trade::CreateForm::SUPPORTED_TYPES }, ticker: c::STRING,
      transfer_account_id: c::ID, category_id: c::ID, excluded: c::BOOLEAN, import_protected: c::BOOLEAN }
    [
      c.definition("list_trades", c::PAGE.merge(account_id: c::ID), read: true),
      c.definition("get_trade", trade, required: [ "trade_id" ], read: true),
      c.definition("create_trade", attrs.merge(account_id: c::ID), required: %w[account_id type date]),
      c.definition("update_trade", trade.merge(attrs.except(:ticker, :transfer_account_id)), required: [ "trade_id" ]),
      c.definition("delete_trade", trade, required: [ "trade_id" ], destructive: true),
      c.definition("unlock_trade", trade, required: [ "trade_id" ]),
      c.definition("list_holdings", c::PAGE.merge(account_id: c::ID), required: [ "account_id" ], read: true),
      c.definition("get_holding", holding, required: [ "holding_id" ], read: true),
      c.definition("update_holding_cost_basis", holding.merge(total_cost_basis: c::MONEY), required: %w[holding_id total_cost_basis]),
      c.definition("unlock_holding_cost_basis", holding, required: [ "holding_id" ]),
      c.definition("remap_holding_security", holding.merge(ticker: c::STRING), required: %w[holding_id ticker]),
      c.definition("reset_holding_security", holding, required: [ "holding_id" ]),
      c.definition("preview_holding_deletion", holding, required: [ "holding_id" ], read: true),
      c.definition("delete_holding", holding.merge(preview_token: { type: "string", maxLength: 16000 }), required: %w[holding_id preview_token], destructive: true),
      c.definition("list_valuations", c::PAGE.merge(account_id: c::ID), required: [ "account_id" ], read: true),
      c.definition("preview_reconciliation", { account_id: c::ID, amount: c::MONEY, date: c::DATE }, required: %w[account_id amount date], read: true),
      c.definition("reconcile_account", { account_id: c::ID, amount: c::MONEY, date: c::DATE }, required: %w[account_id amount date]),
      c.definition("update_valuation", valuation.merge(amount: c::MONEY, date: c::DATE, notes: c::STRING), required: %w[valuation_id amount date]),
      c.definition("delete_valuation", valuation, required: [ "valuation_id" ], destructive: true),
      c.definition("update_managed_portfolio_value", { account_id: c::ID, amount: c::MONEY, date: c::DATE, entry_id: c::ID }, required: %w[account_id amount date]),
      c.definition("list_local_prices", c::PAGE.merge(security_id: c::ID), required: [ "security_id" ], read: true),
      c.definition("set_local_price", { security_id: c::ID, date: c::DATE, price: c::MONEY, currency: c::STRING }, required: %w[security_id date price currency]),
      c.definition("list_exchange_rates", c::PAGE.merge(from_currency: c::STRING, to_currency: c::STRING), required: %w[from_currency to_currency], read: true),
      c.definition("set_exchange_rate", { from_currency: c::STRING, to_currency: c::STRING, date: c::DATE, rate: c::MONEY }, required: %w[from_currency to_currency date rate])
    ]
  end
end
