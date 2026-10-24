# Relay MCP: OAuth con Authentik

## Arquitectura

ChatGPT → Cloudflare Access → `/mcp` → JWT Authentik → vínculo local
`issuer + sub` → `Api::Access` → operaciones financieras nativas.

Opción adicional, desactivada por defecto. Relay recibe access tokens; ChatGPT
realiza Authorization Code + PKCE S256 y renueva directamente en Authentik con
sus credenciales estáticas. Relay no recibe ni envía Client Secret, códigos OAuth,
contraseñas o refresh tokens. No hay callback Authentik en Relay.

No se utiliza el flujo web `OidcIdentity` (que tiene JIT y mappings de roles).
No se crean usuarios ni se sincronizan roles/grupos. OAuth Doorkeeper, sus clientes,
API keys, sesiones, REST y Android conservan su autenticación. No hay nuevo SSO web.

El verificador descarga OIDC discovery y JWKS con HTTPS, sin redirecciones ni
credenciales. Exige issuer exacto, endpoints del mismo origen, soporte anunciado
S256, Authorization Code y autenticación de cliente confidencial. Solo permite
RS256 y claves RSA de al menos 2048 bits; comprueba firma, `kid`, `typ=JWT`, `iss`,
audiencia única, `azp`, `sub`, `uid`, `scope`, `exp`, `iat` y `nbf` cuando exista.

El perfil Authentik distingue access tokens de ID tokens mediante `uid` y `azp`,
ausentes en el ID token normal. **No inyectar esos claims en ID tokens mediante
property mappings**. Es un contrato específico del emisor, no una propiedad
universal JWT; revisarlo al actualizar Authentik.

Los documentos tienen límite de 64 KiB y tiempos de descarga acotados; el token
admite hasta 16 KiB. Discovery/JWKS se cachean en memoria por proceso 10 minutos.
Un `kid` desconocido permite refrescar después de un mínimo de 30 segundos.
Un error del proveedor rechaza la autenticación, limita reintentos durante
30 segundos y no usa claves caducadas. Mantener ambas claves durante la rotación.
`DebugLogEntry` registra issuer y clase del error, nunca tokens o secretos.

## Compatibilidad y evidencia

| MODE | Audiencia admitida | Garantía |
| --- | --- | --- |
| `resource` (predeterminado) | Solo `RELAY_MCP_URL` | Requiere que el emisor vincule realmente ese recurso en autorización, canje y refresh. |
| `authentik` (explícito) | Solo `RELAY_MCP_AUTHENTIK_CLIENT_ID` | Aislamiento por cliente/proveedor; no vinculación completa RFC 8707 al recurso MCP. |

Ambos exigen `azp` igual al cliente dedicado. No hay fallback entre audiencias ni
listas con destinatarios adicionales. No reutilizar ese cliente/proveedor en Ilos,
SSO, REST, Android u otro receptor. No sobrescribir `aud` mediante mappings: eso
no demuestra vinculación RFC 8707. El modo `resource` tampoco certifica por sí solo
el comportamiento del emisor.

Investigación del 24 de octubre de 2026: la documentación vigente de
[Ilos](https://github.com/N7Steve/Ilos/blob/main/docs/MCP_OAUTH.md) describe una POC
pendiente de validación interactiva. Se consultó también su
[verificador](https://github.com/N7Steve/Ilos/blob/main/apps/api/src/mcp/oauth.ts).
La consulta pública al discovery Relay de `auth.n7core.com` no fue accesible desde
la herramienta de investigación. No se ha identificado la versión instalada ni
obtenido tokens reales. La premisa de una integración Ilos ya certificada no está
acreditada por esos documentos.

Se revisó Authentik upstream fijado a
`4aef2aa503ef8adbd588d5a43f5563d5636982ce`:
[id_token.py](https://github.com/goauthentik/authentik/blob/4aef2aa503ef8adbd588d5a43f5563d5636982ce/authentik/providers/oauth2/id_token.py)
parte de audiencia Client ID y añade `azp`, `uid`, `scope` al access token;
[authorize.py](https://github.com/goauthentik/authentik/blob/4aef2aa503ef8adbd588d5a43f5563d5636982ce/authentik/providers/oauth2/views/authorize.py)
y el [canje del código](https://github.com/goauthentik/authentik/blob/4aef2aa503ef8adbd588d5a43f5563d5636982ce/authentik/providers/oauth2/token/authorization_code.py)
no acreditan vinculación de `resource`. Es evidencia del upstream, no de la
instalación. El perfil `authentik` queda disponible como excepción explícita,
pendiente de comprobar en la versión desplegada. Referencias:
[MCP Authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization),
[RFC 8707](https://www.rfc-editor.org/rfc/rfc8707),
[RFC 9728](https://www.rfc-editor.org/rfc/rfc9728).

## Identidad y autorización Relay

`RELAY_MCP_AUTHENTIK_BINDINGS` es una lista JSON de vínculos. Cada entrada contiene
issuer exacto, `sub` estable, UUID del usuario existente y techo local `read` o
`read_write`. Duplicar `issuer + sub` invalida los vínculos. Email, nombre, grupos
y roles del JWT no otorgan permisos. Usuario desconocido, eliminado, desactivado
o sin scopes locales: autenticación rechazada, sin aprovisionamiento.

Scopes efectivos = intersección de `scope` firmado y techo local. `read_write`
incluye lectura. `openid`, `profile`, `email`, `offline_access` y scopes desconocidos
no dan permisos financieros. Solo `openid` se rechaza; token `read_write` con techo
`read` conserva únicamente lectura. Los permisos por cuenta, familia, comparticiones,
operaciones y administración son los de `Api::Access` y las operaciones nativas.
Ser admin no concede escritura sobre cuentas ajenas sin permiso nativo.

Las escrituras crean `Mcp::ChangeSet` sin cambios financieros inmediatos. La autoridad
conserva claims mínimos verificados y expiración; el identificador deriva de identidad,
usuario, cliente, modo y recurso. Nunca se guarda el JWT. La aprobación web y cada
operación posterior revalidan vínculo, usuario, familia, scopes originales, techo
actual, configuración y caducidad. Desactivar o reducir permisos impide aplicar.
Cambiar issuer, cliente, modo, recurso o usuario vinculado invalida propuestas antiguas.
Se conservan digest de revisión, referencias pendientes, idempotencia y ausencia
de aprobación MCP.

Renovar el token no prolonga la autoridad de una propuesta antigua: si venció,
rechazarla y prepararla otra vez con nuevas claves de idempotencia. Un reintento
con token/argumentos idénticos conserva la propuesta; cambiar credencial/claims
con la misma clave puede producir conflicto, como otras credenciales Relay.

Validación local significa que revocar una sesión/refresh token en Authentik no
revoca inmediatamente el JWT emitido. Usar tokens cortos, por ejemplo 10 minutos.
Para corte local inmediato, desactivar el usuario o quitar el vínculo y recargar
web **y worker** si cambió el entorno. No hay introspección remota con secretos.

## Crear proveedor y aplicación Authentik (manual)

1. Anotar la versión instalada. En Applications → Providers crear un proveedor
   **OAuth2/OpenID**, cliente **Confidential**, exclusivo de Relay MCP. Generar
   Client ID y Client Secret nuevos. Guardar el secreto solo en un registro privado
   y ChatGPT; no en Relay.
2. Crear Application, slug `relay-mcp`, y asociar el proveedor. Seleccionar issuer
   **por proveedor**, no global. Debe ser exactamente
   `https://auth.n7core.com/application/o/relay-mcp/`.
3. Elegir clave de firma RSA RS256 de al menos 2048 bits, nunca firma simétrica
   con el secreto. Elegir subject estable UUID/hash, no email; no cambiar el modo
   de subject una vez vinculado.
4. Permitir Authorization Code y Refresh Token; desactivar otros grants cuando
   la versión lo permita. Usar consentimiento explícito y una política de acceso
   restringida inicialmente al usuario autorizado. Mantener MFA y login existentes.
5. Obtener de la gestión de la conexión ChatGPT su **redirect URI exacta** y
   registrarla con coincidencia estricta. Si exige varias, registrar cada URI.
   No dejar el campo vacío, usar comodines, copiar el callback Ilos ni inventar
   un callback en Relay.
6. Añadir mappings estándar `openid` y `offline_access` para renovación. Crear
   mappings de scopes `read` y `read_write`, con descripción clara de lectura o
   lectura/escritura Relay y expresión `return {}`. Conceden el scope sin modificar
   claims. No mapear `aud`, `iss`, `sub`, `azp`, `uid`, `scope`, `iat` o `exp`.
   Opcionalmente restringir la concesión de escritura con política del proveedor,
   además del techo local obligatorio.
7. Configurar access tokens cortos y rotación refresh según la versión. Confirmar
   discovery con S256 y cliente confidencial. En el flujo real comprobar challenge
   S256 y canje con verifier, rechazando el verifier incorrecto/ausente para un
   código con challenge. El upstream revisado también admite códigos sin challenge
   y `plain`: anunciar S256 no acredita imposición universal. Para prohibirlos en
   todos los flujos, configurar y verificar una política en la versión instalada.
   Relay no puede deducir PKCE del JWT; no se atribuye esa garantía al verificador.
8. Obtener el `sub` mediante una autorización de prueba y verificar localmente su
   firma/issuer/cliente. No enviar tokens a páginas de decodificación, chats o logs.
   Buscar el UUID del usuario Relay en su administración o consulta de solo lectura
   autorizada. Revisar issuer + subject + UUID; no asociar solo por email.

Ver [documentación oficial Authentik](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/).
No modificar la aplicación/proveedor Ilos.

## Variables exactas TrueNAS

Añadir a `/mnt/AppsPool/relay/config/relay.env`, preservando todo lo existente:

```dotenv
RELAY_MCP_ENABLED=true
RELAY_MCP_URL=https://relay.n7core.com/mcp
RELAY_MCP_AUTHENTIK_ENABLED=false
RELAY_MCP_AUTHENTIK_ISSUER=https://auth.n7core.com/application/o/relay-mcp/
RELAY_MCP_AUTHENTIK_CLIENT_ID=REEMPLAZAR_CLIENT_ID_DEDICADO
RELAY_MCP_AUTHENTIK_MODE=authentik
RELAY_MCP_AUTHENTIK_BINDINGS='[{"issuer":"https://auth.n7core.com/application/o/relay-mcp/","sub":"REEMPLAZAR_SUB_VERIFICADO","user_id":"REEMPLAZAR_UUID_RELAY","scopes":["read"]}]'
```

JSON en una sola línea y entre comillas simples externas: el arranque TrueNAS
carga este archivo con `. /config/relay.env` en el shell. Esas comillas preservan
las comillas dobles del JSON. No introducir comillas simples en los valores del
ejemplo; si un subject las contiene, codificarlas como `\u0027` en el JSON.
No existe ni hace falta `RELAY_MCP_AUTHENTIK_CLIENT_SECRET`.
El MODE predeterminado es `resource`; la compatibilidad requiere `authentik`
expresamente. Conservar `RELAY_MCP_CLIENT_IDS` para Doorkeeper y
`RELAY_MCP_API_KEYS_ENABLED` para API keys. No poner el cliente Authentik en la
allowlist Doorkeeper.

Comenzar con techo `read`. Después de preparar/revisar el despliegue, activar
ENABLED y recargar web/worker mediante el procedimiento operativo autorizado.
Para ampliar permisos, usar `["read_write"]` y autorizar de nuevo en ChatGPT
solicitando ese scope. No cambiar datasets, PostgreSQL, Redis, credenciales,
volúmenes o actualizador. No se requieren migraciones. No se ha desplegado ni
modificado producción. Sigue aplicando el [runbook TrueNAS](../hosting/truenas.md).

## Discovery y conexión ChatGPT

El recurso `/.well-known/oauth-protected-resource/mcp` anuncia la URL canónica y,
cuando se activa Authentik, los issuers `[Authentik, Relay]`. Authentik va primero
para conexiones nuevas; Relay conserva clientes nativos. El discovery
`/.well-known/oauth-authorization-server` de Relay sigue describiendo Doorkeeper.
ChatGPT debe obtener el discovery OIDC del issuer Authentik, sin proxy OAuth.
Los 401 incluyen `WWW-Authenticate: Bearer resource_metadata="https://relay.n7core.com/.well-known/oauth-protected-resource/mcp"`.

1. ChatGPT web → Plugins/Apps/conexiones MCP, según versión → **Add custom MCP
   server**. URL `https://relay.n7core.com/mcp`, autenticación OAuth.
2. Introducir Client ID y Client Secret estáticos exclusivos de Relay. Obtener
   el callback mostrado para registrarlo en el proveedor antes de completar.
   No usar cabeceras Cloudflare, API key, cliente Ilos ni sustituir por DCR/CIMD.
3. Confirmar que abre `auth.n7core.com` con cliente Relay y PKCE S256. Solicitar
   `openid offline_access read` inicialmente. Si la interfaz no ofrece campo de
   scopes, revisar los realmente solicitados y concedidos: debe existir scope
   financiero. Autenticar, consentir y completar el callback de ChatGPT.
4. Instalar/seleccionar la conexión y empezar por `get_context`, `list_accounts`
   y consultas pequeñas. Esperar al vencimiento y verificar refresh real sin
   contraseña, conservando cliente, issuer, subject y scopes. Sin `offline_access`
   puede requerirse una nueva autorización.
5. Si selecciona issuer incorrecto, exige resource binding que el proveedor no
   garantiza o rechaza dos issuers, registrar incompatibilidad y detener la
   aceptación. No hacer fallback de audiencia, reescribir claims, eliminar OAuth
   ni redirigir los endpoints nativos de Relay hacia Authentik.

Fuentes oficiales: [credenciales OAuth estáticas en ChatGPT](https://developers.openai.com/api/docs/guides/custom-mcp-server)
y [flujo PKCE](https://developers.openai.com/plugins/build/auth). La prueba local
HTTP/SDK no certifica la interfaz ni el flujo interactivo de una cuenta real.

## Cloudflare Access (manual)

En Zero Trust → Access → Applications identificar rutas y aplicación exactas.
Crear/revisar política **Bypass**, selector **IP ranges**, con todos los prefijos
IPv4/IPv6 de [ChatGPT connectors](https://openai.com/chatgpt-connectors.json).
Registrar `creationTime` y revisar cambios según la [guía oficial](https://developers.openai.com/api/docs/guides/ip-addresses).
No usar rangos de agentes Codex ni `Everyone`. Comprobar precedencia y aplicaciones
solapadas. La IP identifica la red OpenAI, no al usuario: OAuth sigue obligatorio.

| Ruta | Origen de petición | Tratamiento |
| --- | --- | --- |
| Relay `/mcp` | Conector | Bypass por IP oficial; JWT/OAuth obligatorio en Rails. |
| Relay `/.well-known/oauth-protected-resource/mcp` | Conector | Mismo Bypass; metadata pública. |
| Relay `/.well-known/oauth-authorization-server` | Clientes nativos/conector | Discovery accesible cuando se utiliza issuer Relay. |
| Relay `/mcp/files` y `/mcp/files/download` | Cliente que use canales binarios | Reglas específicas solo si se usan; scopes y autorización obligatorios. |
| Authentik `/application/o/relay-mcp/.well-known/openid-configuration`, `/application/o/relay-mcp/jwks/` | Conector y servidor Relay | Sin challenge interactivo: permitir también salida de Relay o publicar solo estas rutas de metadata. |
| Authentik `/application/o/token/`, `/application/o/revoke/` | Conector | Permitir OAuth desde IP OpenAI sin login Access; Authentik autentica cliente. Rutas globales: revisar impacto sobre otros proveedores. |
| Authentik `/application/o/authorize/`, login y consentimiento | Navegador de Steve | Acceso interactivo normal; el navegador no usa IP del conector. |
| Callback exacto `chatgpt.com/...` | Navegador | Servido por ChatGPT; no crear callback Relay ni regla Cloudflare propia. |
| Relay login, `/oauth/authorize`, `/settings/pending_changes/*` | Navegador/cliente nativo | Conservar protección web actual; no ampliar Bypass a toda la web. |
| Relay `/oauth/token`, `/oauth/revoke` | Clientes Doorkeeper | Conservar las reglas que necesitan los clientes actuales. |

Verificar ausencia de HTML, redirecciones Access, challenges WAF/bot o 403 en
peticiones servidor-a-servidor. Evitar caché autenticada y logs de Authorization,
códigos, tokens o secretos. No se han cambiado políticas Cloudflare.

## Checklist de aceptación y rollback

- [ ] Registrar versión Authentik, issuer, cliente dedicado, callback y perfil de claims.
- [ ] Discovery/JWKS accesibles desde conector y Relay; metadata y desafíos correctos.
- [ ] Con techo `read`, conectar ChatGPT: contexto, cuentas visibles y una lectura
  pequeña coinciden con los permisos de la misma cuenta web.
- [ ] Rechazar usuario no vinculado/desactivado, solo `openid`, otro cliente,
  audiencia incorrecta, firma manipulada, ID token y token caducado.
- [ ] Catálogo de lectura; llamada manual de escritura rechazada con techo `read`.
- [ ] Comprobar S256 real y verifier incorrecto; comprobar refresh tras vencimiento.
- [ ] Solo con prueba de escritura autorizada, ampliar techo/scope y proponer un
  tag sintético. Antes de aprobar no existe; reintentar crea una única propuesta.
  Rechazar o aprobar conscientemente desde la web. No usar datos financieros reales.
- [ ] Reducir permisos antes de aprobar/aplicar: propuesta rechazada/detenida.
- [ ] Verificar OAuth nativo, API keys, REST, sesiones y Android existentes.
- [ ] Registrar resultados interactivos antes de certificar producción.

Rollback: desactivar `RELAY_MCP_AUTHENTIK_ENABLED` y recargar web/worker con el
procedimiento autorizado. Revocar conexión/refresh tokens en Authentik si se retira.
Doorkeeper y API keys conservan su configuración. No borrar usuarios ni propuestas.

Las pruebas automatizadas usan RSA/JWKS sintéticos y Docker `relay-tests`: validación,
discovery/fallos/rotación, vínculos, scopes, autorización por cuenta, separación
REST/MCP, compatibilidad OAuth/API keys y aprobación web. El test explícito
`test/manual/mcp_client_smoke.rb` usa el SDK oficial por HTTP contra un servidor
temporal y JWT sintético. No realiza login OAuth real ni certifica producción.
## Resultados locales (24 de octubre de 2026)

| Comprobación | Resultado |
| --- | --- |
| Suite Rails completa sobre el código final | 5.680 pruebas, 26.564 aserciones, 0 fallos, 0 errores, 38 omisiones condicionadas por el entorno; ninguna omisión nueva en estos tests. |
| Tests Authentik y smoke HTTP con SDK oficial 1.32.2 | 18 pruebas, 167 aserciones, 0 fallos, 0 errores, 0 omisiones. Incluye smoke nativo Doorkeeper y Authentik con propuestas/aprobación. |
| RuboCop | 1.849 archivos sin infracciones; comprobación adicional de los últimos ajustes del verificador/tests también correcta. |
| Brakeman | 0 errores, 0 avisos activos; se conservan las 5 exclusiones existentes. |
| Assets | Compilación correcta dentro de las ejecuciones de pruebas. |
| Diff | `git diff --check` correcto. |

La suite emite mensajes de Git porque la imagen de test no contiene `.git`, y
avisos de deprecación existentes; termina con estado correcto. No se han ejecutado
tests de navegador en esta tarea (no se han cambiado vistas), ni pruebas contra
datos o infraestructura de producción.

Repetir Rails con `.\bin\test-docker.ps1 unit`. Para reproducir el SDK tras
construir la imagen con ese script, ejecutar desde PowerShell:

```powershell
docker compose --project-name relay-tests --env-file docker/test.env --file compose.test.yml run --rm --entrypoint /bin/sh runner -c 'npm install --prefix /tmp/relay-mcp-client --no-audit --no-fund @modelcontextprotocol/sdk@1.32.2 && ruby bin/docker-test-entrypoint unit test/models/mcp/authentik_verifier_test.rb test/integration/mcp_authentik_test.rb test/manual/mcp_client_smoke.rb'
```

El SDK se instala solo en el contenedor efímero; no añade dependencias al producto.
Estos resultados no completan el checklist interactivo anterior.
