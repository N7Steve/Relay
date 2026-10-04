# Poda fase 5 — MCP y asistente externo

Seleccionada por Steve el 4 de octubre de 2026. Base `92ee241a1`, presente en
`main` y `origin/main` al empezar. Árbol limpio, fetch y fast-forward sin cambios.
La fase 4 ya estaba publicada en esa base. Sin ramas, worktrees, PR, commit/push
ni operaciones sobre TrueNAS durante esta entrega.

## Resultado y alcance

- Retirados `/mcp`, `/.well-known/oauth-protected-resource`,
  `/.well-known/oauth-authorization-server`, `/register`, ajustes MCP/revocación
  de tokens desde esa pantalla y desconexión del asistente externo. Las rutas
  ausentes responden 404; credenciales o variables antiguas no las reactivan.
- Retirados `Assistant::External`, cliente HTTP/SSE y catálogo de agentes, selector
  familiar, descubrimiento síncrono, controles y traducciones de ese transporte.
- Retirados perfil OpenClaw de Compose, listener/puerto/reverse proxy e ingress
  MCP del chart. Se conservan Ollama/Open WebUI, forward proxy Pipelock y sus
  controles de salida, healthchecks y recibos. No se eliminan volúmenes reales.
- Chat nuevo siempre utiliza `Assistant::Builtin`. `ASSISTANT_TYPE`, `MCP_*` y
  `EXTERNAL_ASSISTANT_*` no habilitan ni seleccionan un transporte. La disponibilidad
  sigue requiriendo la puerta IA, consentimiento y un proveedor integrado configurado.

Se conservan OAuth/Doorkeeper, aplicaciones, grants, tokens, API keys, scopes,
autenticación y clientes web/nativos. El default de scope para aplicaciones
exclusivamente read_write sigue en el controlador de autorizaciones con nombre
neutral. La marca nueva para jobs es interna, sin parámetros o respuestas
públicos nuevos. Se repara el reintento API v1 para reutilizar la pregunta
original y crear una respuesta pendiente válida; conserva autenticación, scopes
y respuesta 202 con message_id. OpenAPI actualiza únicamente su resumen.

El registro de funciones es compartido con el integrado: herramientas de
finanzas, Statement Vault y Bills siguen disponibles con aislamiento familiar,
permisos de cuentas y gates preview. El valor de procedencia `mcp` que conserva
CreateTransaction forma parte del contrato histórico de idempotencia; no activa
un endpoint y no se renombra, evitando duplicados por cambiar esa identidad.
IA, clasificación, PDFs, embeddings, prompts y consumo local se mantienen para
la selección opcional de fase 6. Drive, Brandfetch, Agenda, informes y finanzas
no cambian.

## Historia, credenciales, trabajos y recuperación

No hay migraciones, eliminación de tablas, filas o archivos, ni cambio de IDs,
contenido, modelos históricos o nombres STI. Family.assistant_type sigue aceptando
valores históricos externos para restauración, pero no participa en el routing.
Los ajustes external_assistant_* cifrados permanecen como persistencia histórica
sin consumidor de transporte ni formulario de escritura.

Las conversaciones externas y sus herramientas/resultados siguen legibles y
exportables localmente. No se reconstruye un índice remoto ni se inventan bytes
que el origen nunca guardó; esos documentos siguen señalados por el informe de
backup. El backup familiar conserva su contrato y excluye credenciales operativas.

No hay un job exclusivo del externo: ambos usaban AssistantResponseJob y la cola
high_priority. Los mensajes nuevos se encolan con backend builtin explícito.
Un trabajo antiguo sin esa marca se detiene con un error local y conserva
contenido; la respuesta pendiente pasa a failed sin borrarse. No es posible
identificar de forma fiable su transporte tras cambiar preferencias/variables,
por lo que también se detienen trabajos builtin anteriores sin marca. El usuario
puede reintentarlos explícitamente con el integrado. No se redirige automáticamente
ningún trabajo antiguo a otro proveedor. La puerta IA apagada bloquea la ejecución;
ninguna variable antigua participa en el dispatch ni en la resolución de trabajos.

No se purgan colas/caches compartidos ni se revocan tokens. No existe un identificador
fiable que permita separar todos los clientes MCP de otros clientes OAuth; nombres
de aplicaciones y la ausencia de mobile_device_id no justifican revocar su acceso.
El acceso a MCP termina por retirar la ruta, preservando la API autorizada.

## Validación

Fase implementada y validada en Docker Linux aislado, pendiente de publicación
autorizada. Rails completo ejecutado sobre una imagen reconstruida del árbol
actual, con la paralelización existente limitada a cuatro procesos.

- Rails completo: 10.663 pruebas, 45.476 aserciones, cero fallos y errores,
  45 omisiones preexistentes. Duración: 218,74 segundos. El reintento API deja
  de estar omitido; no se añaden omisiones.

- Focalizadas: 232 pruebas, 993 aserciones, cero fallos y errores, una omisión
  preexistente. Jobs, rutas, chat y reintento API: 65 pruebas y 268 aserciones,
  sin fallos, errores u omisiones. Comprobación posterior del estado reintentable:
  26 pruebas y 70 aserciones, todas correctas. Backup de conversaciones:
  6 pruebas y 63 aserciones, incluyendo el placeholder vacío detenido.
- OpenAI retenido: 51 pruebas y 193 aserciones, sin fallos, errores u omisiones.
- Navegador final: 20 pruebas, 92 aserciones, cero fallos, errores u omisiones.
  Captura de Hosting revisada, sin controles ni descripción MCP.
- Rswag documental: 434 ejemplos, cero fallos y 89 pendientes documentales
  existentes. La cobertura del reintento usa X-Api-Key y rechaza claves read-only.
- RuboCop: 2889 archivos sin infracciones; ERB, Biome y Brakeman correctos,
  cero avisos activos de seguridad y las mismas exclusiones existentes.
  Los últimos cambios de modelo y pruebas también pasan RuboCop focalizado.
- Helm 3.17.3 temporal, descargado con checksum SHA-256 verificado. Dependencias
  y render sobre copia aislada en tmp; lint correcto. Valores MCP/externos
  heredados no generan listener, puerto, env de transporte ni ingress MCP.
- Compose AI válido con perfil local-ai; sin OpenClaw ni endpoint de callback.
- Snapshot sintético de fase 0 → restore → export → restore: cada restauración
  verifica 21 registros y un original, valores financieros, relaciones y bytes
  coinciden; rollback comprobado. El backup de conversaciones también recorre
  dos restauraciones con familia externa y modelo histórico OpenClaw.
- Imagen y eager loading offline de producción correctos, incluso con credenciales
  y overrides antiguos: builtin/OAuth conservados y clases/rutas externas ausentes.

La primera tanda detectó una referencia a un partial retirado y un supuesto de
controller OAuth en la prueba nueva; se corrigieron. La primera suite completa
identificó una comprobación documental OpenAI: se repuso su configuración vigente.
El navegador detectó que conservar una respuesta failed ocultaba el aviso de
error; se corrigió el cálculo del estado reintentable sin eliminar su historial.
Esas ejecuciones no constituyen evidencia de cierre. Se eliminó la omisión antigua
del reintento API al reparar su implementación. No se añadieron omisiones ni
se debilitaron controles de acceso. Instalación y backups privados no inspeccionados;
recuperación sintética. Clientes nativos sin cambios de código en esta fase.
Una repetición utilizó una copia de pruebas con la guía OpenAI obsoleta; se
descartó como evidencia y se reconstruyó la imagen completa antes del cierre.
Los servicios de pruebas de esta fase se detienen conservando volúmenes y logs.

Evidencia local no versionada en tmp: pruning-phase-5-focused.log,
pruning-phase-5-retry-contracts.log, pruning-phase-5-history-tests.log,
pruning-phase-5-provider-contracts.log, pruning-phase-5-chat-release.log,
pruning-phase-5-suite-parallel.log, pruning-phase-5-system-verified.log,
docker-test-results/phase5-hosting.png, pruning-phase-5-checks-verified.log,
pruning-phase-5-chat-lint.log, pruning-phase-5-final-lint.log,
pruning-phase-5-openapi-final.log,
pruning-phase-5-helm-lint.log,
pruning-phase-5-helm-render.yml, phase5-compose.json, pruning-phase-5-recovery.log,
phase5-current.json, pruning-phase-5-image-complete.log y pruning-phase-5-boot-complete.log.

## Despliegue y reversión

Actualizar web/worker juntos, conservar backup de instalación y las mismas
claves de cifrado/SECRET_KEY_BASE. Retirar variables y exposición de red MCP/externo
de la configuración operativa al desplegar; no hacerlo automáticamente aquí.
Una petición MCP o de registro dinámico deja de funcionar; la API y los clientes
siguen utilizando sus autenticaciones y scopes propios.

Reversión de código/configuración, con esquema y datos compatibles. No requiere
reconectar tokens porque no se revocaron. Volver al código anterior con credenciales
externas podría reactivar ese transporte; no restaurar automáticamente variables,
listeners o jobs. Los trabajos detenidos ya no se reencolan al revertir.

Tras publicación autorizada se puede detener aquí con Relay utilizable. La siguiente
selección es fase 6, retirada opcional de IA integrada; no está incluida en esta entrega.
