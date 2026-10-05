# Sure archive

These files preserve the fork's history and inherited release machinery. They
are references, not current Relay operating instructions. The current plan is
[RELAY_MIGRATION.md](../../../RELAY_MIGRATION.md); use the
[development guides](../../llm-guides/README.md) for supported local commands.

- `informe_scheduled_payments.md`: May 2026 implementation report. Agenda has
  evolved since then; current behavior is described in
  [the preservation map](../../../FORK_CUSTOMIZATIONS.md).
- `rollback-instructions.md`: an old rollback recipe for specific UI changes.
  It is not a rollback plan for Relay or its current database.
- `workflows/`: the 12 inherited image/chart/client release, deployment, mirror,
  impact report, documentation publishing and tag-triggered LLM evaluation
  workflows. Stored outside `.github/workflows`, they cannot run in Relay.
  Their original paths and contents remain available in Git history.

The workflow files retain their original relative references as historical
evidence. Restoring them requires defining Relay versions, destinations,
credentials and client identities, and reviewing the complete workflow graph.
Moving one file back is not a supported release procedure.

Read-only CI remains active for Rails, JavaScript, security, Pipelock secret
scanning and Flutter. The Helm chart (`charts/sure/`), the Pipelock forward-proxy
example and the guides for retired features were removed in pruning phase 11
and are recoverable from Git history; see
[Relay product scope](../../product-scope.md).
`hosting/` keeps the inherited Sure guides only as historical references.
