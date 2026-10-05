# Relay configuration and historical data

Relay serves one installation. Maintenance commands use only `relay:*` and
configuration uses only the `RELAY_*` names below. `sure:*` aliases and `SURE_*`
fallbacks are removed. Remap installation configuration before the final cut.
Historical data readers remain because stored records and backups must be usable.

## Environment variables and maintenance

| Name | Default |
| --- | --- |
| `RELAY_IMPORT_MAX_ROWS` | 100000 records |
| `RELAY_IMPORT_MAX_NDJSON_SIZE_MB` | 500 MB |
| `RELAY_BATCH_SIZE` | 100 items |
| `RELAY_LIMIT` | No limit |
| `RELAY_DRY_RUN` | true |

Nonpositive/nonnumeric import limits use their defaults. Encryption maintenance
retains precedence of nonblank positional arguments, then unprefixed
`BATCH_SIZE`/`LIMIT`/`DRY_RUN`, then `RELAY_*`, then defaults. Unrecognized dry-run
values stay true; `0`, `false`, `no` and `n` explicitly disable dry run.
`Relay::Environment.legacy_names_in_use` reports obsolete variable names that
lack a Relay equivalent; it does not enable them or print their values.

Examples: `relay:encrypt_access_urls[batch_size,limit,dry_run]`,
`relay:simplefin:encrypt_access_urls[batch_size,limit,dry_run]`,
`relay:simplefin:prune_pending[item_id,account_id,dry_run]`.
A naming change does not authorize running a maintenance operation.

The manual `data_migration:eu_plaid_webhooks` task requires the installation's
explicit `PLAID_EU_WEBHOOK_URL` (HTTPS, no embedded credentials or fragment).
It never chooses Sure's hosted domain. Do not run it until the actual callback
has been selected and reviewed.

## Exports and restore

New full backup files use `relay_export_YYYYMMDD_HHMMSS.zip`. An already attached
export keeps its stored filename, including `sure_export_*`, and remains
downloadable. CSV export naming and Google Drive's configured filenames and
remote file IDs are unchanged.

New full exports use version 3, with a versioned relational snapshot and original
attachment bytes in `all.ndjson`. Both Sure and Relay ZIPs can now be uploaded
directly, or through their extracted `all.ndjson`. Version 2 exports remain
readable through the legacy importer. See [complete backups](backups.md) for
restoration requirements, preserved data and exclusions.

## Backup import names: Relay writers

Web and API requests accept both `RelayImport` and `SureImport`. Both use the
same NDJSON validation, limits, upload, preflight and publication workflow.
The web upload form now submits `RelayImport`; old links still work. Routes,
`X-Api-Key`/OAuth authentication and family permissions remain unchanged.

Relay targets a single installation. New backup writers use Relay directly;
there is no response negotiation or support for running older application
versions alongside this writer release. Readers retain existing stored data.

| Surface | Current behavior |
| --- | --- |
| Web/API import creation | Both input names write `RelayImport` |
| API preflight | Both names return `data.type: RelayImport`; no data/jobs are created |
| API import type filter | Either name selects both stored backup types, within the current family |
| API import details/list | `type` reflects the stored type; readers support both names |
| New session creation | Both input names and an omitted type write `RelayImport`; database default is `RelayImport` |
| Session retry | Preserves the original stored type, chunks and idempotency key, even with the other input name |
| New chunks | Use the stored session type; existing chunks keep their type |
| Jobs queued by web/API | New backups use `RelayImport` GlobalIDs; session jobs keep `ImportSession` |

`RelayImport < SureImport` adds a real STI reader without duplicating the backup
implementation. It reads records with type `RelayImport`; the legacy parent
also reads both types. `backup_import_sti.rb` loads the subclass in `to_prepare`
so legacy queries/GlobalIDs can find Relay records even with lazy loading and
after development reloads. Existing `SureImport::Preflight`, exception classes
and localized keys stay available. Attachments still use polymorphic record
type `Import`; no files are moved or reattached. Session source mappings and
the `sure_import_session:<id>` source key stay intact.

The tests exercise both stored STI names, their GlobalIDs, serialized
import/revert jobs, attachments, preflight, verification and session workers.
No data backfill is included. Existing `SureImport` records and sessions are
not converted: preserving a session's type on retry prevents changes to its
already uploaded chunks. A row lock protects expected-chunk reconciliation in
both normal retries and duplicate-insert races. Conflicting counts still fail.

### Session schema expansion

`20261003120000_allow_relay_import_sessions.rb` expands the session check constraint
to `SureImport` and `RelayImport`. It does not change the default or update rows,
chunks, mappings, attachments or jobs. Rails runs the replacement
in its normal migration transaction; the validated constraint rejects other
types and the existing NOT NULL constraint remains in force.

The reverse migration takes an exclusive table lock before checking for nonlegacy
sessions. It refuses with `ActiveRecord::IrreversibleMigration` if any exist,
preserving their data and the expanded constraint. Without such rows, it restores
the validated `SureImport` constraint, keeping the same default. It never converts
or deletes sessions to make rollback succeed. Both directions take an exclusive
table lock and validate existing rows: account for blocking when scheduling this
migration on a large installation.

`20261003130000_use_relay_import_session_default.rb` then changes the session
default from `SureImport` to `RelayImport`. It is independently reversible and
does not convert existing sessions. Reversing the default leaves the expanded
constraint in place so existing Relay rows remain valid.

Upgrade and reversal are exercised inside test transactions in an isolated
PostgreSQL database. Adding these migrations to the repository does not apply
them to an installation.

### Applying this release to the single installation

1. Back up and rehearse against an isolated copy of the installation.
2. Schedule the update of web and workers together. Apply the two included
   migrations in timestamp order before running the new writers. Do not keep
   older web/worker versions running alongside this release.
3. Verify upload, session retries, publication, readback and revert. The API
   returns stored types directly; any client in use must accept `RelayImport`.
   No compatibility header or alternate response representation is provided.
4. Keep old stored types readable. Renaming existing data is unnecessary and
   would require a separate plan for records, jobs and rollback.

The release/channel and deployment decisions are collected in [the final form](../migration/final-decisions.md).
Nothing here starts a server or migrates an existing database.

## Reverting this naming change

Phase 10 adds a separate irreversible schema cleanup. Its old-backup reader
recovers the supported product and reports omitted retired modules; it preserves
the `RelayImport`/`SureImport` contracts above. The API no longer emits retired
security acquisition metadata or Bills/Plaid reset counters. Reverting the naming
change alone cannot recover tables discarded by phase 10. See
[phase 10](../migration/pruning-phase-10.md) before any installation update or
database recovery.

Reverting code restores the old task/configuration names. Existing attachments
and Relay backup payloads remain readable. Before reverting, switch configured
`RELAY_*` names back to `SURE_*` , and use the legacy
task names: the older application does not know the new names. No data migration
is required.

Reverting this writer release requires code that can still read `RelayImport`
records and queued GlobalIDs. Reversing the default does not rewrite data or
change this requirement. Do not narrow the session constraint while Relay
sessions exist; its reverse migration refuses to do so. Reverting files in Git
does not revert an installation's database.
