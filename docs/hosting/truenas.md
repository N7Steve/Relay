# Relay on TrueNAS 25.10: one YAML installation

Use [`compose.truenas.yml`](../../compose.truenas.yml) in **Apps → Discover Apps →
⋮ → Install via YAML**, with app name **relay**. Paste the entire file, including
the `x-*` anchors and `volumes`. No `.env`, checkout, dataset path, registry or
manually supplied password is needed. The Apps pool must already be configured,
outbound access to GitHub/Docker and dependency registries must work, and host
port 3002 must be free. The source repository is public.

The YAML builds the pinned Git revision locally, generates private credentials
inside a persistent volume, creates PostgreSQL 16, Redis, storage, Rails and
Sidekiq, and publishes **http://TRUENAS-IP:3002**. First build downloads/compiles
dependencies and can take several minutes. Create your first account through
the UI; no default administrator or demo financial data is installed.

## Persistence and startup

All resources are scoped to the app's Compose project. No `sure-web-test`
container, database, port 3001 or source volume is referenced.

| Volume | Content |
| --- | --- |
| `relay-config` | Database password, session secret and all three encryption keys |
| `relay-postgres` | Database `relay_production`, owned by `relay_user` |
| `relay-storage` | Active Storage attachment binaries |
| `relay-redis` | Persistent queue state (AOF) |

An idempotent init service generates keys only on the first installation. It
refuses to replace missing keys if a PostgreSQL database already exists. It
does not print credentials. Database password is read from a file; Rails loads
the same configuration in web and worker. Encryption keys are explicit and
remain stable even if Rails changes its default derivation in a future release.

Web uses the existing Docker entrypoint's `db:prepare`: on an empty database it
loads the schema/seeds, and on later releases it runs pending migrations. Worker
waits for the web health check, so it cannot consume jobs before initial setup.
Only web publishes a host port. Telemetry stays disabled. HTTP is configured for
initial access on the local network; TLS/proxy can be added later without moving
the database or regenerating keys.

## Updates

Keep the **same TrueNAS app name**, volume definitions and saved configuration.
Before updating, take a consistent PostgreSQL backup plus configuration and
attachment copies; include Redis if pending jobs must be preserved. Docker
volumes reside in the configured Apps pool; they are not independently named
ZFS datasets in the Storage UI. A database backup alone cannot restore encrypted
credentials or attachment binaries. Persisted volumes are not automatic backups.

Edit the app YAML's `x-relay-image` anchor:

1. Set the Git context's full SHA to the approved release revision.
2. Set `BUILD_COMMIT_SHA` to the identical SHA.
3. Give `image` a new local tag for that revision.

TrueNAS/Compose builds the new revision (`pull_policy: build`), then starts the
same services against the same volumes. This changes application code, not
database names, users or storage layout. Do not use the floating `main` ref for
an unattended upgrade. Do not bump PostgreSQL to another major version as part
of a routine application update. New application migrations can still require
release-specific review; no promise of compatibility with every future schema
change is made. Restoring only the previous image after a schema/data change is
not a complete rollback.

Do not delete the app's volumes when updating/reinstalling. Deleting
`relay-config` loses encryption/session credentials; deleting database/storage
volumes loses records/attachments. Recover from the matching backups instead of
allowing init to create replacement keys.

## Importing Sure later

This is a fresh installation suitable for continued use, not an automatic import.
The existing Sure app remains separate until Relay is stable. Follow the
[migration runbook](../migration/final-runbook.md). Its database version/schema,
binary storage and encryption configuration still need to be inventoried and
tested with real backups. Restoring the entire Sure database requires retaining
or deliberately converting its encryption keys; replacing database files under
new Relay keys does not decrypt existing credentials. That controlled import
may require updating the private configuration volume, not redesigning the YAML
or changing Relay's database names. Do not send the keys in chat or put them in Git.

The deployment foundation is tested separately from restoration of source data.
Successful Rails unit tests and Docker boot cannot certify a future real-data
import or operation on hardware that has not yet run this YAML.

References: [TrueNAS custom apps](https://apps.truenas.com/managing-apps/installing-custom-apps/),
[Docker Git build contexts](https://docs.docker.com/build/concepts/context/).
