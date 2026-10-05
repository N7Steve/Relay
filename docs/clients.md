# Relay Clients

Relay is centered on one self-hosted Rails server. Every client connects to that
server and uses the same accounts, users, authentication rules, and financial
data. The supported product scope is summarized in
[Relay product scope](product-scope.md).

## Client overview

| Client | Best for | Status | Entry point |
| --- | --- | --- | --- |
| Web app and PWA | Full everyday use and administration from any modern browser. | Primary client | Open the server URL. For local development see [Local Docker app](llm-guides/docker-local-app.md). |
| Flutter Android app | Mobile access: login, balances and transactions. | Companion app; APK built locally or by Mobile CI | See [Relay Mobile](../mobile/README.md). |
| Custom API clients | Scripts, services, importers, dashboards or a future dedicated front end. | HTTP API | See [docs/api/openapi.yaml](api/openapi.yaml) and the endpoint guides in [docs/api](api/). |

There is no public release channel, app store distribution or demo server. The
macOS desktop app, the SwiftUI iOS/iPadOS app, the Flutter iOS and web targets
and push notifications were removed in pruning phase 12; the external MCP
endpoint and the AI assistant in phases 5 and 6. Their code remains in Git
history.

## Web app

The web app is the complete Relay experience: settings, Enable Banking
connections, transactions, Agenda, reports, investments, budgets, goals,
imports and backups. Install it with the [TrueNAS guide](hosting/truenas.md) or
the generic [Docker guide](hosting/docker.md).

## Native and API clients

Native and custom clients authenticate with a user-generated `X-Api-Key`
header, or with OAuth2 bearer tokens from Relay's Doorkeeper authorization
server for registered app clients. The Android app's mobile SSO uses the
`sureapp://oauth/callback` scheme inherited from Sure; it is kept as an external
contract so existing installs keep working.

A new client (for example a Windows app or a separate web front end) should use
the API v1 endpoints with an API key or an OAuth application, and read
server-calculated figures instead of re-implementing financial rules.

## Native reporting and device continuity

Read monthly server-calculated totals and the daily spending comparison using
[`GET /api/v1/cash_flow`](api/openapi.yaml). Clients should
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
