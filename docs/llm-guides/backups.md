# Complete family backups

The full export is version 3. `all.ndjson` contains a versioned relational
snapshot and the actual file bytes, so it can be imported independently of the
other ZIP entries. CSVs and the previous NDJSON records remain available for
interchange. Older exports still use the legacy importer; they cannot recover
data or files that their exporter never included.

The relational snapshot inside export version 3 now has snapshot version 2.
It preserves independent import protection, investment tax/tracking attributes,
canonical posting status and account financial treatment. Snapshot version 1 is
still accepted: excluded entries retain their former import protection during
translation, after checksum verification. Version 2 preserves explicit unlocks
even when a movement remains analytically excluded. Legacy NDJSON retains
original exceptional behavior and translates its historical exclusion protection.

The snapshot covers accounts and all accountable details and addresses; account
ownership and sharing; entries, splits, transfers and rejected matches; locked
attributes, provider metadata, reconciliation and import history; balances,
holdings, securities, prices and relevant exchange rates; taxonomy and merchant
customizations; budgets and budget sharing; rules, runs and notification delivery
deduplication; Agenda series, tags and occurrences; goals, account allocations
and pledges; documents and statements; supported family and member preferences
and insights; Enable Banking connections and account payloads; and Google Drive
export configurations. Previously connected accounts retain local financial
observations, authoritative holdings and managed portfolio performance.

Active Storage originals are embedded as Base64 with size and checksum metadata.
This includes account and merchant custom icons, provider logos, profile photos,
transaction receipts, documents, statement originals and uploaded import files.
Thumbnails and other derived variants can be regenerated.

`backup_report.json` lists exclusions and documents whose original bytes were
never retained by the source. Earlier assistant uploads could index a document
without storing its original locally. These cannot be recreated from metadata;
the archive report, import preflight and readback verification identify them
explicitly. New document uploads retain the original locally.

Restoration requires a family administrator and a destination without financial
data. Create the destination administrator first and upload the ZIP directly as
a Relay backup through Imports. Extracted `all.ndjson` is also accepted. Legacy
Sure and new Relay filenames use the same reader. ZIP paths are never extracted
to disk; exactly one root `all.ndjson` is required. Size limits apply to both
uploaded bytes and decompressed NDJSON. A session must contain the complete snapshot
as one chunk. UUIDs are remapped by model, including polymorphic relationships,
rule operands and embedded goal/Agenda references. Seeded, unused taxonomy absent
from the backup is removed; matching taxonomy is reused. Shared market and
provider-merchant records are never overwritten. Conflicting shared records or
missing references cause an explicit failure.

Historical `Import.account_id` references are the sole exception: older source
apps could retain import history after its account was deleted. Such imports
keep their history and source files with a null account link. Preflight and
readback verification report `historical_import_account_unavailable`, including
the original source record and account IDs. Financial references remain strict.

The manifest checks integrity with SHA-256, and each file is checked
against its size and MD5 checksum. The importer verifies restored attributes
before committing. Database changes are transactional and uploaded files from
failed attempts are cleaned up. The import keeps its source mappings to avoid
duplicate records on retry. Automatic post-import sync is suppressed to preserve
the imported snapshot; normal sync can be requested afterwards. Full restoration
cannot be undone through the transaction-import revert action.

This is a family-data migration, not an image of the whole server. Environment
variables, global instance settings, running jobs, sessions, API keys, passkeys,
SSO registrations, user passwords/MFA and pending login/invitation tokens are not
portable family data. The destination keeps its administrator's login and email;
source administrator preferences and ownership map to that administrator. Other
members retain their identities, roles and preferences and need destination
password setup. A source super-admin becomes a family admin rather than acquiring
instance administration. Source member emails already used by another family
are rejected. Generated export archives, operational logs and property-provider usage history
stay with their respective instances. Retained external services can require
reauthorization on the new instance.

Provider credentials are included and re-encrypted with the destination's Rails
encryption configuration. Treat the downloaded archive as sensitive: its portable
payload is not password-encrypted.

Maintain `Family::Backup::MODEL_NAMES`, `PARENTS`, the polymorphic scopes and the
documented exclusions when adding a model. The table-coverage test fails when a
new family-owned table has no disposition. New columns on existing models are
included automatically; generated columns are verified but not written.

Backup model names are stable persisted keys, independent of the implementation
class. Since phase 10, supported snapshots exclude retired connectors, FinanceKit,
recurring Bills, conversations/tool calls, AI usage, commercial subscriptions,
evaluation data and obsolete market metadata. Their exclusive tables and readers
are removed. The snapshot/ZIP versions remain unchanged.

Older Sure/Relay archives are validated in their original form before filtering.
The explicit names-only `Family::Backup::DiscardPolicy` reports discarded records,
attachments and removed attributes as `retired_data_discarded`. Only the supported
product is restored; verification carries `scope: supported_product`. Unknown
models, unknown core fields, corrupt bytes and missing financial references still
fail. Legacy nonrelational Bills rows also report omissions. No Bills-to-Agenda
conversion occurs. Retired credentials, connection payloads, conversations and
their exclusive originals cannot be recovered into the current product.

Before discarding connection rows, the importer preserves reverse balance history,
authoritative holdings, IBKR stored balances and Indexa performance history in
generic account/holding fields. Missing linked managed portfolio data fails
explicitly. Supported originals and relationships remain recoverable. Retired
modules can only be recovered by restoring the previous complete server backup
with its matching older application, separately from current-product recovery.
See [phase 10](../migration/pruning-phase-10.md) for the exact disposition and
irreversible database migration. Earlier integration records below describe their
original scope; this phase supersedes their historical-reader policy.

Run the backup round-trip tests plus the exporter, importer, SureImport,
ImportSession and web/API import controller suites. Tests cover actual bytes,
relationships, histories, settings, import retries and rollback after late errors.

## Relay integration record — 3 October 2026

- Approved scope: implement complete backup export/import from the user's
  original Sure app, including direct ZIP uploads.
- Relay starting HEAD: `f7b0be951ee72fce6e24bb62a6608894e030e2b9`.
- Source: `N7Steve/sure`, parent `2cc641c18794ec28b787d4d78bfb43b39f85720e` through
  `8e768c39661c1999fd0bf6ffe3b26c851c8f72c6`. Only the complete-backup feature
  is adapted; no upstream merge, deployment or database migration is included.
- Adaptations: retain Relay STI writers/readers and session defaults; normalize
  ZIP uploads consistently in web, API, sessions and preflight; bound decompression;
  preserve destination login activation; verify originals and persist restoration
  evidence inside the restore transaction; explicitly warn about orphaned
  historical import account links.
- Real archive rehearsal: the supplied Sure ZIP restored 42,244 relational records
  and 6 originals with matching readback. Two historical import account links
  were unavailable and reported. Re-exporting with Relay and restoring again
  matched the same record and attachment counts. Both rehearsals used temporary
  families in Docker's isolated test database with SQL rollback; no installation
  data or source archive was changed. Private data is not checked into the repo.
- Validation: full Rails suite: 10,853 tests, 46,225 assertions, no failures or
  errors, 33 existing skips. The focused backup/import/controller run passed
  371 tests; the final readback-counter/export-version checks passed 31 tests.
  Browser imports passed 8 tests. RuboCop, ERB lint, Biome lint and Brakeman
  passed; OpenAPI was regenerated (436 documentation examples, no failures).
  API endpoint consistency verification also passed. The optional global
  Biome format check reports 65 pre-existing JavaScript formatting errors;
  this change modifies no JavaScript or formatter configuration.
- Reversal: revert the cohesive code/docs/test change; no new schema is required.
  Code reversal does not undo restored family data. A restoration is deliberately
  not revertible through transaction import controls; use a destination backup
  or a separately authorized reset when reversing an actual migration.

`Transaction.shared_expense` se conserva en snapshots y NDJSON de intercambio,
también en divisiones. Los backups históricos que no contienen el atributo
traducen la etiqueta «Gastos compartidos» al restaurar, sin eliminarla. Los
backups nuevos conservan el valor explícito, incluso `false` con esa etiqueta.
Ver [gastos compartidos](financial-effects.md#gastos-compartidos).
