# Proxy de salida opcional

El chart heredado conserva el forward proxy Pipelock, sus healthchecks y recibos.
`pipelock.example.yaml` sigue disponible como configuración genérica para un
proxy elegido por el operador. La fase 6 retira el ejemplo Compose IA y sus
servicios Ollama/Open WebUI; no elimina servicios ni volúmenes de instalaciones.

El proxy cooperativo no sustituye las puertas de capacidad de Relay ni impone
una política de red del host. MCP y los transportes de asistente están retirados;
sus valores históricos no exponen endpoints ni requieren activar un proxy.

Ver [fase 6](../migration/pruning-phase-6.md).
