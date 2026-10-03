# Relay configuration and import compatibility

Relay introduces new configuration and command names without requiring existing
installations to migrate immediately. The Sure names remain supported throughout
this transition; there is no removal date yet.

## Environment variables

| Preferred name | Legacy fallback | Default |
| --- | --- | --- |
| `RELAY_IMPORT_MAX_ROWS` | `SURE_IMPORT_MAX_ROWS` | 100000 records |
| `RELAY_IMPORT_MAX_NDJSON_SIZE_MB` | `SURE_IMPORT_MAX_NDJSON_SIZE_MB` | 500 MB |
| `RELAY_BATCH_SIZE` | `SURE_BATCH_SIZE` | 100 items |
| `RELAY_LIMIT` | `SURE_LIMIT` | No limit |
| `RELAY_DRY_RUN` | `SURE_DRY_RUN` | true |

The import limits apply to web uploads, API uploads and workers. The last three
flags apply to `relay:encrypt_access_urls` and its SimpleFin wrapper, as before.
Other provider flags and their defaults are unchanged.

A defined `RELAY_*` variable takes precedence over `SURE_*`, including an empty
or invalid value. Nonpositive/nonnumeric import limits use their defaults. The
maintenance task uses its existing parsing: nonpositive batch sizes use 100,
nonpositive limits mean no limit, and an unrecognized dry-run value stays true.
`0`, `false`, `no` and `n` explicitly disable dry run.

For the encryption task, precedence is: nonblank positional arguments, nonblank
unprefixed `BATCH_SIZE`/`LIMIT`/`DRY_RUN`, then `RELAY_*`, then `SURE_*`, then
defaults. This preserves the existing unprefixed overrides. Check both the new
and unprefixed flags before applying a maintenance operation.

To list legacy variables defined without their Relay equivalent, without
printing values, an operator can run in the intended Rails environment:

```sh
bin/rails runner 'puts Relay::Environment.legacy_names_in_use'
```

This is a read-only diagnostic, not a setup or database migration command. For
maintenance flags, the listed variables are fallback candidates: positional
arguments and unprefixed overrides can still take precedence when a task runs.

## Maintenance tasks

Every former `sure:*` task now has a canonical `relay:*` name with the same
arguments and behavior. `sure:*` remains a Rake compatibility alias forwarding
its named arguments to the canonical task. Both names share Rake's normal
once-per-invocation behavior, so requesting both does not run maintenance twice.
Examples:

- `relay:encrypt_access_urls[batch_size,limit,dry_run]`
- `relay:simplefin:encrypt_access_urls[batch_size,limit,dry_run]`
- `relay:simplefin:prune_pending[item_id,account_id,dry_run]`
- `relay:holdings:seed_prev_snapshot[holding_id,change_pct,days_ago,dry_run]`

The new name does not authorize running a task that changes stored data. Read
the task's arguments and safeguards before using it. No maintenance task is run
on an existing installation as part of the naming migration.

## Exports and restore

New full backup files use `relay_export_YYYYMMDD_HHMMSS.zip`. An already attached
export keeps its stored filename, including `sure_export_*`, and remains
downloadable. CSV export naming and Google Drive's configured filenames and
remote file IDs are unchanged.

ZIP structure, export version 2, `all.ndjson`, record types, IDs and data remain
unchanged. Restore a legacy or Relay backup by extracting its `all.ndjson` and
using the existing backup import workflow. The ZIP filename is not a format
marker; importing a ZIP directly is not added by this change.

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

The release/channel and deployment decisions are outside this code change.
Nothing here starts a server or migrates an existing database.

## Reverting this naming change

Reverting code restores the old task/configuration names. Existing attachments
and Relay backup payloads remain readable. Before reverting, switch configured
`RELAY_*` names back to `SURE_*` (or set both consistently), and use the legacy
task names: the older application does not know the new names. No data migration
is required.

Reverting this writer release requires code that can still read `RelayImport`
records and queued GlobalIDs. Reversing the default does not rewrite data or
change this requirement. Do not narrow the session constraint while Relay
sessions exist; its reverse migration refuses to do so. Reverting files in Git
does not revert an installation's database.
