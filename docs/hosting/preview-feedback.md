# Relay telemetry and surveys

Steve chose to disable telemetry and surveys on 3 October 2026. Relay does not
load PostHog, initialize Sentry or forward logs to Logtail/Skylight. Old environment
variables do not re-enable them. Flutter uses local diagnostics without the
Sentry SDK; legacy DSNs have no effect.

The preview chart, expansion, zoom, transaction navigation and local graph
comparison remain available. Feedback controls, dialogs and SDK bootstrap have
been removed. Operational/support diagnostics remain local through Rails logs
and `DebugLogEntry`; disabling telemetry does not suppress financial errors.

The previous survey implementation notes are archived under
`docs/archive/sure/feedback/`. They describe prior behavior, not a configuration
path to enable collection in Relay. Phase 3 removed monitoring SDKs,
initializers, remote LLM traces and evaluation tasks. Errors retain local
diagnostic records.
