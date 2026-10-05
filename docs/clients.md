# Relay Clients

Relay is centered on one self-hosted Rails server. Every client connects to that
server and uses the same accounts, users, authentication rules, and financial
data. The supported product scope is summarized in
[Relay product scope](product-scope.md).

## Client overview

| Client | Best for | Status | Entry point |
| --- | --- | --- | --- |
| Web app and PWA | Full everyday use and administration from any modern browser. | Primary client | Open the server URL. For local development see [Local Docker app](llm-guides/docker-local-app.md). |
| macOS desktop app | Relay in a native Mac window with system app chrome and deep-link handling. | Native shell around the web app; built locally | See [Relay Desktop](../desktop/README.md). |
| Flutter mobile app | Basic mobile access on Android and iOS: login, balances and transactions. | Companion app; built locally | See [Relay Mobile](../mobile/README.md). |
| iOS/iPadOS SwiftUI app | Overview of balance sheet, accounts, budgets and insights with an API key. | Companion app; built locally | See [Relay for iOS](../bitrig/README.md). |
| Custom API clients | Scripts, services, importers or dashboards. | HTTP API | See [docs/api/openapi.yaml](api/openapi.yaml) and the endpoint guides in [docs/api](api/). |

There is no public release channel, app store distribution or demo server for
any client. The inherited release workflows are archived under
[docs/archive/sure/workflows](archive/sure/workflows/). The external MCP endpoint
and the AI assistant were retired in pruning phases 5 and 6.

## Web app

The web app is the complete Relay experience: settings, Enable Banking
connections, transactions, Agenda, reports, investments, budgets, goals,
imports and backups. Install it with the [TrueNAS guide](hosting/truenas.md) or
the generic [Docker guide](hosting/docker.md). The desktop app renders this same
web app.

## Native and API clients

Native and custom clients authenticate with a user-generated `X-Api-Key`
header, or with OAuth2 bearer tokens from Relay's Doorkeeper authorization
server for registered app clients. External identifiers inherited from Sure
(`sure://` and `sureapp://` schemes, bundle and package IDs, OAuth application
names) are kept as external contracts so that existing installs keep working.

## Native reporting and device continuity

Read monthly server-calculated totals and the daily spending comparison using
[`GET /api/v1/cash_flow`](api/openapi.yaml). Native clients should
use these values instead of rebuilding Relay's reporting rules from transactions.

Structural node `name` values are fallback labels; clients should localize
`cash_flow`, `surplus`, and `deficit` by `kind` at the presentation boundary.

`include` and `view` are mutually exclusive; combining them returns `422 invalid_view`.

Request `include=sankey` to append category nodes and links to the monthly
summary. For arbitrary date filters, request
`view=sankey&start_date=YYYY-MM-DD&end_date=YYYY-MM-DD` to receive only the graph
and its currency, time zone, as-of date, and inclusive period. This avoids building
a daily series for long date ranges. The default monthly response is unchanged.

Graph values are decimal strings in family currency, with stable node IDs and
zero-based link indices. Refunds are netted within each category; parent direct
amounts exclude children before each direction is grouped. Graph income and
spending can therefore differ from the gross monthly figures, while net savings
agrees. Surplus and deficit nodes balance the central flow. Clients own layout,
formatting, and structural colors; all financial aggregation stays on the server.

The public endpoint uses the standard OAuth/API-key authentication and does not
accept browser sessions. Responses are private and not HTTP-cacheable; native
clients retain their own authenticated, identity-scoped offline cache.

The Turbo dashboard fetches `/dashboard/cash_flow` through a normal web controller,
with session authentication, onboarding checks, and the current user's preview
gate. It honors the impersonated browser identity and finance-account scope. Both
endpoints use `IncomeStatement::CashFlowGraph` and `IncomeStatement::Sankey`, sharing
the graph representation and aggregation without sharing authentication paths.
The web dashboard keeps its original Sankey and renders the server-calculated
chart below it only for users with preview features enabled.

## Push notifications

Push registration and delivery are disabled in self-hosted Relay; see
[iOS push notifications](hosting/push-notifications.md). The
`/api/v1/push_subscriptions` contract and its `device_key` proof remain for the
retained clients: 32 securely random bytes encoded as 64 lowercase hex
characters, stored only in secure device storage and preserved across logout.
The server stores only its SHA-256 digest; knowing an APNs token alone never
authorizes transferring a registration to another user.

## Retired client integrations

FinanceKit was retired in pruning phase 9F: the server no longer exposes
`/api/v1/financekit/*`. Accounts linked before the retirement remain ordinary
accounts; see [phase 9](migration/pruning-phase-9.md).
