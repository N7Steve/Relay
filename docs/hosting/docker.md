# Self-hosting Relay with Docker

Relay is supported as a single self-hosted instance built from this repository
with Docker. The maintained installation is the TrueNAS folder app described in
the [TrueNAS guide](truenas.md); this page covers the generic Compose example for
other Docker hosts. There is no public image, registry channel or Helm chart.

## Prepare an image

From a checkout of the intended revision, build a local image. This command builds
only; it does not start Rails or prepare a database:

```sh
docker build --build-arg BUILD_COMMIT_SHA="$(git rev-parse HEAD)" -t relay:local .
```

Set `RELAY_IMAGE=relay:local` in a private environment file. A local tag belongs
to the Docker engine on which it was built. Alternatively, combine
`compose.example.yml` with `compose.source.yml` to build web and worker from the
checkout, pinning `RELAY_COMMIT_SHA` for build metadata.

## Prepare configuration

Copy `compose.example.yml` and `.env.example` to the installation directory and
keep real credentials out of Git. `POSTGRES_PASSWORD`, `SECRET_KEY_BASE` and
`RELAY_IMAGE` are required; new installations default to the `relay_production`
database and `relay_user` role. Existing installations keep their encryption keys
and credentials until a separately validated rotation.

Optional integrations are configured through environment variables:
[Google Drive exports](google-drive-exports.md), [Brandfetch logos](logos.md),
[OIDC/SSO](oidc.md) and [passkeys](webauthn.md). Enable Banking connections are
configured per family in the application. Each external capability is off by
default: Brandfetch logos are enabled in the self-hosting settings, while bank
sync and Google Drive are enabled with `RELAY_EXTERNAL_BANK_SYNC_ENABLED=true` and
`RELAY_EXTERNAL_GOOGLE_DRIVE_ENABLED=true` (or the matching stored setting).

Validate the rendered configuration without starting services:

```sh
docker compose --env-file /path/to/private.env -f compose.example.yml config --quiet
```

The `backup` profile runs scheduled PostgreSQL dumps to an rclone destination.
It does not copy attachments or keys; a complete server backup must also include
`/rails/storage` and the private environment file. Family ZIP exports are a
separate data-recovery path, described in [backups](../llm-guides/backups.md).

## Binding to IPv6

Puma binds to `BINDING` (default `0.0.0.0` in containers). For dual-stack access,
set `BINDING=::` in the web environment and publish `[::]:${PORT}:3000`, as
commented in `compose.example.yml`.

## Operation

Starting web runs the Docker entrypoint's `db:prepare`, which migrates the
database: treat starting a new revision as an update, and take a complete backup
first. Keep web and worker on the same image. Relay sends no analytics, surveys
or external monitoring; operational logs go to STDOUT.

The scope of the maintained product is summarized in
[Relay product scope](../product-scope.md). Release notes and issue tracking
belong to [N7Steve/Relay](https://github.com/N7Steve/Relay).
