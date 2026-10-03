# Relay telemetry and surveys

Steve chose to disable telemetry and surveys on 3 October 2026. Relay does not
load PostHog, initialize Sentry or forward logs to Logtail/Skylight. Old environment
variables do not re-enable them. Flutter telemetry remains inactive even if a
legacy build provides a Sentry DSN.

The preview chart, expansion, zoom, transaction navigation and local graph
comparison remain available. Feedback controls, dialogs and SDK bootstrap have
been removed. Operational/support diagnostics remain local through Rails logs
and `DebugLogEntry`; disabling telemetry does not suppress financial errors.

The previous survey implementation notes are archived under
`docs/archive/sure/feedback/`. They describe prior behavior, not a configuration
path to enable collection in Relay. Unused monitoring dependencies and inert
error hooks can be removed during the later cleanup phase without blocking the
initial migration.
