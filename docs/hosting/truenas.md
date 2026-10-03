# Relay on TrueNAS 25.10: installation in AppsPool/relay

Use [`compose.truenas.folder.yml`](../../compose.truenas.folder.yml) in **Apps →
Discover Apps → ⋮ → Install via YAML**, with app name **relay**. This is a fresh
installation. Import your complete family backup through Relay after startup;
there is no transfer from the previous Docker volumes.

The YAML is self-contained: it includes the bootstrap updater, so you can paste
it directly without first publishing deployment files. Initial installation
builds the complete-backup revision `d7452d794` and later updates follow `main`.
The Apps pool must already be configured,
`/mnt/AppsPool` must exist on the NAS, outbound GitHub/Docker/registry access must
work, and host port 3002 must be free. Paste the entire YAML, including its `x-*`
anchors. No `.env`, manually supplied passwords, checkout or SHA is required.

The app publishes **http://TRUENAS-IP:3002**. Its first build can take several
minutes. Create your account, then import the ZIP using the complete-backup import option.

## Folder layout

The init service creates the directory scaffold and uses explicit host bind
mounts instead of Docker named volumes:

```text
/mnt/AppsPool/relay/
├── update-relay.sh             # installed automatically, root-owned
├── config/                    # relay.env and postgres-password
├── postgres/                  # PostgreSQL 16 data
├── redis/                     # persistent Redis queue/AOF
├── storage/                   # attachment binaries
├── backups/                   # separate complete server backups per update
├── logs/                      # updater/build logs
├── releases/<commit>/         # source code downloaded by the updater
├── deployment/                # installation template, active config and SHA
├── .work/                     # temporary downloads/configuration; removed on exit
└── .update.lock                # prevents concurrent updater runs
```

Application data and management files live here. TrueNAS still manages its own
app metadata, Docker images/build cache and container stdout logs inside its
Apps infrastructure; a per-app YAML cannot relocate that shared Docker engine.
Container stdout logs are capped at three 10 MB files per service. Updater logs
and downloaded releases are kept under the folder shown above.

The parent directory and management directories are private to root. The Rails
config file is mode 0600 and belongs to UID 1000; storage also belongs to UID 1000.
PostgreSQL and Redis entrypoints manage ownership of their own data directories.
Init preserves existing encryption keys and refuses to generate replacements if
a database already exists. Do not recursively change ownership/permissions to a
single user, or replace `config` when reinstalling.

Web loads `/config/relay.env` and uses the Docker entrypoint's `db:prepare`.
Worker starts after web becomes healthy. PostgreSQL reads its password from the
same config directory. Database/user remain `relay_production`/`relay_user`,
PostgreSQL stays on major version 16, and HTTP remains on host port 3002.

## Automatic update with one command

Run **on the TrueNAS host** (Shell or SSH):

```bash
sudo bash /mnt/AppsPool/relay/update-relay.sh
```

There are no required arguments. Each invocation:

1. Checks that AppsPool is mounted and locks the updater.
2. Resolves the current `N7Steve/Relay` **main** branch to a full SHA through the
   GitHub API. Network/rate-limit errors stop the operation before touching Relay.
3. Validates the running `relay` app and its mounts. Other app names, source
   repositories, storage locations and legacy named-volume layouts are rejected.
4. Returns immediately if healthy web and running worker already report that SHA.
5. Downloads that exact commit to `releases/<SHA>` and builds it locally before
   downtime, preserving Docker's build cache. Later movement of `main` does not
   change the chosen source revision during this run.
6. Stops web/worker gracefully and saves PostgreSQL, config/keys, attachments,
   Redis and the before/after app configuration to a private backup directory.
7. Applies the pinned image through TrueNAS `app.update`, preserving installed
   environment, ports and mounts. Web prepares/migrates the database on startup.
8. Waits for web health and worker startup, verifies both running commit IDs and
   checks that no migrations are pending. Saves the active configuration and SHA.

For a read-only app check, optionally use:

```bash
sudo bash /mnt/AppsPool/relay/update-relay.sh --check
```

This still queries GitHub and writes a local run log, but does not download/build
source, back up, stop or update the app. It does not prove the target code builds.
Run the normal command to apply the latest main commit. Automatic selection of
`main` is intentional; this updater does not wait for a GitHub release or CI.
It updates when invoked, not on a recurring schedule. Do not edit the app in
TrueNAS while it is running; it also checks for intervening configuration changes.

The bootstrap image uses a pinned Git commit and `pull_policy: missing` to build
only when that image is absent. The first updater run replaces it with an image tagged for an exact SHA
and `pull_policy: never`. Subsequent restarts reuse that image. Init atomically
installs the updater shipped with each new image, falling back to the embedded
bootstrap script for releases that do not include it. Publishing future updater
changes in `main` therefore updates the installed script on the next upgrade.
When present in the image, `installation-template.yml` is copied as a reference,
not the active config: re-pasting it would reset the pinned bootstrap settings.

## Backups and failures

Each update writes `backups/relay-<UTC timestamp>-<unique suffix>/` with:

- `database.dump` and its table of contents (`pg_dump -Fc`, checked by `pg_restore`).
- `config.tar.gz`, `storage.tar.gz` and `redis.tar.gz`.
- The before/after app configuration, metadata, middleware result and SHA256 sums.
- `BACKUP_COMPLETE` once all backup validation passes; `UPDATE_COMPLETE` only
  after the updated app passes its startup checks.

The dump catalog, compressed streams and tar structure are checked; this is not
a full restore rehearsal. Incomplete directories without `BACKUP_COMPLETE` must
not be treated as complete backups. These server backups contain private keys
and credentials and are separate from Relay's family ZIP export/import.

If download/build/backup fails before `app.update`, the script leaves the original
code in place and attempts to restart any services it stopped. If the update has
started, it keeps the matching backup and does not automatically roll back code
against a potentially migrated database. Review the Relay app/update job and
`logs/` on the NAS; recover database, keys, storage and Redis together if needed.
Startup checks do not exercise every feature. Backups, source releases and old
images are retained; the updater does not prune other apps' Docker images.

## Native TrueNAS update detection

TrueNAS monitors registry images and can offer an update action for custom apps.
This deployment builds Relay locally, so a new Git commit is handled by the
script above. A native update badge could refer to PostgreSQL or Redis instead.
Native detection for Relay itself would require publishing images to a registry
and following a maintained tag such as `stable`; that is not this deployment.

The previous [`compose.truenas.yml`](../../compose.truenas.yml) remains available
as the historical named-volume installation. It is not compatible with this
folder updater; no migration or deletion of its data is performed.

References: [TrueNAS custom apps](https://apps.truenas.com/managing-apps/installing-custom-apps/),
[TrueNAS custom app updates](https://apps.truenas.com/managing-apps/managing-installed-apps/#managing-custom-apps),
[app.update API](https://api.truenas.com/v25.10/api_methods_app.update.html),
[Docker bind mounts](https://docs.docker.com/reference/compose-file/services/#volumes).

For maintainers: after editing `bin/update-relay.sh`, run
`ruby bin/render-relay-yaml.rb` in the Linux development environment to refresh
the YAML's embedded bootstrap copy. It escapes dollars for Compose interpolation;
the deployment tests verify the copies match.
