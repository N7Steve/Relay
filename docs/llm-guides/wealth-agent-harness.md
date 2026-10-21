# Acceso financiero externo y nuevo MCP de Relay

MCP y el transporte del asistente externo se retiraron en fase 5. La documentación
anterior del harness pertenece a ese recorrido y se conserva como
[referencia archivada](../archive/sure/llm-guides/wealth-agent-harness.md).

La IA integrada y su catálogo se retiraron después, en fase 6; Bills también se
retiró y la fase 10 eliminó su persistencia. No existe un registro activo
`Assistant.function_classes` ni un transporte MCP que pueda activarse con las
variables antiguas. Los originales/documentos del producto soportado permanecen;
las conversaciones antiguas no forman parte de su persistencia actual.

El 21 de octubre de 2026 Steve autorizó las fases 0–1 para preparar una API
completa y un MCP propio. El [roadmap](../research/relay-api-mcp-roadmap.md) registra
el estado, las pruebas y lo pendiente. El [inventario de capacidades y contrato
de acceso](../research/relay-api-capability-matrix.md) y su
[superficie regenerable](../research/relay-api-surface.json) sustituyen al antiguo
catálogo como referencia de trabajo. El transporte nuevo pertenece a la fase 2;
esta decisión no recupera chat integrado, proveedores IA ni funciones retiradas.

El [wealth blueprint](wealth-blueprint.md) sigue siendo arquitectura de referencia
para un sistema externo separado; no prescribe operaciones en este repositorio.
