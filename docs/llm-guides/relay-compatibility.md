# Relay configuration and backup compatibility

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

`SureImport` remains the persisted STI type and API import type. API routes,
`X-Api-Key`/OAuth authentication, family permissions, encryption keys and
historical migrations are unchanged. Renaming that type requires a separate
transition for database constraints, workers and clients.

## Reverting this naming change

Reverting code restores the old task/configuration names. Existing attachments
and Relay backup payloads remain readable. Before reverting, switch configured
`RELAY_*` names back to `SURE_*` (or set both consistently), and use the legacy
task names: the older application does not know the new names. No data migration
is required.
