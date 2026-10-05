# Contributing to Relay

It means so much that you're interested in contributing to Relay! Seriously. Thank you. The entire community benefits from these contributions!

## House Rules

- Before contributing, read the [repository guidance](AGENTS.md) and [architecture and conventions](docs/llm-guides/architecture.md). Detailed [task guides](docs/llm-guides/README.md) cover testing, UI, APIs and providers.
- Coding-assistant setup is optional; see the [supported instruction adapters](docs/llm-guides/harness-adapters.md).
- Before contributing, please check if it already exists in [issues](https://github.com/N7Steve/Relay/issues) or [PRs](https://github.com/N7Steve/Relay/pulls)
- Given the speed at which we're moving on the codebase, we don't assign issues or "give" issues to anyone.
- When multiple PRs are submitted for the same issue, we take the one that most succinctly & efficiently solves a given problem and stays within the scope of work.
- Priority is generally given to previous committers as they've proven familiarity with the codebase and product.

## What should I contribute?

Relay is a personal, self-hosted project with a deliberately reduced scope; see
[Relay product scope](docs/product-scope.md). Fixes and improvements to the
maintained product are welcome. Reintroducing retired features requires an
explicit product decision.

## Development

### Setup

To get setup for local development, you have two options:

1. [Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers) with VSCode (see the `.devcontainer` folder)
   - A `selenium/standalone-chrome` service is included in the Dev Container setup, so **system tests work out of the box** — no local Chrome required.
   - Run system tests: `DISABLE_PARALLELIZATION=true bin/rails test:system`
   - Watch the browser live at `http://localhost:7900` or `http://localhost:4444` (password: `secret`)
2. Docker on Windows or Linux: [local app](docs/llm-guides/docker-local-app.md) and [tests](docs/llm-guides/docker-tests.md); see also the [development guide](docs/llm-guides/development.md)

### Relay maintenance workflow

Work directly on `main` and keep changes small and cohesive. Prepare and validate
the changes before presenting them to the owner. Commit and push to `origin/main`
only after the owner confirms the changes; an explicit request to commit or push
already supplies that confirmation. Do not create branches, worktrees or pull
requests unless the owner explicitly requests an exception. Preserve existing
work and use fast-forward synchronization; do not reset or force-push.

See [repository guidance](AGENTS.md) and the
[development guide](docs/llm-guides/development.md) for required verification.
Dependabot PRs are update proposals that require review and validation before
integration; their existence does not authorize automatic merges or closure.

### Making a Pull Request when explicitly requested

The following inherited contribution workflow applies to an explicitly requested
PR or a contribution to upstream Sure, rather than routine Relay maintenance.

1. Fork the repo
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request, and be sure to check the [Allow edits from maintainers](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/allowing-changes-to-a-pull-request-branch-created-from-a-fork) option while creating your PR. This allows maintainers to collaborate with you on your PR if needed.
6. If possible, [link your pull request to an issue](https://docs.github.com/en/issues/tracking-your-work-with-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword) by adding the appropriate keyword (e.g. `fixes issue #XXX`)
7. Before requesting a review, please make sure that all [Github Checks](https://docs.github.com/en/rest/checks?apiVersion=2022-11-28) have passed and your branch is up-to-date with the `main` branch. After doing so, request a review and wait for a maintainer's approval.

All PRs should target the `main` branch.

### Automated Security Scanning

Every pull request to the `main` branch automatically runs a Pipelock security scan. This scan analyzes your PR diff for:

- Leaked secrets (API keys, tokens, credentials)
- Agent security risks (misconfigurations, exposed credentials, missing controls)

The scan runs as part of the CI pipeline and typically completes in ~30 seconds. If security issues are found, the CI check will fail. You don't need to configure anything—the security scanning is automatic and zero-configuration.
