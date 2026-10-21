# Relay MCP y operaciones cotidianas

Preparado en fases 2–3 del roadmap. Comparte `Api::DailyOperations`, permisos
`Api::Access` y operaciones nativas con la API; no llama por HTTP a Relay ni
recupera el asistente integrado o proveedores retirados.

**Escrituras pendientes:** todas las escrituras MCP se guardan como propuestas,
sin modificar el dominio hasta aprobarlas en **Ajustes → Cambios pendientes**.
El MCP no puede aprobarlas. Ver [contrato de propuestas y aprobación](mcp-pending-changes.md).

## Instrucciones operativas de esta instalación

Las [instrucciones MCP](../../config/mcp/instructions.md) contienen el flujo
personal aprobado de normalización y conciliación: exclusión de Agenda,
compras ambiguas pendientes de describir, cobros de María, devoluciones,
transferencias y comprobación del saldo por cuenta. Son reglas de esta
instalación y se entregan a todos sus usuarios MCP autenticados; no contienen
extractos, saldos ni identificadores bancarios.

`initialize` las entrega en `instructions`. Para ambos protocolos, la herramienta
`get_context` también las devuelve en `operating_instructions`; su descripción
MCP indica consultarlas antes de preparar cambios. Esto cubre los clientes
`2026-07-28`, que no usan la inicialización clásica. La API REST conserva su
contexto original y su catálogo compartido, sin estas instrucciones personales.

Son instrucciones para el agente, no validaciones financieras nuevas del
servidor ni una conciliación ya ejecutada. Se mantienen los permisos, las
validaciones nativas y la aprobación web obligatoria. Después de desplegar esta
versión, reconectar el cliente MCP y consultar `get_context` para obtenerlas.

## Activación y autenticación

Desactivado por defecto. Variables de instancia:

```env
RELAY_MCP_ENABLED=true
RELAY_MCP_URL=https://relay.example/mcp
RELAY_MCP_CLIENT_IDS=uid-del-cliente-registrado
RELAY_MCP_API_KEYS_ENABLED=false
```

La URL es la dirección pública canónica, sin barra final, del endpoint `/mcp`.
Los Compose de ejemplo/local pasan estas variables al entorno compartido de
web/worker. En la instalación TrueNAS de carpeta se añaden al `config/relay.env`
persistente, que esos procesos ya cargan. Esta entrega no modifica esa instalación.
Registrar previamente aplicaciones Doorkeeper desde su interfaz administrativa,
con redirecciones exactas y los scopes `read` o `read_write`. Incluir sus UID
separados por comas en la lista de clientes permitidos. Los clientes públicos
usan authorization code con PKCE S256. No hay registro dinámico ni recuperación
de metadatos desde URLs arbitrarias del cliente.

El descubrimiento de recurso está en
`/.well-known/oauth-protected-resource/mcp`; el de autorización, en
`/.well-known/oauth-authorization-server`. La autorización usa
`/oauth/authorize`, `/oauth/token` y `/oauth/revoke`. Enviar
`resource=https://relay.example/mcp` tanto al autorizar como al canjear o renovar.
El consentimiento conserva el recurso. Grant y token almacenan su audiencia;
los tokens corrientes de la API no sirven para MCP y los de MCP no sirven para
la API REST. Desactivar el cliente en la lista bloquea inmediatamente su acceso.

El modo opcional `X-Api-Key` requiere `RELAY_MCP_API_KEYS_ENABLED=true`. Usa
claves individuales de usuario, sus scopes, caducidad, revocación y limitación
existentes; es una alternativa explícita para clientes propios. No hay token
global asociado a un correo. Habilitar MCP no habilita conexiones salientes.

### App de escritorio de ChatGPT con API key y Cloudflare Access

Para un MCP HTTP conectado localmente desde Ajustes → MCP servers, la app de
escritorio admite cabeceras estáticas y comparte `~/.codex/config.toml` con Codex.
Esta configuración no se aplica al conector alojado de ChatGPT web, cuya
autenticación y transporte se configuran por separado.

En la instalación de Relay, habilitar estas variables mediante su configuración
persistente (o `environment` del YAML de despliegue):

```env
RELAY_MCP_ENABLED=true
RELAY_MCP_URL=https://relay.n7core.com/mcp
RELAY_MCP_API_KEYS_ENABLED=true
```

Crear una API key individual en `/settings/api_keys`, por ejemplo «ChatGPT MCP»,
con scope `read` o `read_write` según las operaciones deseadas. Es un token
estático ligado al usuario, con sus permisos, caducidad y revocación existentes;
no hace falta introducir un secreto global en el YAML ni registrar un cliente
OAuth para esta modalidad. `RELAY_MCP_CLIENT_IDS` se utiliza para OAuth.

Crear también un Service Token de Cloudflare Access y autorizarlo mediante una
política Service Auth que cubra las rutas necesarias. El token de Cloudflare
permite atravesar Access; la API key de Relay sigue autorizando cada operación.
El cliente envía ambas credenciales, sin sustituir una por otra.

Ejemplo de configuración **local**, con valores que se deben sustituir:

```toml
[mcp_servers.relay]
url = "https://relay.n7core.com/mcp"

[mcp_servers.relay.http_headers]
"X-Api-Key" = "API_KEY_DEL_USUARIO_EN_RELAY"
"CF-Access-Client-Id" = "CLIENT_ID_DEL_SERVICE_TOKEN"
"CF-Access-Client-Secret" = "CLIENT_SECRET_DEL_SERVICE_TOKEN"
```

Como alternativa a guardar valores en ese archivo, usar `env_http_headers`
con nombres de variables de entorno disponibles para el proceso de la app.
No enviar `Authorization: Bearer` con la API key: ese encabezado selecciona
la validación OAuth de Relay. Guardar los secretos en la configuración local
del cliente; no añadirlos al repositorio ni pegarlos en el chat. Tras configurar,
reiniciar la conexión y probar primero `get_context`. La compatibilidad descrita
en la documentación no sustituye una prueba con la app y el despliegue reales.

Fuentes: [MCP en la app de escritorio](https://learn.chatgpt.com/docs/extend/mcp?surface=app),
[referencia de cabeceras](https://learn.chatgpt.com/docs/config-file/config-reference) y
[Service Tokens de Cloudflare](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/).

La migración `20261021120000` prepara audiencia, PKCE y registro idempotente de
operaciones. Debe aplicarse por el procedimiento de despliegue antes de utilizar
este código con una base existente. No se ha ejecutado contra la instalación del
usuario ni se ha desplegado TrueNAS.

## Transporte

POST `/mcp`, JSON-RPC 2.0, una petición por mensaje. `Content-Type:
application/json`, `Accept: application/json, text/event-stream`. Respuestas JSON,
sin sesiones de protocolo, stream persistente o muestreo. GET y DELETE responden
405. Origin, cuando esté presente, debe coincidir exactamente con el origen
canónico configurado. No se deriva del Host que envíe el cliente.

- `2025-11-25`: `initialize`, `notifications/initialized`, `ping`, `tools/list`
  y `tools/call`. Tras initialize, enviar `MCP-Protocol-Version` en cada petición.
- `2026-07-28`: sin handshake; `server/discover`, `ping`, `tools/list` y
  `tools/call`. Enviar `MCP-Protocol-Version`, `Mcp-Method` y `Mcp-Name` para
  ejecución. `params._meta` lleva `io.modelcontextprotocol/protocolVersion`,
  `io.modelcontextprotocol/clientInfo` y `io.modelcontextprotocol/clientCapabilities`.
  Se comprueba correspondencia entre cabeceras y cuerpo.

Los errores de protocolo son JSON-RPC; las denegaciones/validaciones de una
herramienta son resultados con `isError: true`. `structuredContent` contiene el
resultado y `content` su representación JSON. Los esquemas rechazan campos
desconocidos, fechas inválidas, decimales no finitos y lotes de más de 100.
El cuerpo de petición MCP JSON y cada resultado de dominio están acotados a
256 KiB (el envoltorio MCP incluye sus representaciones estructurada/textual).
Una escritura que exceda el límite de resultado se revierte antes de confirmar.
Una lectura demasiado grande devuelve un error explícito para reducir período/página.

El catálogo se pagina mediante `nextCursor`/`cursor` (25 herramientas); los datos
mediante `page`, `per_page` (1–100), `total_count` y `next_page`. El catálogo omite
escrituras para credenciales de lectura, pero cada ejecución vuelve a comprobar
la autoridad efectiva. Texto financiero se devuelve como datos, nunca se ejecuta.

## Operaciones compartidas con API

Cada herramienta de dominio tiene una ruta fija `POST /api/v1/actions/<nombre>` con cuerpo
`{"arguments": {...}}`. Son extensiones compatibles de v1; las rutas anteriores
conservan su contrato (incluidos los imports CSV de categorías y comercios).
OpenAPI enumera cada ruta y esquema; no hay endpoint de ejecución arbitraria de
modelos, SQL o métodos.

| Grupo | Herramientas |
| --- | --- |
| Contexto y consulta | `get_context`, `list_accounts`, `get_account`, `search_transactions`, `get_cash_flow`, `get_operation`, `get_account_sync` |
| Cuentas | `create_account`, `update_account`, `set_account_status`, `set_default_account` |
| Movimientos | `create_transaction`, `update_transaction`, `delete_transaction`, `duplicate_transaction`, `bulk_update_transactions`, `preview_bulk_delete_transactions`, `bulk_delete_transactions`, `preview_categorization` |
| División y protección | `split_transaction`, `unsplit_transaction`, `protect_transaction`, `unlock_transaction` |
| Duplicados y conversión | `merge_duplicate`, `dismiss_duplicate`, `convert_transaction_to_trade` |
| Transferencias | `create_transfer`, `update_transfer`, `match_transfer`, `unlink_transfer`, `delete_transfer` |
| Organización | `list/create/update/delete` de categorías, comercios y etiquetas; `merge_categories`, `merge_merchants`, `merge_tags`, `replace_category`, `replace_tag` |
| Informes y planificación | 11 consultas financieras y 39 operaciones de presupuestos, Agenda y Goals; [contrato y límites](reporting-planning.md) |
| Inversión y procesos | 24 operaciones de inversión y 54 de reglas, importaciones, archivos y backups; [contrato y límites](investment-processes.md) |
| Integraciones y administración | 60 operaciones de perfil, familia, seguridad, banco, Drive, acceso externo y trabajos; [autoridad y presencia humana](integrations-administration.md) |
| Cierre de cobertura | 8 consultas/operaciones adicionales de contexto, movimientos, transferencias, valores locales e insights; [auditoría y release](mcp-release.md) |

El catálogo de dominio contiene 244 herramientas. El transporte MCP añade
`get_pending_changes` para seguimiento, sin ruta REST de aprobación.
Los informes reutilizan los
motores financieros de la web; la planificación conserva propiedad, permisos,
máquinas de estado y gate de preview de Goals.
Los originales se transfieren por un canal autenticado aparte; el catálogo
devuelve referencias y metadatos. La conciliación, las importaciones y la
restauración usan los lectores y motores nativos.

Cantidades como strings decimales, con signo de libro: positivo = salida,
negativo = entrada. Las divisiones suman el importe firmado del padre. Los
importes de creación de transferencias son positivos; moneda, naturaleza y
conversión pertenecen al motor nativo. La edición de importe usa FX local fechado
y falla si falta; no inventa paridad. Archivo y activación son valores deseados,
no toggles. Omitir/account_id null en `set_default_account` limpia la preferencia.

Toda escritura exige `idempotency_key` (1–128 caracteres), única para el usuario.
En MCP, los reintentos idénticos devuelven la misma propuesta; cambiar el payload
o la credencial con esa clave se rechaza. La ejecución solo empieza tras aprobación
web y tiene un namespace de idempotencia propio. En REST, resultado y escritura
siguen guardándose juntos y los reintentos devuelven el resultado original.
Los permisos se revisan al ejecutar; operaciones sobre un registro eliminado pueden
fallar. `get_operation` devuelve únicamente finalización de escritura REST,
sin recuperar datos históricos de cuentas cuyo acceso haya cambiado.
`get_account_sync` consulta por separado la recalculación asíncrona: completar
la escritura no implica que haya terminado el job.

Las escrituras de cuenta requieren owner/full_control; una compartición
read_write permite anotaciones. Ambas cuentas y las comisiones se comprueban en
transferencias. La organización global requiere administrador con acceso a todas
las cuentas, porque sustituciones/fusiones afectan también movimientos existentes.
Las referencias siempre pertenecen a la familia y al conjunto disponible del actor.

Dividir reemplaza atómicamente una división anterior; revertir recupera el padre.
Los hijos no admiten edición/borrado directo ni cambios por lote. Desbloquear
limpia protecciones de importación/usuario/campos, conservando la protección
estructural de las divisiones. `unlink_transfer` conserva los movimientos;
`delete_transfer` elimina ambos. Rechazar registra `RejectedTransfer` y evita
el emparejamiento automático posterior, conforme al modelo nativo.

Los lotes de borrado requieren primero una previsualización. La política delegada
de esta fase permite hasta 100 movimientos efectivos (incluidos hijos y
comisiones), con permiso de escritura en todas sus cuentas. El servidor firma
una previsualización ligada al actor, selección y versiones de los registros,
válida diez minutos; ejecutar vuelve a validar permisos y bloquea/comprueba los
registros. Una modificación posterior invalida la previsualización. El token
demuestra la previsualización del servidor, no una aprobación humana adicional.
Esta delegación de operativa cotidiana no se aplica a restauraciones, borrados
familiares ni cambios de seguridad, que siguen fuera de esta fase.
La sugerencia de categorías usa únicamente el modelo Bayes local y exige
visibilidad completa para no inferir actividad de cuentas ajenas; no modifica
movimientos. La aplicación de cambios usa el lote explícito de anotaciones.

## Diseño y verificación

Se evaluó el [SDK Ruby oficial](https://github.com/modelcontextprotocol/ruby-sdk).
Se eligió un adaptador limitado a descubrimiento y herramientas síncronas: el
producto no necesita sesiones, sampling, prompts, recursos o callbacks. Esto
evita una dependencia de ejecución y conserva autenticación/rate limiting de
Rails. No se afirma conformidad con capacidades que no se anuncian.
Las versiones se prueban con contratos separados según la
[especificación de transporte](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http).

Minitest cubre protocolo, permisos, aislamiento, validación, reintentos, signos,
divisiones, cuentas y organización, además de OAuth/PKCE/recurso/revocación.
`test/manual/mcp_client_smoke.rb` y `.mjs` prueban un cliente oficial TypeScript
por HTTP real contra el servidor temporal de Capybara y la base Docker aislada.
El SDK se instala solo en `/tmp/relay-mcp-client` del contenedor de verificación;
no añade dependencias al producto. El resultado y versión probada se registran
en el roadmap al cerrar la verificación.
