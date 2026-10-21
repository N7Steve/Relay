# MCP de Relay: cierre de código y verificación de despliegue

La cobertura de código/API/MCP y la verificación de una instalación son resultados
distintos. Las pruebas locales no certifican el TLS, proxy, clientes configurados
o exposición de red de TrueNAS. Esta entrega prepara el código y el procedimiento;
no publica cambios, aplica migraciones a la instalación ni abre puertos.

## Evidencia de conformidad

El [manifiesto](../research/relay-api-mcp-coverage.yml) relaciona **44 casos de uso**
del inventario original con herramientas, pruebas y límites de presencia humana,
presentación o exclusión. Hay **244 herramientas**, cada una con ruta fija API,
esquema de entrada cerrado y resultado estructurado. Las formas de autoridad no
se sustituyen por un simple scope read_write.

`RAILS_ENV=test bundle exec ruby bin/mcp-parity-audit` comprueba que ningún caso
de uso o herramienta quede sin disposición, que existan operaciones y rutas
exactas, schemas OpenAPI reutilizables, autenticación API-key documental y
archivos de evidencia. Es una auditoría estática complementaria a Minitest; no
demuestra por sí misma comportamiento ni certifica un servidor público.

La suite de comportamiento cubre API/MCP compartidos, scopes, familias, cuentas
privadas, roles, preview, estados, signos/FX/precios, reintentos, permisos cambiantes,
archivos y recuperación. El cliente oficial se prueba por HTTP real en el servidor
temporal de Capybara con OAuth. La migración aditiva de audiencia/PKCE/operaciones
se verifica sobre el esquema histórico aislado, no sobre los datos del usuario.

Verificación del 21 de octubre de 2026: suite completa con **5.634 pruebas,
25.756 aserciones, cero fallos y errores, 38 omisiones existentes**; cliente
oficial y probe local con **1 prueba, 6 aserciones, cero fallos, errores u omisiones**.
RuboCop, ERB lint, Biome, Brakeman, generación OpenAPI, consistencia API e
inventario pasan. El [roadmap](../research/relay-api-mcp-roadmap.md) conserva
los recuentos y límites de cada entrega.

| Cliente o contrato | Evidencia y límite |
| --- | --- |
| SDK oficial TypeScript 1.32.1, Streamable HTTP 2025-11-25 | Catálogo paginado, validación de salida, lecturas, escrituras concurrentes/idempotentes, flujos de dominio y archivos |
| Contrato 2026-07-28 | Integración independiente de metadatos/cabeceras, server/discover y denegaciones; no se atribuye esa versión al SDK anterior |
| Otros clientes y aplicaciones | No certificados por esta entrega; verificar discovery, resource/PKCE, scopes y transporte del cliente concreto |

No se anuncian sampling, prompts, recursos, sesiones, ejecución arbitraria o una
cancelación RPC que deshaga escrituras. Los jobs tienen sus operaciones de consulta
y cancelación/recovery nativas.

El cuerpo de petición MCP JSON y cada resultado de dominio se limitan a 256 KiB.
El envoltorio MCP conserva structuredContent y texto JSON para compatibilidad;
su tamaño HTTP incluye ambas representaciones. Una escritura cuyo resultado de
dominio excede ese límite se revierte **antes de confirmar el ledger o el dominio**.
Una lectura demasiado grande pide reducir período/página. Los bytes originales
usan el canal autenticado de hasta 100 MiB y los límites menores de cada dominio.

## Preparación y conexión

1. Confirmar y publicar el código revisado mediante el flujo del repositorio.
2. Hacer el backup de servidor previsto en el procedimiento de instalación y
   aplicar las migraciones mediante el despliegue autorizado. La migración
   `20261021120000` añade audiencia, columnas PKCE y ledger; no se ejecuta aquí.
3. Configurar la URL pública HTTPS exacta terminada en `/mcp` y registrar el
   cliente con redirecciones exactas, scopes mínimos y PKCE S256 para clientes
   públicos. Añadir su UID a la allowlist. Usar el [contrato de configuración](mcp.md).
4. Pasar las variables coherentes a web y worker. La lista de clientes y la URL
   de recurso no se aceptan desde un payload del asistente.
5. Empezar con credencial read y comprobar contexto/cuentas. Autorizar read_write
   únicamente para las operaciones que se quieran delegar. El cliente abre los
   handoffs humanos; no tramita MFA, passkeys o consentimiento en nombre de la persona.

## Proxy, TLS y prueba de la instalación

El proxy debe conservar host/esquema públicos y las cabeceras `Authorization`,
`Accept`, `Content-Type`, `Origin`, `MCP-Protocol-Version`, `Mcp-Method` y
`Mcp-Name`; debe preservar `WWW-Authenticate`, `Retry-After` y respuestas privadas
sin caché. Mantener accesibles discovery/OAuth y `/mcp`, más `/mcp/files` y su
descarga cuando se utilicen originales. La administración web conserva su login.
No sustituir OAuth por una excepción pública del proxy.

La transferencia multipart requiere un límite de proxy compatible con el máximo
del canal, además del overhead multipart. Comprobar timeouts con las consultas
que realmente se usarán; los metadatos/handshake pequeños no representan un
informe histórico completo. Este transporte síncrono devuelve JSON; no depende
de mantener un stream SSE o sesión abierta.

`ruby bin/mcp-deployment-check https://relay.example/mcp` realiza pruebas de lectura
de discovery, issuer, PKCE, challenge anónimo y Origin. Valida certificado y hostname
TLS, no sigue redirects y no ejecuta herramientas. Se puede proporcionar una
credencial por `MCP_CHECK_TOKEN` para añadir un handshake autenticado; el script
no imprime esa credencial. No pasar secretos como argumento del comando.

El probe falla ante URLs públicas HTTP, metadatos inconsistentes, pérdida del
challenge o bloqueo/reescritura de rutas por el proxy. HTTP solo se admite para
loopback en la prueba aislada, cuyo resultado dice expresamente que no certifica
TLS desplegado. No hay opción para deshabilitar verificación de certificados.

Después de la comprobación de infraestructura, conectar el cliente real desde
su red habitual, completar consentimiento y comprobar lectura, revocación,
reintentos y una operación sintética autorizada. Anotar host, versión de cliente,
fecha y resultados. Esa evidencia queda pendiente del despliegue autorizado de
esta versión; no se sustituye por la prueba local.

Destino indicado por Steve: `https://relay.n7core.com/mcp`. El 21 de octubre de
2026, una consulta HEAD desde Windows con validación TLS devuelve HTTP 404,
coherente con que esta versión aún no está desplegada. El probe desde Docker
falla antes de conectar por resolución DNS. El dominio responde por HTTPS desde
Windows, pero siguen pendientes discovery, OAuth, cabeceras y comportamiento MCP
del proxy con la nueva versión. No se han cambiado configuración ni datos del host.

## Revocación, observación y recuperación

Retirar un UID de la allowlist bloquea ese cliente MCP; revocar claves/grants
usa su mecanismo propio. Deshabilitar MCP bloquea las rutas MCP y discovery sin
habilitar o deshabilitar banco/Drive/logos. Los trabajos delegados revisan de nuevo
credencial y permisos antes de ejecutarse. La configuración de recurrencias Drive
es una autorización nativa persistente del usuario: pausarla/borrarla o desconectar
Drive detiene esa recurrencia; revocar una clave API no borra programaciones creadas.

Usar estados de operación, Sync, import/session, export y Drive run para distinguir
escritura confirmada de recálculo/proceso pendiente. Los fallos relevantes y cambios
de acceso se auditan en DebugLogEntry sin copiar secretos a respuestas. No se
interpreta una petición RPC cancelada o un timeout del cliente como rollback.

Para retirar la funcionalidad, deshabilitar MCP y sus clientes, revisar jobs y
recurrencias y volver a una versión compatible del código según el runbook del host.
Conservar las columnas aditivas y el ledger durante el rollback: borrarlos puede
romper OAuth o permitir duplicados al reintentar. No hacer una migración down ni
restaurar un backup real automáticamente. El backup familiar y el de servidor
son procedimientos diferentes.
