import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { Client } from "/tmp/relay-mcp-client/node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js";
import { StreamableHTTPClientTransport } from "/tmp/relay-mcp-client/node_modules/@modelcontextprotocol/sdk/dist/esm/client/streamableHttp.js";

const client = new Client({ name: "Relay smoke", version: "1.0.0" });
const runKey = randomUUID();
const transport = new StreamableHTTPClientTransport(new URL(process.env.MCP_URL), {
  requestInit: { headers: { Authorization: `Bearer ${process.env.MCP_BEARER}` } },
});
await client.connect(transport);
let cursor;
const names = [];
do {
  const page = await client.listTools(cursor ? { cursor } : {});
  names.push(...page.tools.map((tool) => tool.name));
  cursor = page.nextCursor;
} while (cursor);
assert(names.includes("create_transaction"));
assert(names.includes("list_tags"));
const context = await client.callTool({ name: "get_context", arguments: {} });
assert.equal(context.isError, false);
const arguments_ = {
  account_id: process.env.MCP_ACCOUNT,
  name: "Official SDK smoke",
  amount: "14.50",
  date: new Date().toISOString().slice(0, 10),
  idempotency_key: `${runKey}-create`,
};
const [created, replay] = await Promise.all([
  client.callTool({ name: "create_transaction", arguments: arguments_ }),
  client.callTool({ name: "create_transaction", arguments: arguments_ }),
]);
assert.equal(created.isError, false, JSON.stringify(created));
assert.equal(replay.isError, false, JSON.stringify(replay));
assert.equal(replay.structuredContent.transaction_id, created.structuredContent.transaction_id);
const split = await client.callTool({ name: "split_transaction", arguments: {
  transaction_id: created.structuredContent.transaction_id,
  splits: [{ name: "First", amount: "4.50" }, { name: "Second", amount: "10.00" }],
  idempotency_key: `${runKey}-split`,
} });
assert.equal(split.isError, false, JSON.stringify(split));
assert.equal(split.structuredContent.children.length, 2);
const removed = await client.callTool({ name: "delete_transaction", arguments: {
  transaction_id: created.structuredContent.transaction_id,
  idempotency_key: `${runKey}-delete`,
} });
assert.equal(removed.isError, false, JSON.stringify(removed));
const call = async (name, arguments_) => {
  const result = await client.callTool({ name, arguments: arguments_ });
  assert.equal(result.isError, false, JSON.stringify(result));
  return result.structuredContent;
};
const today = new Date().toISOString().slice(0, 10);
const period = { start_date: `${today.slice(0, 7)}-01`, end_date: today };
await call("get_activity_report", period);
await call("get_category_report", period);
await call("get_shared_expenses", period);
await call("get_report_accounts", {});
await call("get_net_worth", {});
await call("get_account_forecast", { account_id: process.env.MCP_ACCOUNT, horizon_months: 1 });
await call("list_budgets", {});
const budget = await call("create_budget", { month: today, idempotency_key: `${runKey}-budget` });
await call("get_budget", { budget_id: budget.id });
await call("list_budget_allocations", { budget_id: budget.id });
const schedule = await call("create_scheduled_payment", {
  title: "SDK planned expense", amount: "9.25", currency: "USD", frequency: "monthly",
  start_date: today, payment_type: "expense", account_id: process.env.MCP_ACCOUNT,
  auto_confirm: false, idempotency_key: `${runKey}-schedule`,
});
const occurrence = await call("confirm_scheduled_date", {
  scheduled_payment_id: schedule.id, scheduled_date: today, idempotency_key: `${runKey}-confirm`,
});
await call("retract_scheduled_entry", {
  scheduled_payment_id: schedule.id, occurrence_id: occurrence.id, idempotency_key: `${runKey}-retract`,
});
await call("list_scheduled_payments", {});
await call("delete_scheduled_payment", { scheduled_payment_id: schedule.id, idempotency_key: `${runKey}-delete-schedule` });
const goal = await call("create_goal", {
  name: "SDK goal", target_amount: "100", accounts: [{ account_id: process.env.MCP_ACCOUNT, allocated_amount: "100" }],
  idempotency_key: `${runKey}-goal`,
});
await call("list_goals", {});
await call("list_goal_pledges", { goal_id: goal.id });
await call("delete_goal", { goal_id: goal.id, idempotency_key: `${runKey}-delete-goal` });
const trade = await call("create_trade", {
  account_id: process.env.MCP_INVESTMENT, type: "buy", date: today,
  ticker: "AAPL", qty: "1", price: "100", fee: "2", idempotency_key: `${runKey}-trade`,
});
assert.equal(trade.amount, "102.0");
await call("get_trade", { trade_id: trade.entryable_id });
await call("list_holdings", { account_id: process.env.MCP_INVESTMENT });
await call("delete_trade", { trade_id: trade.entryable_id, idempotency_key: `${runKey}-delete-trade` });
await call("get_upload_channel", {});
const csv = `date,name,amount,currency\n${today},SDK imported,12,USD\n`;
const form = new FormData();
form.append("file", new Blob([csv], { type: "text/csv" }), "statement.csv");
form.append("sha256", createHash("sha256").update(csv).digest("hex"));
form.append("idempotency_key", `${runKey}-upload`);
const fileRoot = process.env.MCP_URL.replace(/\/mcp$/, "/mcp/files");
const uploaded = await fetch(fileRoot, { method: "POST", headers: { Authorization: `Bearer ${process.env.MCP_BEARER}` }, body: form });
assert.equal(uploaded.status, 201, await uploaded.clone().text());
const staged = await uploaded.json();
const statement = await call("upload_statement", { upload_token: staged.upload_token, account_id: process.env.MCP_ACCOUNT, idempotency_key: `${runKey}-statement` });
const fileInfo = await call("get_file_transfer", { kind: "statement", id: statement.id });
const downloaded = await fetch(new URL(fileInfo.mcp_path, process.env.MCP_URL), { headers: { Authorization: `Bearer ${process.env.MCP_BEARER}` } });
assert.equal(downloaded.status, 200);
assert.equal(await downloaded.text(), csv);
const imported = await call("start_import", {
  type: "TransactionImport", upload_token: staged.upload_token, account_id: process.env.MCP_ACCOUNT,
  date_col_label: "date", name_col_label: "name", amount_col_label: "amount", currency_col_label: "currency", date_format: "%Y-%m-%d", idempotency_key: `${runKey}-import`,
});
await call("preview_import", { import_id: imported.id });
await call("delete_import", { import_id: imported.id, idempotency_key: `${runKey}-delete-import` });
await call("delete_statement", { statement_id: statement.id, idempotency_key: `${runKey}-delete-statement` });
const rule = await call("create_rule", {
  name: "SDK rule", conditions: [{ condition_type: "transaction_name", operator: "like", value: runKey }],
  actions: [{ action_type: "set_transaction_name", value: "SDK name" }], idempotency_key: `${runKey}-rule`,
});
const rulePreview = await call("preview_rule_run", { rule_id: rule.id });
await call("apply_rule", { rule_id: rule.id, preview_token: rulePreview.preview_token, idempotency_key: `${runKey}-apply-rule` });
await call("list_rule_runs", { rule_id: rule.id });
await call("delete_rule", { rule_id: rule.id, idempotency_key: `${runKey}-delete-rule` });
const capabilities = await call("get_capabilities", {});
assert.equal(capabilities.permissions_rechecked_on_every_call, true);
assert.equal(capabilities.tools.length, names.length);
await call("get_profile", {});
await call("update_profile", { first_name: "SDK actor", idempotency_key: `${runKey}-profile` });
await call("get_preferences", {});
await call("list_members", {});
await call("list_sessions", {});
await call("list_api_keys", {});
await call("list_oauth_grants", {});
await call("get_security_status", {});
const human = await call("get_human_flow", { flow: "mfa" });
assert.equal(human.human_required, true);
await call("get_drive_connection", {});
await call("list_drive_schedules", {});
await call("list_bank_connections", {});
await call("get_external_access", {});
await call("list_syncs", { account_id: process.env.MCP_ACCOUNT });
await call("list_local_securities", {});
await call("list_transfers", {});
await call("get_cash_flow", { month: `${today.slice(0, 7)}-01`, include_sankey: true });
await client.close();
console.log(`MCP SDK smoke passed (${names.length} tools)`);
