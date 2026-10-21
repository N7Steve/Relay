import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Client } from "/tmp/relay-mcp-client/node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js";
import { StreamableHTTPClientTransport } from "/tmp/relay-mcp-client/node_modules/@modelcontextprotocol/sdk/dist/esm/client/streamableHttp.js";

const client = new Client({ name: "Relay approval smoke", version: "1.0.0" });
const transport = new StreamableHTTPClientTransport(new URL(process.env.MCP_URL), {
  requestInit: { headers: { Authorization: `Bearer ${process.env.MCP_BEARER}` } },
});
await client.connect(transport);
const names = [];
let cursor;
do {
  const page = await client.listTools(cursor ? { cursor } : {});
  names.push(...page.tools.map((tool) => tool.name));
  cursor = page.nextCursor;
} while (cursor);
assert(names.includes("get_pending_changes"));
assert(!names.includes("approve_pending_changes"));
async function call(name, args) {
  const response = await client.callTool({ name, arguments: args });
  assert.equal(response.isError, false, JSON.stringify(response));
  return response.structuredContent;
}
await call("get_context", {});
const runKey = randomUUID();
const args = {
  account_id: process.env.MCP_ACCOUNT,
  name: "Official SDK pending approval",
  amount: "14.50",
  date: new Date().toISOString().slice(0, 10),
  idempotency_key: `${runKey}-create`,
};
const [created, replay] = await Promise.all([
  call("create_transaction", args), call("create_transaction", args),
]);
assert.equal(created.status, "pending_approval");
assert.equal(created.change_id, replay.change_id);
const edited = await call("update_transaction", {
  transaction_id: `pending:${created.change_id}:transaction_id`,
  name: "Official SDK approved name", idempotency_key: `${runKey}-edit`,
});
assert.equal(edited.change_set_id, created.change_set_id);
const deleted = await call("delete_transaction", {
  transaction_id: `pending:${created.change_id}:transaction_id`, idempotency_key: `${runKey}-delete`,
});
assert.equal(deleted.change_set_id, created.change_set_id);
const listed = await call("get_pending_changes", {});
assert(listed.data.some((set) => set.id === created.change_set_id && set.status === "pending"));
const search = await call("search_transactions", { search: "Official SDK pending approval" });
assert.equal(search.data.length, 0);
console.log(`CHANGE_SET_ID=${created.change_set_id}`);
console.log(`MCP SDK smoke passed: ${names.length} tools, reads, proposal replay, dependencies; canonical data unchanged`);
await client.close();
