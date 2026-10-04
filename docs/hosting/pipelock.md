# Proxy de salida opcional

La fase 5 conserva el forward proxy Pipelock para instalaciones que lo elijan.
`compose.example.ai.yml` y el chart heredado mantienen HTTPS_PROXY, healthchecks,
controles de salida y configuración de recibos. Un proxy cooperativo no sustituye
las puertas de capacidad de Relay ni impone una política de red del host.

Se retiran el listener, puerto e ingress del reverse proxy MCP y el perfil
OpenClaw. No se reconfigura una instalación real ni se eliminan volúmenes existentes.
Las opciones MCP antiguas del chart ya no exponen un endpoint de Relay.

Ver [registro de fase 5](../migration/pruning-phase-5.md) y
[referencia anterior archivada](../archive/sure/hosting/pipelock.md).
