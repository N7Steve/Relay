# Repository guidance

## Working in the repository

- Read [architecture and conventions](docs/llm-guides/architecture.md) before changing code, and the relevant [task guides](docs/llm-guides/README.md).
- For upstream reviews and integrations, follow [fork direction and selective integration](FORK_EVOLUTION.md): present complete features for the user's selection first, then integrate only the approved scope. Use [FORK_CUSTOMIZATIONS.md](FORK_CUSTOMIZATIONS.md) as the preservation map.
- Rails code lives in `app/`; keep business logic in models, concerns and POROs, with thin controllers. JavaScript is in `app/javascript/`, components in `app/components/`, assets in `app/assets/`, and configuration in `config/`.
- Minitest tests mirror `app/` under `test/`; fixtures are in `test/fixtures/`. Migrations and schema are in `db/`, scripts in `bin/`, shared libraries in `lib/`.
- Use `Current.user` and `Current.family`, never `current_user` or `current_family`. Preserve family tenancy and existing authorization boundaries.
- Prefer built-in Rails patterns and established dependencies. New dependencies need a strong technical or business reason. Keep changes focused, readable and consistent with nearby code.
- Ruby uses two-space indentation, `snake_case` methods/variables and `CamelCase` classes. JavaScript uses `lowerCamelCase` variables/functions and `PascalCase` classes; follow Biome. Keep domain logic out of ERB.
- Never commit secrets; use environment variables and `.env.local` for local configuration.
- Do not start `rails server`, touch `tmp/restart.txt`, run `rails credentials`, or automatically run migrations. Setup and database commands in the [development guide](docs/llm-guides/development.md) are for explicitly requested environment work.
- New migrations use the current Rails migration version; leave historical migration versions intact.

## Git workflow, tests and publication

- Work directly on `main`. Do not create separate branches, worktrees or pull requests unless the user explicitly requests an exception.
- Before changing files, inspect the working tree and synchronize `main` with `origin/main` using a fast-forward when possible. Preserve existing user changes; never reset, discard work or force-push to resolve divergence.
- Prepare and validate the changes, then present the concrete result. Commit and push directly to `origin/main` only after the user confirms those changes. An explicit instruction such as "commit and push" or "sube los cambios" counts as confirmation; do not ask again for the same scope.

- Use Minitest and fixtures for behavioral tests, with Mocha and VCR where needed. RSpec/rswag is for OpenAPI documentation only. Follow the [testing guide](docs/llm-guides/testing.md).
- Run `bin/rails test` and ensure it is green before pushing. Before opening a PR, run **all** checks in the [pre-PR checklist](docs/llm-guides/development.md#before-opening-a-pull-request): full Rails tests, applicable system tests, Ruby and ERB lint, Biome and Brakeman. Only create the PR when all required checks pass.
- Commits use imperative subjects of at most 72 characters, with rationale and issue references where relevant. Target `main` with small, cohesive changes.
- PRs explain the problem, resulting behavior and validation; link issues and include screenshots for UI changes and migration notes when applicable. Ensure CI passes and the branch is up to date before requesting review; see [CONTRIBUTING.md](CONTRIBUTING.md).
- PR-specific requirements apply only when the user explicitly requests a PR. Dependency update proposals from Dependabot require review and validation before integration; do not merge or close them automatically.

## UI changes

When touching ERB, view components or CSS, follow the [design system guide](docs/llm-guides/design-system.md):

- Use functional tokens from `app/assets/tailwind/relay-design-system.css`, such as `bg-container`, `text-primary`, `border-primary`, `bg-warning/10` and `text-destructive`. No raw Tailwind palette classes or hex literals.
- Check `app/components/DS/` first for alerts, badges, buttons, disclosures, dialogs and inputs. Use existing `DS::*` primitives.
- If the same hand-built shape appears at least twice in a diff with no DS equivalent, propose a new `DS::*` primitive before the second copy lands.
- Use the `icon` helper, never `lucide_icon` directly; no raw SVG outside DS primitives. Use `t()` for user-facing strings and scale tokens instead of arbitrary pixel values when a scale token fits.
- Adding styles to `app/assets/tailwind/relay-design-system.css` or `app/assets/tailwind/application.css` requires explicit permission.
- Reviewers escalate DS reuse and repeated-shape violations to close/rewrite; token and icon/SVG/localization/scale violations are request-changes.

## API changes

Adding or modifying `app/controllers/api/v1/` endpoints requires Minitest behavioral coverage and corresponding **documentation-only** rswag specs in `spec/requests/api/v1/`. Reusable schemas belong in `spec/swagger_helper.rb`; regenerate `docs/api/openapi.yaml` with `RAILS_ENV=test bundle exec rake rswag:specs:swaggerize` after changes.

**Post-commit API consistency:** after every API endpoint commit, follow the [API checklist](docs/llm-guides/api-endpoint-consistency.md): Minitest coverage, no behavioral assertions in rswag, and the shared `X-Api-Key` authentication pattern in those tests/specs.

## Provider and feature work

- Read [provider sync guidance](docs/llm-guides/providers.md) when changing imports, pending transactions, FX metadata or diagnostics. Use `DebugLogEntry.capture(...)` for support-relevant failures and partial responses, with provider/source metadata and family/account-provider context where available.
- Security prices and exchange rates have no external providers since pruning phase 9A; do not reintroduce them without an explicit product decision. See [phase 9](docs/migration/pruning-phase-9.md).
- For feature rollout, follow [preview-feature gating](docs/llm-guides/gating-a-preview-feature.md); for goals, read the [Goals guide](docs/llm-guides/goals.md).
