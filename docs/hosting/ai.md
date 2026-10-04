# Asistente integrado de Relay

Relay conserva el asistente integrado durante la fase 5. MCP y el asistente
externo están retirados; las variables antiguas no seleccionan otro transporte.

La IA requiere `Setting.ai_features_enabled?`, consentimiento del usuario y un
proveedor configurado. Configure OpenAI o un endpoint compatible mediante
`OPENAI_ACCESS_TOKEN`, `OPENAI_URI_BASE` y `OPENAI_MODEL`, o Anthropic mediante
`ANTHROPIC_ACCESS_TOKEN`, `ANTHROPIC_BASE_URL` y `ANTHROPIC_MODEL`. El proveedor
principal se selecciona con `LLM_PROVIDER`; los ajustes locales están en Hosting.
Los endpoints compatibles locales, Ollama y los parámetros de contexto/timeout
continúan soportados. `compose.example.ai.yml` conserva el perfil `local-ai`.

Los endpoints compatibles también admiten `OPENAI_EXTRA_HEADERS`, un objeto JSON
con cabeceras adicionales. Las cabeceras estáticas se aplican a cada petición;
las que incluyan `{session_id}` se resuelven únicamente para el chat y usan su ID,
sin enviarse a los jobs de clasificación/extracción. No guardar secretos en los
ejemplos. Los límites `LLM_CONTEXT_WINDOW`, `LLM_MAX_RESPONSE_TOKENS`,
`LLM_MAX_ITEMS_PER_CALL`, `OPENAI_REQUEST_TIMEOUT`, `AI_RESPONSE_TIMEOUT` y
`ASSISTANT_MAX_TOOL_CALL_ITERATIONS` siguen controlando presupuesto y latencia.
La configuración de embeddings `EMBEDDING_PROVIDER`, `EMBEDDING_URI_BASE`,
`EMBEDDING_MODEL`, `EMBEDDING_DIMENSIONS` y `EMBEDDING_ACCESS_TOKEN` se conserva;
los originales locales se recuperan por backup y los índices no son portables.

Las herramientas del chat integrado mantienen el aislamiento familiar, permisos
de cuentas y gates preview. La clasificación, extracción documental, embeddings,
insights y reglas IA se conservan hasta la selección específica de fase 6.

Las conversaciones y documentos históricos se conservan sin cambiar IDs, contenido,
modelos registrados ni bytes originales. No se reconstruyen índices remotos
como parte de esta fase ni se cambian automáticamente las preferencias históricas.
Los nuevos mensajes usan el integrado; los trabajos antiguos sin marca de transporte se detienen
con un error local, sin enviarse a un proveedor distinto ni borrar su contenido.

Ver [registro de fase 5](../migration/pruning-phase-5.md),
[backups](../llm-guides/backups.md) y
[referencia anterior archivada](../archive/sure/hosting/ai.md).
