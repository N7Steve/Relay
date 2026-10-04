# Provider integration guidance

Read [architecture](architecture.md) for provider concepts, runtime registry
selection and `Provided` concerns. For a new securities price provider, follow
[the complete workflow](adding-a-securities-provider.md), including response
types, MIC mapping, currency handling, settings encryption, UI, locales and tests.

## External capability boundaries

Account connector runtime is limited to Enable Banking and FinanceKit. The
[phase 7 record](../migration/pruning-phase-7.md) lists retired connectors and
their historical persistence contract. Market/FX providers, Brandfetch and Drive
remain independent. Do not restore removed connectors through configuration,
generators, upstream merges or reflection.

Financial provider requests require explicit installation-wide activation through
`ExternalAccess`. Check at the transport boundary so direct requests, existing
client instances and previously queued jobs also respect suspension. Faraday
connections use `ExternalAccess::RequestMiddleware` with `:bank_sync`,
`:market_data`, `:property_valuations` or `:ai` as appropriate. HTTParty bank
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

Retired Item/Account classes retain encryption, associations and attachment
declarations. They do not include Syncable, perform imports, register adapters
or contact upstream services on destruction. Serialized connector jobs are
compatibility consumers that cancel without side effects; shared queues are
never purged. `DestroyJob` preserves retired records. Explicit financial reset
remains a separately confirmed operation, with family-scoped historical data.

Do not delete those classes, tables, original attachments, migration translation
data or historical migrations until the later persistence disposition is approved
and its backup compatibility has been validated.
