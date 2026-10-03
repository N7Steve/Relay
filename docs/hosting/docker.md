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
explicitly. The database defaults in the examples are inherited installation
names, not an instruction to rename an existing database. For a new installation
use, for example, `relay_production` and `relay_user`, with private generated
credentials. Existing installations retain their original encryption keys and
credentials until a separately validated rotation.

Review storage mounts, Compose project name, port exposure, TLS/proxy settings,
onboarding and provider callbacks for that installation. A changed project name
selects different named volumes; never point a rehearsal at the live volumes.
The examples' SSL switches assume a separately reviewed network configuration.

Validate the rendered configuration without starting services:

```sh
docker compose --env-file /path/to/private.env -f compose.example.yml config --quiet
```

Self-hosted feedback is disabled without an explicit `POSTHOG_FEEDBACK_KEY` and
`POSTHOG_SELF_HOSTED_SANKEY_SURVEY_ID`. Leave these empty for no feedback
collection. General analytics remains separately controlled by `POSTHOG_KEY`.
See [feedback configuration](preview-feedback.md).

## Existing Sure installation

Use the [final migration runbook](../migration/final-runbook.md) and answer the
[decision form](../migration/final-decisions.md) before changing the installation.
The Docker entrypoint can prepare/migrate a database when starting Rails: starting
web is an operational migration step, not an image-build check.

Do not regenerate existing keys, change database names, switch volume mounts or
use a financial export as a complete installation backup. The legacy Sure Docker
guide is retained under `docs/archive/sure/hosting/docker.md` for historical
reference; its upstream image and setup instructions are not Relay defaults.

Release notes and issue tracking belong to [N7Steve/Relay](https://github.com/N7Steve/Relay).
