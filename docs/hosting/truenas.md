# Relay on TrueNAS 25.10: installation in AppsPool/relay

Relay is built and verified on the development computer and published to the local
Gitea Container Registry as `100.81.25.109:30008/n7steve/relay`. TrueNAS never
compiles Relay: a cron job runs the updater, which pulls the `stable` channel and
applies it with a backup. The image also bundles the signed Android APK, so the
native app updates itself from Relay once the server is updated. See
[local releases](local-releases.md).

## Registry access

The NAS pulls `127.0.0.1:30008/n7steve/relay` over loopback from the local Gitea
instance (no `daemon.json` changes needed on TrueNAS).

- **Private package**: create a Gitea token with only `read:package` and store it
  with the app, not in `/root`, so it survives TrueNAS upgrades:

  ```bash
  sudo mkdir -p /mnt/AppsPool/relay/registry
  sudo chmod 700 /mnt/AppsPool/relay/registry
  sudo DOCKER_CONFIG=/mnt/AppsPool/relay/registry docker login 127.0.0.1:30008 -u n7steve --password-stdin
  ```

  The updater uses `/mnt/AppsPool/relay/registry/config.json` automatically when
  it exists. For a first installation also run
  `sudo DOCKER_CONFIG=/mnt/AppsPool/relay/registry docker pull 127.0.0.1:30008/n7steve/relay:stable`
  so TrueNAS finds the image locally.

## Fresh installation

Use [`compose.truenas.folder.yml`](../../compose.truenas.folder.yml) in **Apps →
Discover Apps → ⋮ → Install via YAML**, with app name **relay**. Paste the entire
YAML, including its `x-*` anchors. No `.env`, manually supplied passwords,
checkout or SHA is required. The Apps pool must already be configured,
`/mnt/AppsPool` must exist and host port 3002 must be free. The app publishes
**http://TRUENAS-IP:3002**. Create your account, then import the complete family
backup ZIP through Relay.

## Folder layout

```text
/mnt/AppsPool/relay/
├── update-relay.sh             # installed automatically, root-owned
├── config/                    # relay.env and postgres-password
├── registry/                  # optional docker login for a private package
├── postgres/                  # PostgreSQL 16 data
├── redis/                     # persistent Redis queue/AOF
├── storage/                   # attachment binaries
├── backups/                   # separate complete server backups per update
├── logs/                      # updater logs
├── deployment/                # installation template, active config, SHA and image
├── .work/                     # temporary files; removed on exit
└── .update.lock                # prevents concurrent updater runs
```

`releases/` is only used by the former source-build updater and can be deleted
after the first registry update.

The parent directory and management directories are private to root. The Rails
config file is mode 0600 and belongs to UID 1000; storage also belongs to UID 1000.
PostgreSQL and Redis manage ownership of their own data directories. Init
preserves existing encryption keys and refuses to generate replacements if a
database already exists. Do not recursively change ownership/permissions to a
single user, or replace `config` when reinstalling.

Web loads `/config/relay.env` and uses the Docker entrypoint's `db:prepare`.
Worker starts after web becomes healthy. Database/user remain
`relay_production`/`relay_user`, PostgreSQL stays on major version 16 and HTTP
remains on host port 3002. Container stdout logs are capped at three 10 MB files
per service.

## Automatic updates (cron)

In **System → Advanced Settings → Cron Jobs → Add**:

| Field       | Value                                               |
| ----------- | --------------------------------------------------- |
| Description | Relay updater                                       |
| Command     | `bash /mnt/AppsPool/relay/update-relay.sh --cron`   |
| Run As User | `root`                                              |
| Schedule    | Every 15 minutes (`*/15 * * * *`) or a nightly time |
| Hide stdout | enabled; Hide stderr disabled                       |

Each run:

1. Checks AppsPool, takes the lock (a concurrent cron run exits quietly) and pulls
   `100.81.25.109:30008/n7steve/relay:stable`. Registry errors stop before touching Relay.
2. Requires a `linux/amd64` image with one registry digest and a
   `BUILD_COMMIT_SHA`.
3. Validates the running `relay` app and its mounts. Other app names, foreign
   images, other storage locations and named-volume layouts are rejected.
4. Exits if web and worker already run that image and web is healthy. With
   `--cron` such a run leaves no log file.
5. Stops web/worker gracefully and saves PostgreSQL, config/keys, attachments,
   Redis and the before/after app configuration to a private backup directory.
6. Pins the image **by digest** through TrueNAS `app.update`, preserving
   environment, ports and mounts. The configuration is sent over the middleware
   socket with TrueNAS's Python client, never as a command-line argument: TrueNAS
   audits commands run through `sudo` (cron jobs included), and sudo kills a
   process whose long arguments it cannot verify (`argv mismatch`). It polls the
   state of that job by ID. Web prepares/migrates the database on startup.
7. Waits for web health and worker startup, verifies the running image and commit,
   checks that no migrations are pending and records the SHA and digest.
8. Removes older Relay images, keeping the running and previous one.

Run it by hand with `sudo bash /mnt/AppsPool/relay/update-relay.sh`, or validate
without stopping anything with `--check` (it still pulls the channel image).
Do not edit the app in TrueNAS while an update runs; the updater refuses to
overwrite a configuration changed during the backup.

If an attempt fails, cron skips that digest to avoid repeatedly stopping Relay.
Review the log and the TrueNAS job before retrying by hand. Cron can still apply
a new digest. The updater checks for active TrueNAS update jobs before stopping
any services.

### Moving an existing source-build installation

Installations created with the earlier YAML build `main` on the NAS. Configure
registry access, then run the installed updater **once by hand**:

```bash
sudo bash /mnt/AppsPool/relay/update-relay.sh
```

That run still uses the old updater: it builds the current `main`, whose init
installs the new registry updater. From the next run (by hand or cron) the app
switches to the published digest and stops building locally. The data folders
are reused unchanged.

## Backups and failures

Each update writes `backups/relay-<UTC timestamp>-<unique suffix>/` with:

- `database.dump` and its table of contents (`pg_dump -Fc`, checked by `pg_restore`).
- `config.tar.gz`, `storage.tar.gz` and `redis.tar.gz`.
- The before/after app configuration, metadata, middleware result and SHA256 sums.
- `BACKUP_COMPLETE` once all backup validation passes; `UPDATE_COMPLETE` only
  after the updated app passes its startup checks.

Backups are only created when an update is applied and are never pruned
automatically; delete old ones when they are no longer needed. They contain
private keys and credentials and are separate from Relay's family ZIP export.

If backup fails before `app.update`, the script restarts the services it stopped
and leaves the original image in place. If TrueNAS rejects `app.update` (no job
running and the stored configuration unchanged), nothing was applied: the script
resumes the previous version and keeps the client error or job status in the
backup folder as `update-error.txt`. Use the job ID from the updater log to
inspect failed jobs in TrueNAS. If it cannot tell
whether the change was applied, it resumes nothing and keeps the backup; check
the app in TrueNAS and `logs/`. Once an update has been applied, it does not roll
back code against a potentially migrated database.
To return to the previous release, restore database, keys, storage and Redis
together and set the previous digest from `app-before.json`.

References: [TrueNAS custom apps](https://apps.truenas.com/managing-apps/installing-custom-apps/),
[TrueNAS cron jobs](https://www.truenas.com/docs/scale/scaletutorials/systemsettings/advanced/managecronjobsscale/),
[app.update API](https://api.truenas.com/v25.10/api_methods_app.update.html),
[Docker bind mounts](https://docs.docker.com/reference/compose-file/services/#volumes).

For maintainers: after editing `bin/update-relay.sh`, run
`ruby bin/render-relay-yaml.rb` in Linux (the release script does it in a Ruby
container) to refresh the YAML's embedded bootstrap copy. It escapes dollars for
Compose interpolation; the deployment tests verify the copies match.
