# Self-hosting Relay with Docker

Relay is built from this repository. There is no selected public release channel
or default upstream application image. The standard and AI Compose examples
require `RELAY_IMAGE` explicitly and use the same image for web and worker.

## Prepare an image

From a checkout of the intended revision, build a local image. This command builds
only; it does not start Rails or prepare a database:

```sh
docker build --build-arg BUILD_COMMIT_SHA="$(git rev-parse HEAD)" -t relay:local .
```

Set `RELAY_IMAGE=relay:local` in a private environment file, or use an approved
registry image pinned to its digest. A local tag belongs to the Docker engine on
which it was built; building on a workstation does not install it on a server.

## Prepare configuration

Copy `compose.example.yml` (or the optional AI example) and `.env.example` to the
chosen installation directory. Keep real credentials out of Git. Configure
`POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` and `SECRET_KEY_BASE`
explicitly. The new installation defaults are `relay_production` and `relay_user`; password
and secret key must be supplied explicitly, with private generated credentials. Existing installations retain their original encryption keys and
credentials until a separately validated rotation.

Review storage mounts, Compose project name, port exposure, TLS/proxy settings,
onboarding and provider callbacks for that installation. A changed project name
selects different named volumes; never point a rehearsal at the live volumes.
The examples' SSL switches assume a separately reviewed network configuration.

Validate the rendered configuration without starting services:

```sh
docker compose --env-file /path/to/private.env -f compose.example.yml config --quiet
```

Relay disables analytics, surveys and external monitoring regardless of inherited
`POSTHOG_*`, `SENTRY_*`, `SKYLIGHT_*` or `LOGTAIL_*` values. Operational logs remain
on STDOUT. See [telemetry policy](preview-feedback.md).

## Build directly from Git for the test installation

The current Sure test container on TrueNAS 25.10.4 uses the local image
`sure-staging-web-test` and publishes host port 3001. Relay's initial test must
use a separate project, image, database/storage and host port. The old container
continues running; import data only after Relay is stable.

A source-build override is provided as `compose.source.yml`. In the private Relay
test environment file, set a new local `RELAY_IMAGE` (for example
`relay-staging-web-test`), explicit database credentials/name, `SECRET_KEY_BASE`
and an unused `PORT` (for example 3002). Confirm mounts/project before starting.
Pin the exact Git revision in `RELAY_COMMIT_SHA` for build metadata.

Validate the configuration from the checkout without starting services:

```sh
docker compose --env-file /path/to/relay-test.env -p relay-test \
  -f compose.example.yml -f compose.source.yml config --quiet
```

Build from the checkout with the same arguments and `build`; this does not start
Rails. Creating/starting the TrueNAS test app is a later installation step. Do not
reuse the Sure project's volumes or overwrite its private environment file.
The precise Sure build command/configuration is being inventoried with read-only
container labels; no registry publication is assumed from the local image name.

## Existing Sure installation

Use the [final migration runbook](../migration/final-runbook.md) and the recorded
[decisions](../migration/final-decisions.md) before changing the installation.
The Docker entrypoint can prepare/migrate a database when starting Rails: starting
web is an operational migration step, not an image-build check.

Do not regenerate existing keys, change database names, switch volume mounts or
use a financial export as a complete installation backup. The legacy Sure Docker
guide is retained under `docs/archive/sure/hosting/docker.md` for historical
reference; its upstream image and setup instructions are not Relay defaults.

Release notes and issue tracking belong to [N7Steve/Relay](https://github.com/N7Steve/Relay).
