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

## Backup import names: reader rollout

Web and API requests accept both `RelayImport` and `SureImport`. Both use the
same NDJSON validation, limits, upload, preflight and publication workflow.
The web upload form now submits `RelayImport`; old links still work. Routes,
`X-Api-Key`/OAuth authentication and family permissions remain unchanged.

This release deploys compatible readers **before** changing stored types:

| Surface | Current behavior |
| --- | --- |
| Web/API import creation | Both names write `SureImport` through `Import.storage_type` |
| API preflight | Both names return `data.type: SureImport`; no data/jobs are created |
| API import type filter | Either name selects both stored backup types, within the current family |
| API import details/list | `type` reflects the stored type; readers support both names |
| Session creation/retry | Both input names resolve to `SureImport`, including retries with the other name |
| Session/chunk writes | Keep `SureImport`, the session default and its existing database constraint |
| Jobs queued by web/API | Keep legacy `SureImport` GlobalIDs; session jobs keep `ImportSession` |

`RelayImport < SureImport` adds a real STI reader without duplicating the backup
implementation. It reads records with type `RelayImport`; the legacy parent
also reads both types. `backup_import_sti.rb` loads the subclass in `to_prepare`
so legacy queries/GlobalIDs can find Relay records even with lazy loading and
after development reloads. Existing `SureImport::Preflight`, exception classes
and localized keys stay available. Attachments still use polymorphic record
type `Import`; no files are moved or reattached. Session source mappings and
the `sure_import_session:<id>` source key stay intact.

The tests exercise both STI names, their GlobalIDs, serialized import/revert
jobs, attachments, preflight, verification and session workers. Relay-type
records are created **only in isolated tests** to validate the future reader.
Normal writers in this release do not create them. Do not use
`RelayImport.create!` or change types manually on an installation while older
workers are still running. No data backfill or migration is included here.

### Next rollout steps

1. Deploy this reader release to every web and worker process. Verify versions
   and queued/retrying/scheduled jobs; restarting only web is insufficient.
2. Add a new current-version migration to expand the session type constraint
   to both names. Keep legacy records valid and test upgrade/reversal on an
   isolated copy. Do not alter historical migrations. This schema expansion
   must precede writing new session types; it need not rewrite data.
3. Coordinate the writer change, database defaults and clients. Preserve the
   original session type when an idempotency key is retried with the other name,
   and test mixed legacy/new chunks and old GlobalIDs. Account for older clients
   whose response enums only accept `SureImport` before returning new types.
4. A backfill is optional and separate: old types can remain readable. If one
   is needed, define batching, backup, counts, queued jobs and rollback first.
   Retain the legacy class and reader while legacy records or jobs exist.

The release/channel and deployment decisions are outside this code change.
Nothing here starts a server or migrates an existing database.

## Reverting this naming change

Reverting code restores the old task/configuration names. Existing attachments
and Relay backup payloads remain readable. Before reverting, switch configured
`RELAY_*` names back to `SURE_*` (or set both consistently), and use the legacy
task names: the older application does not know the new names. No data migration
is required.

Reverting this reader release also requires clients/forms to send `SureImport`
again. It is data-compatible while normal writers have kept the legacy type.
If an operator has manually created Relay STI records or queued Relay GlobalIDs,
older code cannot read them: inspect those records/jobs before reverting. Once
new session types are written in a later rollout, narrowing the constraint is
not safe until those rows are handled explicitly.
