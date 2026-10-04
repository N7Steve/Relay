# MCP retirado

La fase 5 retira `/mcp`, su descubrimiento OAuth, el registro dinámico `/register`
y los ajustes del asistente externo. Esas rutas ya no existen (404).
Las variables `MCP_*`, `EXTERNAL_ASSISTANT_*` y `ASSISTANT_TYPE` no activan un transporte.

Se conservan OAuth/Doorkeeper, API keys y clientes web/nativos. No se revocan tokens
ni se purgan colas o datos compartidos. Las conversaciones y documentos locales
permanecen legibles y recuperables mediante backup; los remotos sin original
local siguen señalados en el informe de recuperación.

El asistente integrado conserva sus herramientas financieras y permisos.
Los trabajos antiguos sin marca de transporte se detienen sin redirigirlos a otro
proveedor. Los nuevos trabajos del integrado incluyen una marca explícita.

Ver [registro de fase 5](../migration/pruning-phase-5.md) y
[guía anterior archivada](../archive/sure/hosting/mcp.md).
