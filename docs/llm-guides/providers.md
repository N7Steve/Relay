# Provider integration guidance

Read [architecture](architecture.md) for provider concepts and runtime registry
selection. Security prices and exchange rates have no providers since
[phase 9A](../migration/pruning-phase-9.md): they come from stored rows, trades,
holdings and backups only.

## External capability boundaries

Account connector runtime is limited to Enable Banking. The
[phase 7 record](../migration/pruning-phase-7.md) lists retired connectors and
their historical persistence contract; FinanceKit followed in
[phase 9F](../migration/pruning-phase-9.md). Brandfetch and Drive remain
independent; property valuations were removed in phase 12. Do not restore removed connectors through configuration,
generators, upstream merges or reflection.

Financial provider requests require explicit installation-wide activation through
`ExternalAccess`. Check at the transport boundary so direct requests, existing
client instances and previously queued jobs also respect suspension. Faraday
connections use `ExternalAccess::RequestMiddleware` with `:bank_sync`
or `:google_drive` as appropriate. HTTParty bank
clients prepend `Provider::ExternalRequestGuard` to their singleton class.
Other transports must check `ExternalAccess.require!` before opening a connection.

Keep account materialization and matching local. Do not reinstate provider calls
in `Account::Syncer` or convert linked accounts to manual when disabling access.
Keep cached financial data and explicit missing-data failures. The configuration
and deployment transition is documented in [phase 2](../migration/pruning-phase-2.md).

## Provider logos

A provider's logo comes from [`ProviderLogo`](../../app/components/provider_logo.rb): the
Brandfetch icon for the `domain` in its
[`Provider::Metadata::REGISTRY`](../../app/models/provider/metadata.rb) entry, falling back
to `logo_icon`, then `logo_text` initials on `logo_color`. Anything identifying a provider
renders `render ProviderLogo.new(provider_key: :<x>)` — the `_<x>_item` card on Accounts,
the Bank Sync cards and connection rows, and the connection rows in
`settings/providers/_<x>_panel` — rather than a hand-built badge or the first letter of a
connection name. A panel's setup form and instructions carry no logo.

Give each new provider a registry entry with a brand domain. A provider with no single
brand behind it may omit the domain and set `logo_icon` instead.
Institution logos are a separate concept and belong on accounts through
`Account#logo_url`, never on a provider.

## Support diagnostics

When a provider sync/import path encounters a recoverable error, suspicious partial
response or other support-relevant incident, prefer
[`DebugLogEntry.capture`](../../app/models/debug_log_entry.rb) over `Rails.logger.*`
so operators can inspect it in the super-admin `/settings/debug` UI.

- Include `category`, `level`, `message`, `source`, `provider_key` and useful
  structured `metadata`.
- Attach `family` and `account_provider` whenever available so support can filter
  and trace the affected connection. Account/user associations can add context.
- Reserve raw Rails logging for low-value local noise; incidents operators need
  to investigate belong in the debug log.

## Pending transactions and FX metadata

Enable Banking's importer reads `Setting.syncs_include_pending` (default true).
It fetches BOOK and, when enabled, PDNG transactions, handles unsupported PDNG
as a partial response, and reconciles pending-to-booked records without losing
protected user edits. Keep its namespaced metadata and settlement tests.
Retired connector environment flags no longer influence this preference.

Canonical `posting_status` is normalized on validated writes without removing
source metadata. NULL rows use every retained historical pending namespace;
scopes, searches and settlement lookups agree. `Entry.import_protected` governs
independent import protection; analytical `excluded` is no longer its source for
new records. Historical NULL protection retains the previous promise until an
explicit unlock. Split structure, field locks and importer priorities remain.

`Transaction#extra`, pending scopes, FX metadata, transaction-name rule matching
and import reconciliation still read historical namespaces. Preserve those local
readers: removing a transport does not authorize changing existing amounts,
currencies, pending flags, locked fields or names. Cached IBKR historical balance
calculations and Indexa performance history remain local financial readers.

## Historical transaction naming

Historical Plaid rows may combine merchant and original bank description with
`" - "`. For `=` and `!=`, `Rule::ConditionFilter::TransactionName` rebuilds that
exact value from stored `extra["plaid"]["original_description"]`. Keep exact
comparison, user-modified/split protections, SQL escaping and family boundaries.
Do not replace it with prefix matching. The retired processor is unnecessary
for reading this persisted convention.

## Historical persistence and queued work

Phase 10 removed retired Item/Account classes and exclusive tables after their
persistence disposition was approved. Historical backup compatibility now lives
in `Family::Backup::DiscardPolicy` and its restoration translations, preserving
supported financial observations, holdings and performance history before
discarding retired records. Do not remove those translations or historical
transaction metadata readers when simplifying the runtime factory.

`Provider::Factory` resolves only Enable Banking explicitly; new files cannot
register additional providers. Serialized retired connector jobs remain
compatibility consumers that finish without connector effects; shared queues
are never purged. See the phase 10 record and the complete backup guide for the
current persistence contract.
