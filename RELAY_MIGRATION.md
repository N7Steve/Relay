# Migración de Sure a Relay

Fecha de inicio: **2 de octubre de 2026**.

## Estado consolidado al 4 de octubre de 2026

Steve confirma que Relay está desplegado, con los datos de Sure importados,
correctos y estables, y que conserva un backup local. La salida facilitada desde
TrueNAS confirma que web y worker ejecutan
`1e279bd8f6fe05d295c074180efccbcd59195ad5`, la referencia de inicio de la poda.

Las entregas posteriores a la décima incorporaron backups completos versión 3
con originales disponibles y restauración ZIP, además de instalación TrueNAS
en `/mnt/AppsPool/relay` y actualización desde Git con backup previo.
El ensayo documentado de un archivo Sure restauró 42.244 registros y 6 originales;
el inventario de pruebas actual queda en el [registro de fase 0](docs/migration/pruning-phase-0.md).

Los estados «pendientes» dentro de las entregas siguientes son fotografías
históricas. La separación técnica y el traslado están completados según la
confirmación del usuario; la simplificación funcional se ejecutará mediante el
[plan de poda](docs/migration/pruning-plan.md). No se ha inspeccionado directamente
la base TrueNAS ni certificado aquí su recuperación completa de instalación.
Google Drive y Brandfetch son funciones utilizadas y deben preservarse.


## Propósito y alcance

Relay es la evolución independiente de nuestro fork de Sure. Su prioridad son
las finanzas personales curadas, la exactitud de los datos, Agenda, las
previsiones y la comprensión de compromisos y liquidez. Mantener paridad con
Sure deja de ser un objetivo. Upstream sigue siendo una fuente de soluciones
que se analizan y adaptan por funcionalidades delimitadas.

Este documento registra la separación y su plan. No autoriza por sí mismo
futuras implementaciones, despliegues, migraciones sobre una instalación ni
cambios de configuración externa. Las reglas técnicas siguen en
[AGENTS.md](AGENTS.md) y [las guías](docs/llm-guides/README.md); las decisiones de
producto e integración están en [FORK_EVOLUTION.md](FORK_EVOLUTION.md). El mapa
de preservación es [FORK_CUSTOMIZATIONS.md](FORK_CUSTOMIZATIONS.md).

## Base y trazabilidad

| Referencia | Valor |
| --- | --- |
| Repositorio de trabajo | `D:\Steve\Proyectos\Relay` |
| Nuevo origin | `git@github.com:N7Steve/Relay.git` |
| Base estable de procedencia | `https://github.com/N7Steve/sure.git` |
| SHA importado | `2cc641c18794ec28b787d4d78bfb43b39f85720e` |
| Commit de procedencia | `Stabilize fork features and add local Docker workflows` |
| Historial de main importado | 3.505 commits, sin squash ni reescritura |
| Referencia upstream revisada en la política | `ec4282e0eba808e443b6c15a11d567c1c4c4f3fb` |
| Estado del origen al importar | Árbol limpio; los cambios locales previos ya estaban comprometidos |

El repositorio Relay ya estaba inicializado y su remoto no tenía referencias.
Se importaron objetos, ramas locales y etiquetas mediante Git desde Sure, y se
situó `main` en el SHA indicado. Los commits conservan SHA, autoría, fechas y
mensajes. La copia usa almacenamiento Git propio; no se copian credenciales,
archivos `.env`, bases de datos, adjuntos, dependencias ni configuración privada.

Remotos de Relay:

- `origin`: Relay; destino de sus nuevos commits.
- `legacy-sure`: nuestro repositorio Sure; referencia histórica.
- `upstream`: `https://github.com/we-promise/sure.git`; fuente de consultas.

Las ramas antiguas se conservan localmente bajo `refs/remotes/legacy-sure/` y
las etiquetas conservan sus nombres. Las referencias remotas que ya tenía Sure
se archivan localmente en `refs/archive/sure/remotes/`, conservando también la
historia alcanzable desde esas ramas sin activarlas como ramas de Relay. También
se conservan los refs locales de stash y capturas de Codex bajo
`refs/archive/sure/`; el archivo local contiene los mismos 6.231 commits
alcanzables que el origen al importar. Esos refs no se publican ni se activan
como stashes o trabajos de Relay.
La publicación inicial envía únicamente
`main`: las etiquetas heredadas no se publican como lanzamientos de Relay.
Si se necesita un archivo remoto de las demás ramas, prepararlo explícitamente
bajo nombres de archivo, sin activar workflows de publicación por etiquetas.
No usar un push espejo periódico para mantener Relay igual que Sure.

El repositorio Sure no se modifica. Un arreglo urgente realizado allí después
de la separación se evalúa y traslada a Relay de forma explícita.

## Primera entrega: identidad superficial

Alcance del primer commit propio:

- Valor predeterminado `PRODUCT_NAME=Relay`, conservando la personalización por
  variable de entorno y el valor actual de `BRAND_NAME`.
- Sustitución del nombre de producto literal `Sure` por `Relay` en traducciones;
  se conservan claves, interpolaciones, URLs y nombres técnicos.
- Nombre localizado de autorización y avisos de acceso de soporte.
- Títulos, correos y nombre del manifest PWA que ya consumen `product_name`
  reciben el nuevo nombre automáticamente.
- README propio con procedencia, límites de la primera entrega y guías locales.
- Enlace al commit de la aplicación dirigido al nuevo repositorio. El enlace a
  la versión heredada sigue apuntando a la release original hasta definir las
  versiones y releases propias.
- CI de Relay en `main`, sin publicación automática de imágenes desde el
  workflow heredado. El guard de su job CI impide el build/publicación en Relay
  para los eventos de `main` y cron; sus jobs independientes por etiquetas aún
  requieren revisión antes de publicar cualquier tag.

No se cambian lógica financiera, modelos, esquemas, migraciones, claves,
proveedores, namespaces, APIs, paquetes móviles ni identificadores de clientes.
Los logos e iconos existentes siguen siendo heredados: su sustitución requiere
una identidad visual propia y pertenece a la fase siguiente.

## Segunda entrega: marca visual y aislamiento local

Alcance de la segunda entrega sobre la primera (`8066175`):

- Logo original en `app/assets/images/relay.png` y banner original en
  `docs/branding/relay-banner.png`, sin modificar los archivos proporcionados.
- Logo Relay en acceso, navegación, onboarding, autorización y suscripciones.
  Se conservan las dimensiones y estilos existentes; los logos web obsoletos
  se retiran. Los recursos propios de clientes nativos siguen pendientes.
- Favicon, iconos Apple/Android/PWA y mosaico Windows derivados del logo.
  Fondo opaco para launchers; arte al 72% del lienzo, o 55% para maskable.
  Este último cabe dentro del círculo central seguro del 80%. Favicon al 90%.
  Exportación con Pillow/Lanczos desde el bounding box del canal alfa original;
  no hay nueva dependencia de ejecución de la aplicación.
- Pantalla offline con el logo nuevo y caché del service worker `relay-v2`.
  Las URLs del manifest y cabecera versionan los iconos para renovar la marca.
- README breve en inglés que presenta Relay como proyecto personal basado en
  Sure y conserva procedencia y licencia.
- Namespace Rails `Relay`, lectores y stubs coordinados; `.relay-version`
  sustituye `.sure-version` en runtime y workflows. Se conserva la versión
  heredada `0.7.6-alpha.1`, sin crear una release ni publicar etiquetas.
- Paquete npm raíz `relay`, sin cambios de dependencias.
- Entorno local `relay-local`, imagen `relay-local-app`, usuario/base
  `relay_local` y puerto **127.0.0.1:3002**; el puerto interno sigue en 3000.
  Pruebas `relay-tests` con usuario/base `relay_test`; guards y scripts alineados.
  Los volúmenes quedan aislados por proyecto. No se trasladan los datos locales
  de Sure ni se arranca la aplicación como parte de esta entrega.

Compatibilidad y reversión:

- El nombre por defecto de la base de producción permanece `sure_production`
  para no seleccionar silenciosamente una base vacía en instalaciones existentes.
  Una nueva instalación Relay debe definir `POSTGRES_DB` explícitamente; el
  traslado de una instalación requiere backup, restauración y validación aparte.
- No cambian `SureImport`, STI/constraints, contratos de exportación, variables
  `SURE_*`, cabeceras API, claves, issuer MFA, ni identificadores/callbacks nativos.
  Las propiedades analíticas `sure_version` y el atributo Stimulus homónimo se
  conservan como contratos, aunque su valor ya lo proporciona `Relay.version`.
- El namespace puede cambiar el nombre por defecto de la cookie Rails; revisar
  una posible nueva autenticación en despliegues. No se rotan claves ni se
  altera la cookie de autenticación explícita `session_token`.
- El rollback del código se hace revirtiendo este commit, sin migración de datos.
  Volver a `sure-local` selecciona sus antiguos volúmenes: no copiar ni borrar
  volúmenes automáticamente. Los archivos gráficos originales quedan conservados.

El inventario siguiente conserva los nombres de partida como mapa de búsqueda.
Marca web, Rails/versión, npm raíz, aislamiento Docker y tokens ya avanzaron;
clientes, datos persistidos y distribución siguen en las fases siguientes.

## Tercera entrega: diseño Relay y limpieza del legado

Ejecutada el **3 de octubre de 2026**, sobre `e5f294220`:

- Fuente `design/tokens/relay.tokens.json`, entrada `relay-design-system.css` y
  directorio `relay-design-system/`; consumidores, Lookbook, guías y atributos
  Git alineados. Las extensiones internas pasan de `sure.*` a `relay.*`.
- Generador móvil `mobile/tool/generate_relay_tokens.mjs` adaptado junto con sus
  pruebas y comentarios. Se mantienen `SureTokens`, sus archivos Dart y los
  componentes nativos como contratos internos del cliente existente.
- `npm run tokens:build` genera CSS web y Dart móvil; `tokens:check` comprueba
  ambos sin escribir y detecta archivos ausentes o desactualizados. CI ejecuta
  esta comprobación. Los checks aceptan CRLF en un checkout Windows.
- Todos los valores de tokens se conservan. El CSS regenerado elimina tres
  bloques redundantes heredados (`divide-subdued`, `button-bg-accent` y su hover)
  que ya no emitía el generador anterior. Las utilidades correspondientes siguen
  presentes; las hojas manuales no cambian sus estilos.
- Los 12 workflows heredados de publicación, releases, distribución, mirror,
  documentación, Gittensor y evaluaciones LLM por etiquetas pasan a
  `docs/archive/sure/workflows/`, con contenido intacto. Fuera de
  `.github/workflows/` no pueden ejecutar operaciones en Relay. Se conservan CI
  Rails/JavaScript, PR, Flutter, chart y Pipelock; los canales propios de
  publicación siguen pendientes de definición.
- Los informes antiguos de Agenda y rollback pasan a `docs/archive/sure/`, con
  un índice que explica su carácter histórico. El script `script.rb` pasa a
  `script/debug_currency_methods.rb`, sin cambiar su contenido. `conflicts.txt`
  se elimina después de verificar que es una lista UTF-16 de diez rutas de
  conflictos antiguos, sin consumidores. Todo conserva trazabilidad en Git.
- El mapa de preservación enlaza las rutas nuevas. No se elimina funcionalidad
  de Agenda, exportaciones, proveedores, IA, seguridad ni clientes nativos.

### Criterio de limpieza de la raíz

Se retiran de la raíz cuatro archivos históricos o auxiliares:
`informe_scheduled_payments.md`, `rollback-instructions.md`, `script.rb` y
`conflicts.txt`. El resto de la limpieza renombra fuentes de diseño y archiva
automatización fuera de la raíz.

Se mantienen los archivos necesarios para Rails, Bundler, npm, lint, Docker,
instrucciones y licencia. Los siguientes restos requieren continuidad explícita:

| Archivo/área | Razón para conservarlo ahora |
| --- | --- |
| `compose.example*.yml`, `pipelock.example.yaml`, `.env.example`, `charts/sure/` | Configuración de despliegue heredada, consumida por documentación y comprobaciones de seguridad; preparar destinos Relay antes de sustituirla |
| `Project.json`, `bitrig/`, `appStoreConnect/`, `desktop/`, `mobile/` | Clientes nativos e identidad de distribución todavía por decidir; no eliminar clientes por una limpieza de marca |
| `perf.rake` | Derailed Benchmarks lo exige en la raíz; la dependencia sigue en Gemfile |
| `FORK_CUSTOMIZATIONS.md`, `FORK_EVOLUTION.md`, `RELAY_MIGRATION.md`, adaptadores de agentes | Preservación, dirección y seguimiento actuales del proyecto |

### Estado y próximos pasos

| Fase | Estado después de esta entrega |
| --- | --- |
| 0. Base independiente | Completada; historia y remotos conservados |
| 1. Identidad visible | Marca web/PWA hecha; auditoría de servicios/hosting y superficies mantenidas pendiente |
| 2. Backend, herramientas y diseño | Rails, versión técnica, npm y tokens hechos; versión propia y tareas/variables compatibles pendientes |
| 3. Infraestructura y artefactos | Local/test aislados y publicación heredada retirada; imágenes y chart Relay pendientes |
| 4. Datos y contratos | Pendiente; STI, imports, exportaciones, variables legacy y cabeceras conservados |
| 5. Integraciones y clientes | Pendiente; callbacks y package/bundle IDs conservados |
| 6. Ensayo y publicación | Pendiente; no se ha migrado una instalación ni desplegado Relay |

Siguiente bloque técnico: preparar nombres Relay para exportaciones nuevas y
variables/tareas con precedencia documentada sobre los nombres Sure, probando
lectura legacy. Antes de tocar `SureImport`, diseñar conjuntamente STI, API,
restricciones y jobs. Para distribución, definir primero versión/canal y
destinos propios; no restaurar directamente los workflows archivados.

Reversión: revertir esta entrega devuelve las rutas, generadores y documentos
anteriores. Eso también reactiva los workflows heredados: revisar este efecto
antes de revertir en GitHub. No hay migraciones, cambios de datos, claves,
volúmenes o configuración externa que revertir.

## Cuarta entrega: configuración, tareas y backups compatibles

Ejecutada el **3 de octubre de 2026**, sobre `7565587f4`:

- Los backups nuevos usan `relay_export_YYYYMMDD_HHMMSS.zip`. Un export con
  adjunto conserva el nombre almacenado, incluidos los `sure_export_*`, tanto
  en la lista como en su descarga. El listado precarga adjuntos/blobs para no
  añadir consultas por fila. No se cambian los nombres CSV ni los destinos Drive.
- Los cinco nombres `RELAY_IMPORT_MAX_ROWS`, `RELAY_IMPORT_MAX_NDJSON_SIZE_MB`,
  `RELAY_BATCH_SIZE`, `RELAY_LIMIT` y `RELAY_DRY_RUN` sustituyen a los nombres
  Sure como configuración recomendada. `SURE_*` sigue funcionando cuando el
  equivalente Relay no está definido. Si Relay está definido pero es vacío o
  inválido, se aplican los defaults del consumidor, sin rescatar el valor legacy.
- En la tarea de cifrado se conserva la prioridad de argumentos explícitos y
  overrides sin prefijo antes de Relay/Sure. No cambia el dry-run seguro por
  defecto. `Relay::Environment.legacy_names_in_use` lista nombres legacy
  definidos sin equivalente Relay, sin imprimir valores ni secretos. En tareas
  son candidatos al fallback; los argumentos y overrides pueden tener prioridad.
- Las 12 tareas `sure:*` pasan a `relay:*`, conservando los alias antiguos,
  argumentos y ejecución única de Rake aunque se invoquen ambos nombres en el
  mismo proceso. Los comandos de ejemplo se actualizan; no se ejecutan tareas
  de mantenimiento sobre instalaciones existentes.
- Se actualizan plantillas `.env`, la guía local y
  [la guía de compatibilidad](docs/llm-guides/relay-compatibility.md), incluyendo
  precedencia, diagnóstico, formato de backup y reversión.
- OpenAPI usa el título Relay y documenta la configuración nueva y su fallback.
  Se regenera desde rswag documental. No se modifican rutas, parámetros,
  autenticación, scopes ni tenancy de los endpoints.

Se conservan `SureImport` como clase/tipo STI y valor API, `import_sessions`,
jobs, datos NDJSON, versión ZIP 2, cabeceras, issuer MFA, claves, callbacks e
identificadores nativos. No se añaden ni ejecutan migraciones. La restauración
usa el `all.ndjson` extraído de ambos nombres de ZIP; no se añade una subida
directa de ZIP.

### Estado actual y siguiente bloque

Las fases 0 y la base local de la 3 siguen completadas. La fase 2 ya incluye
las rutas de diseño y tareas propias; queda decidir versión y distribución.
La fase 4 avanza en configuración/exportaciones compatibles, pero aún falta
la transición de tipos persistidos y contratos de importación. Las fases 5 y 6
siguen pendientes.

Siguiente paso: diseñar la transición `SureImport`/`RelayImport` con lectura
compatible de ambos nombres y revisar conjuntamente STI, restricciones de
`import_sessions`, API, GlobalID y jobs. Definir después el cambio de escritura
y sus nuevas migraciones; no renombrar la clase ni reescribir migraciones
históricas de forma aislada. Publicación y clientes requieren primero decidir
versiones, canales y destinos reales de Relay.

Reversión: revertir esta entrega no modifica datos ni adjuntos. Antes de volver
al código anterior, copiar la configuración `RELAY_*` a sus nombres `SURE_*`
o mantener ambos con valores equivalentes, y volver a invocar `sure:*`: el
código anterior desconoce los nombres nuevos. El payload de backups Relay
sigue siendo compatible con el formato anterior.

## Quinta entrega: lectores de importación compatibles

Bloque del **3 de octubre de 2026**, sobre la cuarta entrega
`1f3e3713941c43b5d446a0096a37e790fcd1ff01`:

- Web, creación API, preflight y creación de sesiones aceptan `RelayImport` y
  `SureImport`. El formulario web envía el nombre Relay; los enlaces anteriores
  siguen funcionando.
- `Import::BACKUP_TYPES` reúne ambos nombres. `Import.storage_type` normaliza
  las entradas nuevas a `SureImport`; importaciones, sesiones, chunks y GlobalID
  escritos por los flujos normales siguen siendo compatibles con workers
  anteriores. Preflight también devuelve `SureImport` durante esta etapa.
- `RelayImport < SureImport` incorpora un lector STI real sin duplicar la
  implementación NDJSON. El initializer `backup_import_sti.rb` carga el
  subtipo mediante `to_prepare`, también con carga diferida y tras recargas.
  El lector padre y los GlobalID legacy pueden encontrar registros Relay.
- El filtro API por cualquiera de los nombres incluye ambos tipos guardados,
  siempre dentro de la familia. Detalles y listados devuelven el tipo real del
  registro; ambos conservan la verificación de lectura posterior.
- Las sesiones reutilizan el mismo `client_session_id` al alternar los nombres,
  preservando chunks, límites y conflictos de `expected_chunks`. Se conservan
  sus mappings y la clave de origen `sure_import_session:<id>`.
- Se limpian mensajes API y descripciones OpenAPI que presentaban el formato
  como exclusivo de Sure. Los nombres por defecto de adjuntos API nuevos son
  `relay-import.ndjson`; no se cambia ningún adjunto existente.
- Minitest cubre los dos tipos STI, adjuntos, GlobalID y jobs serializados de
  publicación/reversión, lectores de chunks, web, API, permisos y sesiones.
  OpenAPI describe la diferencia entre nombres aceptados y tipo escrito. El
  recorrido de backup Relay tiene cobertura de navegador.

No cambia el esquema: `import_sessions` mantiene default y constraint de
`SureImport`. Los adjuntos siguen usando el tipo polimórfico `Import`. Se
conservan preflight/excepciones y claves de traducción heredadas, payload NDJSON,
ZIP v2, rutas, scopes y tenancy. Los tipos Relay usados para ensayar lectores
se crean únicamente en bases aisladas de test. No se reescriben datos ni
migraciones históricas; tampoco se opera la instalación existente.

### Estado actual, siguiente bloque y reversión

La fase 4 completa la aceptación de nombres y la preparación de lectores. El
cambio de escritura/defaults/restricciones sigue pendiente. Las fases 0–3
conservan el avance anterior; versión y distribución propias y fases 5–6
continúan pendientes.

El siguiente bloque debe añadir una migración nueva, con versión Rails actual,
que amplíe el constraint de sesiones a ambos nombres antes de cambiar escritores.
Ensayar upgrade y reversión en una base aislada; desplegar primero los lectores
en todos los procesos web/worker. La escritura Relay debe coordinar defaults,
chunks, clientes que solo admiten respuestas `SureImport` e idempotencia de
sesiones existentes sin cambiarles el tipo al reintentar. El backfill de datos
es opcional y requiere un plan aparte; no es necesario para admitir nombres
nuevos. El procedimiento está en [compatibilidad Relay](docs/llm-guides/relay-compatibility.md).

Revertir este bloque conserva los datos generados por los flujos normales;
clientes/formularios deben volver a enviar `SureImport`. Si se hubieran creado
manualmente registros STI o jobs GlobalID Relay, inventariarlos antes de volver
al código anterior, que no los entiende. No usar `RelayImport.create!` ni
cambiar tipos manualmente mientras convivan workers antiguos.

## Sexta entrega: ampliación compatible del esquema de sesiones

Bloque del **3 de octubre de 2026**, sobre `fc55d3dfb`:

- Nueva migración Rails 8.1 `20261003120000_allow_relay_import_sessions.rb`:
  el constraint validado de `import_sessions.import_type` admite `SureImport`
  y `RelayImport`, conservando NOT NULL y el default `SureImport`.
- No cambian escritores web/API, preflight, chunks ni validación del modelo.
  Las sesiones y jobs normales siguen usando el nombre legacy. La ampliación
  prepara el esquema; no activa todavía la escritura Relay.
- La reversión bloquea la tabla antes de comprobar los tipos. Si existe alguna
  sesión no legacy, se niega mediante `ActiveRecord::IrreversibleMigration`,
  conservando datos y constraint. Sin esas sesiones restaura la restricción
  validada anterior. Nunca convierte ni borra filas para facilitar la reversión.
- Minitest ensaya upgrade, reversión, rechazo de tipos no permitidos/NULL,
  preservación de atributos/default e idempotencia y escritura legacy de chunks.
  El DDL se ejecuta dentro de transacciones de test en PostgreSQL aislado.

No se modifican migraciones históricas ni tipos STI de importaciones, contratos
API, adjuntos, mappings o payloads. No se aplican migraciones a instalaciones
existentes ni se arrancan servidores, despliegan lectores o publican artefactos.
Ambas direcciones necesitan un bloqueo exclusivo y validan filas existentes:
planificar su aplicación teniendo en cuenta el tamaño y actividad de la tabla.

### Estado actual y siguiente bloque

La fase 4 cuenta con lectores y una migración preparada para ampliar el esquema.
Quedan pendientes su ensayo sobre una copia de una instalación y el despliegue
coordinado, seguido del cambio de escritura/defaults y compatibilidad de clientes.
La versión propia, distribución y fases 5–6 mantienen sus pendientes anteriores.

Siguiente bloque de código: coordinar escritores de importaciones, sesiones y
chunks para los dos nombres; conservar el tipo de la sesión al reintentar su
`client_session_id`, y resolver las respuestas para clientes cuyo enum solo
acepta `SureImport`. No realizar backfill automático. La puesta en operación
debe desplegar primero lectores en todos los procesos y aplicar después esta
migración como operación aparte, antes de activar escritores nuevos.

Reversión del código: restaurar el esquema anterior únicamente si la reversión
de la migración puede completarse; si hay sesiones Relay, mantener la ampliación
hasta definir cómo tratarlas. Revertir archivos de Git no revierte una base.

## Séptima entrega: escritores Relay para la instancia única

Bloque del **3 de octubre de 2026**, sobre la sexta entrega preparada:

- Decisión del usuario: no mantener compatibilidad con versiones antiguas
  para despliegues mixtos ni clientes anteriores. Relay tendrá una instancia
  única que puede adaptarse directamente. Se conserva acceso a datos existentes.
- Web/API escriben `RelayImport` en todas las importaciones nuevas de backup.
  También las solicitudes con el nombre anterior se normalizan a Relay; no
  se añade negociación de respuestas, flags de transición ni cabeceras nuevas.
  La API devuelve el tipo guardado y preflight devuelve `RelayImport`.
- Las sesiones nuevas usan Relay con cualquiera de los nombres de entrada o
  sin tipo. La migración Rails 8.1 `20261003130000_use_relay_import_session_default.rb`
  cambia únicamente el default después de la ampliación del constraint.
  Revertir el default no convierte filas ni retira el constraint ampliado.
- Reintentar un `client_session_id` mantiene el tipo de su sesión original y
  sus chunks. Un bloqueo de fila protege la comprobación/completado de
  `expected_chunks`, también ante un insert duplicado. Los conflictos de
  conteo siguen rechazándose y no se cambia el tipo de sesiones existentes.
- Los chunks nuevos usan el tipo de su sesión; los anteriores mantienen el
  suyo. La publicación admite chunks de ambos tipos y los nuevos backups
  encolan GlobalID Relay. El lector Sure sigue para datos y jobs existentes.
- Cobertura de escrituras/defaults, reintentos normales y con carreras,
  publicación de chunks mixtos, permisos, tenancy y recorrido web.
  Specs rswag documentales y esquema OpenAPI actualizados.

Se elimina `Import.storage_type`, que forzaba los escritores al nombre anterior.
No se convierten tipos persistidos ni se reescriben migraciones históricas.
Se conservan payload NDJSON/ZIP, adjuntos `Import`, mappings, claves de origen,
verificación de lectura posterior, tenancy y autenticación. Las migraciones
se preparan en código y se ensayan solo en bases aisladas de pruebas; no se
aplican a ninguna instalación existente.

### Estado actual, continuación y reversión

La fase 4 tiene implementados lectores, constraint, default y escritores Relay.
La aplicación efectiva de las migraciones y el ensayo sobre una copia real
siguen pendientes. La decisión de instancia única sustituye la recomendación
anterior de mantener respuestas legacy y coordinar un despliegue por lectores
y escritores: la instalación se actualizará con web/workers a la misma versión.
No hay garantías para ejecutar versiones anteriores junto con estos escritores.

Siguiente bloque: auditar servicios/hosting e instrucciones activas heredadas
y preparar configuración de instalación Relay coherente con los artefactos
disponibles. Publicación, dominios, canales y clientes nativos siguen necesitando
destinos reales; no inventarlos ni activar los workflows Sure archivados.

Reversión: volver a código con lectores Relay conserva acceso a las nuevas
importaciones/jobs. Revertir solo el default mantiene válidas las sesiones
Relay; estrechar el constraint se rechaza mientras existan. Revertir a código
anterior a los lectores exigiría tratar datos/jobs explícitamente. No hacer
backfill ni borrar filas para forzar un rollback.

## Octava entrega: preparación final sin decisiones operativas

Preparada el **3 de octubre de 2026**, sobre `6157a7702`:

- Changelog consulta `N7Steve/Relay` y separa la caché por repositorio. La versión
  heredada se muestra sin enlazarla como release de Relay. Feedback, contacto y
  ayuda lateral llevan a sus issues; locales y templates GitHub coherentes.
- PostHog no incorpora token ni encuesta de Sure. Feedback self-hosted requiere
  `POSTHOG_FEEDBACK_KEY` y `POSTHOG_SELF_HOSTED_SANKEY_SURVEY_ID`, con opt-out
  explícito; los gráficos funcionan sin colección. Compose transmite las variables.
- Metadatos analíticos/Stimulus pasan a `relay_version`/`relayVersion` de forma
  coordinada, sin campos duales para versiones antiguas. La allowlist sigue limitada.
- User-Agent de proveedores, nombre mostrado por Plaid, prompts predeterminados
  del asistente y etiqueta de documentación API identifican Relay. No se cambian
  protocolos de importación, asociaciones externas ni prompts guardados por familias.
- Nuevas altas MFA usan issuer `Relay`. Los secretos existentes no cambian; la
  prueba verifica códigos creados con el issuer anterior. No hace falta reenrolar.
- No se reconocen dominios de Sure como demos de Relay.
- Solo existen tareas `relay:*`; se retiran aliases `sure:*` y fallbacks `SURE_*`.
  Remapear configuración antes del corte. Límites de importación y dry-run mantienen
  sus defaults; permanecen argumentos/overrides sin prefijo de las tareas.
- La tarea manual de webhooks Plaid EU exige `PLAID_EU_WEBHOOK_URL` HTTPS explícita
  y rechaza destinos ausentes/inválidos antes de cargar proveedor o actualizar items.
  No se ejecuta contra servicios externos en este bloque.
- Ejemplos Docker exigen `RELAY_IMAGE` explícita para web/worker; no seleccionan
  imagen upstream ni inventan registro de Relay. Validación del workflow Pipelock
  proporciona una imagen ficticia únicamente para renderizar configuración.
- Dockerfile normaliza scripts ejecutables de un checkout Windows. Guía Docker
  propia; guías Sure Docker/Hostim/Hetzner archivadas como referencia histórica.
  MCP/Pipelock descargan ejemplos Relay y explicitan la imagen; Plaid identifica
  el repositorio propio.
- [Procedimiento final](docs/migration/final-runbook.md) con inventario, backup
  completo, ensayo separado, validación financiera/autorización y recuperación.
- [Formulario final](docs/migration/final-decisions.md) con opciones, recomendaciones
  y campos pendientes: ubicación/datos/destino, acceso, imagen/versión, clientes,
  Helm, telemetría, integraciones, publicación y ventana de operación.

No se despliega, migra ni inspecciona una instalación existente; no se publica
Git, tags ni imágenes. Se conserva la base de producción por defecto y la
identidad histórica de datos. Sophtron (`source` y `sure-family-*`), identidad
externa del asistente, clientes nativos/FinanceKit, Helm y callbacks quedan
registrados para concretarlos según el alcance e instalaciones elegidos.

Las referencias anteriores a aliases, issuer y métricas describen entregas
históricas y quedan sustituidas por este estado. Revertir código restaura esos
nombres pero requiere ajustar la configuración correspondiente; para datos Relay
rige el procedimiento de backup/restauración, no una compatibilidad entre releases.

## Inventario técnico de la separación

| Área | Puntos principales | Tratamiento |
| --- | --- | --- |
| Marca web | `config/initializers/brand.rb`, helpers, locales, layouts y mailers | Nombre superficial iniciado; completar auditoría visual |
| Recursos gráficos | `app/assets/images/`, `public/`, manifest PWA | Crear logo, favicon e iconos propios y comprobar safe areas |
| Rails y versión | `config/application.rb`, `config/initializers/version.rb`, `.sure-version`, Sentry | Renombrado coordinado de namespace y lectores de versión |
| Diseño y generación | `sure-design-system.css`, su directorio, `design/tokens/sure.tokens.json`, `bin/tokens.mjs`, generador móvil, `package.json`, `.gitattributes` | Renombrar rutas y regenerar juntos, sin rediseñar tokens por accidente |
| Importaciones | `SureImport`, `SureImport::Preflight`, `Import::TYPES`, `ImportSession`, controladores y OpenAPI | Transición compatible de código, API y valores persistidos |
| Exportaciones | `FamilyExport#filename`, `sure_export_*`, formato NDJSON/ZIP | Nombre nuevo para archivos nuevos; lectura de formatos anteriores |
| Variables y tareas | `SURE_IMPORT_*`, `SURE_BATCH_SIZE`, `SURE_LIMIT`, `SURE_DRY_RUN`, namespaces `sure:*` | Nuevos nombres con precedencia y período de compatibilidad documentados |
| Autenticación y telemetría | issuer MFA `Sure Finances`, cookies/sesiones, `sure_version` de PostHog | Revisar continuidad e identidad sin invalidar credenciales o métricas |
| Docker local/test | `compose.local.yml`, `compose.test.yml`, scripts y entrypoints | Proyectos, imágenes, volúmenes, puertos y guards coherentes |
| Instalación y publicación | ejemplos Compose, `charts/sure/`, workflows y registro de imágenes | Destinos propios y activación explícita por canal |
| Proveedores | User-Agent y enlaces de cliente | Identificación Relay, conservando los protocolos externos |
| Escritorio | Tauri, `app.sure.desktop`, `sure://`, paquetes Rust/npm | Coordinar identidad, callbacks, builds y distribución |
| Móvil | Flutter, Android/iOS, `am.sure.mobile`, `sureapp://` | Coordinar identificadores, autorización y distribución |
| Swift | `bitrig/App/Sure*`, assets y proyecto | Revisar si se mantiene este cliente y completar su identidad |
| Documentación e integraciones | `docs/clients.md`, hosting, ejemplos API/MCP y callbacks externos | Diferenciar instrucciones de Relay de referencias históricas |

Buscar referencias con límites de palabra y nombres concretos. No reemplazar
subcadenas de `ensure`, `measurement`, `disclosure`, frases como “Are you sure?”
ni URLs históricas. Conservar licencia, atribuciones y referencias de origen.

## Plan por fases

### 0. Base independiente

Importar la historia y registrar el SHA de partida. Comprobar que el árbol del
origen está limpio y que la diferencia inicial contiene únicamente la identidad
superficial y documentación aprobadas. Conservar las referencias de archivo.

Salida: `main` de Relay deriva del SHA de origen y el primer commit propio puede
revertirse sin borrar historia ni modificar Sure.

### 1. Identidad visible completa

Revisar acceso, onboarding, navegación, ajustes, autorizaciones, correos,
errores, PWA, impresión y soporte. Crear los recursos visuales propios; revisar
claro/oscuro, español/inglés, accesibilidad, iconos maskable y Apple touch.
Auditar referencias a servicios y condiciones de hosting heredadas antes de
presentarlas como servicios propios de Relay.

Salida: el usuario identifica Relay en todas las superficies mantenidas.

### 2. Backend, herramientas y diseño

Renombrar `Sure::Application`, utilidades, tareas y archivo de versión con todos
sus consumidores. Mantener `DS::*`, semántica de tokens y convenciones Rails.
Renombrar fuentes, imports y generadores de diseño en un cambio coherente.
Definir versiones independientes; `relay-v0.1.0` es una propuesta pendiente,
evitando colisiones con tags heredados. Ajustar workflows al patrón elegido.

Salida: arranque, carga de clases, assets, tokens, versión y herramientas pasan.

### 3. Infraestructura aislada y artefactos propios

Antes de arrancar la aplicación Relay, cambiar los proyectos fijos `sure-local`
y `sure-tests`, nombres de imágenes y guards de entrypoints de forma coordinada.
Elegir un puerto distinto de 3000 si Sure y Relay convivirán. Los nombres de
proyecto Compose deben aislar volúmenes, redes y servicios.

Los ejemplos Docker exigen ahora `RELAY_IMAGE` explícita. La construcción local
está comprobada; registro, canal y chart mantenido se eligen en el formulario. Revisar todos los
workflows con capacidad de escribir, publicar o desplegar, incluidos workflows
por tag o manuales. Activar cada canal después de definir sus destinos.

Salida: instalar Relay utiliza sus artefactos; operar Relay no toca Sure.

### 4. Datos, importaciones y contratos compatibles

`SureImport` es un tipo STI persistido, un valor del contrato API y el único
`import_type` permitido por una restricción de `import_sessions`. Cambiar solo
la clase rompería registros existentes y clientes.

Diseñar primero lectura compatible y aceptación de ambos nombres; después
incorporar nuevas migraciones para defaults, restricciones y datos. Mantener
compatibilidad durante el despliegue de web y workers; auditar GlobalID,
payloads de jobs y tipos de Active Storage antes de retirar nombres antiguos.
No renombrar ni reescribir migraciones históricas.

Documentar precedencia de variables nuevas sobre legacy y cómo detectar su uso.
Cambiar únicamente los nombres de exportaciones nuevas y verificar que archivos
anteriores siguen siendo importables. Mantener `/api/v1`, autenticación
`X-Api-Key`/OAuth, permisos y tenancy. FinanceKit usa contratos como
`X-Sure-Payload-SHA256`: su nombre requiere transición compatible con el
publicador, no una sustitución superficial. Si cambian endpoints, incluir Minitest,
rswag documental y regeneración de OpenAPI conforme a las guías.

Salida: datos y clientes anteriores siguen funcionando durante la transición.

### 5. Integraciones y clientes

Definir dominios y URLs reales de Relay antes de registrar callbacks OAuth,
SSO y webhooks. No deducir un dominio nuevo por sustitución del nombre.
Coordinar `sure://` y `sureapp://`, presentes también en el controlador de
sesiones, con las aplicaciones cliente. Decidir continuidad o nueva identidad
de distribución antes de cambiar package/bundle IDs y firmas.

Mantener proveedores funcionales y la puerta global de IA. Revisar también
agentes externos y ejemplos MCP/API que puedan seguir usando el nombre antiguo.

Salida: login, callbacks y conexiones funcionan para cada cliente soportado.

### 6. Ensayo de datos, publicación y reversión

Ensayar sobre una copia de PostgreSQL y los adjuntos necesarios, nunca sobre la
instalación estable de Sure. Inventariar claves, `schema_migrations`, Active
Storage, conexiones de proveedores, jobs y configuración de Drive.

Conservar las claves existentes para leer datos cifrados. El initializer de
Active Record puede derivarlas de `SECRET_KEY_BASE`; regenerar este valor sin
un plan de cifrado puede impedir leer credenciales. Probar exportación/restauración
y registrar qué datos no cubre cada formato de exportación.

Planificar un corte con backups, coordinación de workers, comprobaciones y
rollback probado. Cambiar la imagen no revierte cambios de datos; definir qué
migraciones siguen siendo compatibles y cuándo hace falta restaurar un backup.
La puesta en producción se aprueba y ejecuta como trabajo separado.

Salida: primera versión operable de Relay y recuperación ensayada.

## Preservación funcional

Usar el inventario del fork, especialmente para:

- Agenda: generación, confirmación, rechazo, transferencias y vínculos.
- Tratamiento financiero, seguimiento, fuera de finanzas y archivo de cuentas.
- Saldos, patrimonio, informes, transferencias y cálculos multimoneda.
- Previsiones, incertidumbre, roboadvisor y rendimiento de carteras.
- Meses familiares y períodos independientes de widgets.
- Logos por familia, Active Storage, exportaciones y Google Drive personales.
- Autorización, aislamiento familiar, frontera Bills/Plan/Goals y puerta de IA.

## Integraciones futuras desde upstream

Seguir el proceso de análisis y selección de `FORK_EVOLUTION.md`. Las unidades
de incorporación son funcionalidades completas y acotadas. Registrar fecha,
rango revisado, SHA fuente, decisión, adaptaciones, commit Relay, validación y
reversión. Preferir adaptación parcial o implementación propia cuando evita
dependencias ajenas a Relay. Los squash anteriores hacen que el merge-base no
sea suficiente para saber qué contenido ya está integrado.

## Validación y seguimiento

Las herramientas Rails/Bundler se ejecutan en Docker/Linux. La segunda entrega
usa proyectos nuevos **`relay-identity-unit`** (suite completa) y
**`relay-identity-system`** (navegador), con `compose.test.yml` y `docker/test.env`.
Cada proyecto tiene su propia base `relay_test`, alineada con el guard del runner.
Los scripts para uso habitual ya usan `relay-tests`.

La primera entrega usó `relay-unit-tests` y `relay-tests` con el nombre interno
`sure_test`. Sus volúmenes conservan el esquema/usuario anteriores: no
reutilizarlos con el Compose nuevo sin preparar explícitamente una base de
pruebas nueva. Ninguna ejecución comparte el entorno `sure-tests` del origen.

Desde la raíz de Relay, con Docker Desktop en contenedores Linux:

```powershell
# Suite completa sobre su propia base de pruebas.
docker --context desktop-linux compose --project-name relay-identity-unit --env-file docker/test.env --file compose.test.yml build runner
docker --context desktop-linux compose --project-name relay-identity-unit --env-file docker/test.env --file compose.test.yml up --detach --wait db redis
docker --context desktop-linux compose --project-name relay-identity-unit --env-file docker/test.env --file compose.test.yml run --rm runner unit

# Navegador, sobre otra base para evitar interferencias con la suite completa.
docker --context desktop-linux compose --project-name relay-identity-system --env-file docker/test.env --file compose.test.yml build runner
docker --context desktop-linux compose --project-name relay-identity-system --env-file docker/test.env --file compose.test.yml --profile browser up --detach --wait db redis selenium
docker --context desktop-linux compose --project-name relay-identity-system --env-file docker/test.env --file compose.test.yml --profile browser run --rm --use-aliases -e SELENIUM_REMOTE_URL=http://selenium:4444 -e CAPYBARA_APP_HOST=runner -e CAPYBARA_SERVER_PORT=3001 runner system test/system/onboardings_test.rb test/system/admin/system_health_test.rb

# Detener únicamente las pruebas de Relay, conservando sus volúmenes.
docker --context desktop-linux compose --project-name relay-identity-unit --env-file docker/test.env --file compose.test.yml down
docker --context desktop-linux compose --project-name relay-identity-system --env-file docker/test.env --file compose.test.yml --profile browser down
```

El entrypoint de pruebas crea/carga únicamente el esquema de su base aislada;
no aplica las migraciones históricas ni conecta con la instalación estable.

Antes de push, la suite completa `bin/rails test` debe pasar. Para futuros PRs,
cumplir además las pruebas de sistema aplicables, RuboCop, ERB lint, Biome y
Brakeman según [development.md](docs/llm-guides/development.md). Verificar build,
tokens, contratos y pruebas de compatibilidad según el área; registrar resultados
reales y distinguir pendientes. No ocultar fallos heredados como validación.

Validación de la primera entrega, completada el 2 de octubre de 2026:

| Comprobación | Resultado |
| --- | --- |
| Suite completa Rails/Minitest | 10.777 pruebas, 45.639 aserciones, 0 fallos, 0 errores, 33 omisiones |
| Sistema: onboarding y salud de administración en Chromium | 19 pruebas, 87 aserciones, 0 fallos, 0 errores, 0 omisiones |
| RuboCop sobre los 12 archivos Ruby modificados | Sin infracciones |
| ERB lint sobre las 3 vistas modificadas | Sin errores |
| Sintaxis de locales YAML | 2.462 archivos válidos |
| Comparación semántica de locales con el origen | 2.460 archivos heredados verificados; claves conservadas y cambios limitados a marca, más las traducciones nuevas de autorización/soporte |
| Sintaxis y configuración de workflows | 19 archivos válidos; CI propio y guard de publicación verificados |
| Historia Git antes del commit propio | Los 6.231 SHA alcanzables del origen están presentes e idénticos |
| Whitespace | `git diff --check` sin incidencias |

La primera ejecución completa detectó 12 expectativas de texto que conservaban
el nombre Sure. Se actualizaron únicamente esas expectativas y se repitió la
suite completa hasta el resultado anterior. Las 33 omisiones de la suite quedan
visibles; no se eliminaron ni se presentaron como pruebas ejecutadas.

El código de esta entrega queda preparado para publicar en `origin/main` con
un único commit propio sobre la base importada. CI remoto se comprueba después
del push; estos resultados son locales y no certifican un despliegue, una nueva
imagen de producción ni las fases técnicas pendientes. No se abre una PR en
esta entrega ni se afirma haber ejecutado todo el checklist de futuras PRs.

### Validación de la segunda entrega

Ejecutada el 2 de octubre de 2026, en contenedores Linux aislados:

| Comprobación | Resultado |
| --- | --- |
| Suite completa Rails/Minitest | 10.777 pruebas, 45.639 aserciones, 0 fallos, 0 errores, 33 omisiones |
| Sistema: onboarding y salud de administración en Chromium | 19 pruebas, 87 aserciones, sin fallos, errores ni omisiones |
| Revisión visual temporal en Chromium | Acceso y dashboard: logo descargado/renderizado; 1 prueba y 4 aserciones, sin fallos; capturas inspeccionadas |
| RuboCop | Los 11 archivos Ruby modificados pasan |
| ERB lint | Las 14 vistas modificadas pasan |
| Biome | 142 archivos comprobados, sin cambios automáticos |
| Brakeman | 0 errores y 0 avisos activos; conserva 8 avisos ignorados por la configuración heredada |
| Configuración | Compose local/test válido; ambos scripts PowerShell parsean; 19 workflows YAML válidos; service worker con sintaxis JavaScript válida |
| Recursos visuales | Originales verificados mediante SHA-256; 8 PNG opacos con dimensiones esperadas; geometría maskable y recorte circular verificados |
| Whitespace | `git diff --cached --check` sin incidencias |

Los logs y capturas de revisión se guardan localmente bajo `tmp/`, fuera de Git.
Las pruebas cargan el esquema exclusivamente en sus bases aisladas. La revisión
visual temporal no añade pruebas al producto. No se arrancó el entorno local
Relay ni se aplicaron migraciones a instalaciones existentes. Se detienen los
servicios de pruebas sin borrar volúmenes y se conserva Sure intacto.
Los resultados son locales; no equivalen a una release o despliegue de clientes.

### Validación de la tercera entrega

Ejecutada el 3 de octubre de 2026. Se usan proyectos Docker nuevos
`relay-migration-unit` y `relay-migration-system`, cada uno con su base aislada
`relay_test`. La suite de navegador ejecuta todos los tests de sistema.

| Comprobación | Resultado |
| --- | --- |
| Suite completa Rails/Minitest | 10.777 pruebas, 45.639 aserciones, 0 fallos, 0 errores, 33 omisiones heredadas |
| Suite completa de sistema en Chromium | 189 pruebas, 968 aserciones, 0 fallos, 0 errores, 0 omisiones |
| RuboCop completo | 2.915 archivos, sin infracciones |
| ERB lint completo | 779 plantillas, sin errores |
| Biome | 142 archivos, sin errores |
| Brakeman | 0 errores, 0 avisos activos; conserva las 8 exclusiones heredadas |
| Assets | Compilación correcta en ambas suites |
| Generadores | CSS y Dart actualizados; sintaxis Node válida; checks ejecutados en Windows y Linux |
| Checks negativos de generación | Ambos rechazan archivos ausentes y desactualizados sin escribirlos, sobre copias temporales |
| Preservación del diseño | Valores JSON y CSS manual idénticos; declaraciones Dart idénticas; CSS generado solo elimina los 3 bloques duplicados descritos |
| Archivo histórico | 12 workflows y 2 informes conservan su contenido; script trasladado sin cambios |
| Configuración | 7 workflows activos y 12 archivados parsean; llamadas locales resueltas; Compose local/test válido |
| Whitespace | `git diff --cached --check` correcto |

No se ejecuta Flutter nativo localmente; las declaraciones generadas se verifican
por comparación y el workflow Flutter activo comprueba el cliente en CI. La
validación local no certifica el resultado remoto, una release ni un despliegue.
Los logs y copias de auditoría están en `tmp/`, fuera de Git. No se ejecutan
migraciones ni se arranca la instalación local. Los servicios de pruebas se
detienen conservando sus volúmenes al terminar.

### Validación de la cuarta entrega

Ejecutada el 3 de octubre de 2026 en los proyectos aislados `relay-contracts`
y `relay-contracts-system`, con bases `relay_test` independientes:

| Comprobación | Resultado |
| --- | --- |
| Focalizadas: configuración, tareas, backups, importaciones web/API | 204 pruebas, 1.003 aserciones, sin fallos, errores ni omisiones |
| Suite completa Rails/Minitest final | 10.791 pruebas, 45.731 aserciones, 0 fallos, 0 errores, 33 omisiones heredadas |
| Sistema: importaciones y subida desde Transacciones | 7 pruebas, 26 aserciones, sin fallos, errores ni omisiones |
| RuboCop completo | 2.919 archivos, sin infracciones |
| ERB lint completo | 779 plantillas, sin errores |
| Biome | 142 archivos, sin errores |
| Brakeman | 0 errores, 0 avisos activos; conserva las 8 exclusiones heredadas |
| Assets y tokens | Compilación correcta en test; CSS/Dart pasan `tokens:check` |
| OpenAPI | Regenerado: 435 ejemplos documentales, 0 fallos, 89 pendientes documentales heredados; diff limitado a título y 2 descripciones |
| API | Minitest usa `X-Api-Key`; rswag sigue documental; verificador de consistencia correcto |
| Tareas | `bin/rails -T relay:` registra los 12 nombres canónicos; compatibilidad y argumentos cubiertos por Minitest |
| Whitespace | `git diff --check` correcto |

Las pruebas cargan el esquema solo en sus bases aisladas. No se ejecutan tareas
de mantenimiento en instalaciones existentes, migraciones históricas,
despliegues ni el servidor local. Los logs permanecen en `tmp/`, fuera de Git;
los servicios de pruebas se detienen al terminar, sin borrar volúmenes. Los
resultados son locales; CI remoto y distribución no quedan certificados.

### Validación de la quinta entrega

Ejecutada el 3 de octubre de 2026 en `relay-import-compat` y
`relay-import-compat-system`, con bases `relay_test` independientes:

| Comprobación | Resultado |
| --- | --- |
| Focalizadas: STI, GlobalID, jobs, sesiones e importaciones web/API | 233 pruebas, 1.200 aserciones, sin fallos, errores ni omisiones |
| Suite completa Rails/Minitest | 10.809 pruebas, 45.867 aserciones, 0 fallos, 0 errores, 33 omisiones heredadas |
| Sistema: importaciones y subida desde Transacciones, incluido backup Relay | 8 pruebas, 32 aserciones, sin fallos, errores ni omisiones |
| RuboCop completo | 2.922 archivos, sin infracciones |
| ERB lint completo | 779 plantillas, sin errores |
| Biome | 142 archivos, sin errores |
| Brakeman | 0 errores, 0 avisos activos; conserva las 8 exclusiones heredadas |
| Assets y tokens | Compilación correcta en ambas suites; CSS/Dart pasan `tokens:check` |
| Carga diferida STI | Arranque sin `CI` confirma `RelayImport` en los descendientes de `SureImport` sin forzar la carga desde la comprobación |
| OpenAPI | Regenerado: 435 ejemplos documentales, 0 fallos, 89 pendientes heredados; diff limitado a esquemas/descripciones de importación |
| API modificada | Cobertura Minitest con `X-Api-Key`; specs rswag documentales; verificador de guía correcto |

El inventario global `verify_api_endpoint_consistency.rb --compliance` señala
dos desviaciones preexistentes fuera del bloque: Bearer de publicador en
`financekit_spec.rb` y aserciones en `transfers_spec.rb`. Los archivos modificados
no las introducen; no se presenta el inventario global como totalmente conforme.
La generación OpenAPI conserva sus 89 pendientes documentales.

La primera ejecución focalizada detectó expectativas nuevas que suponían que
un backup con solo una cuenta no generaba una valoración inicial. Se completaron
los datos de prueba con una valoración explícita y se corrigió el mensaje de una
aserción de sesión; la repetición final pasa sin modificar el importador ni la
verificación del producto.

Los logs están en `tmp/`, fuera de Git. Se carga el esquema únicamente en las
bases aisladas de pruebas; no se migran instalaciones existentes ni se despliega
la aplicación. Las pruebas de navegador usan su servidor temporal de Capybara.
Los servicios de estos dos proyectos se detienen conservando los volúmenes al
terminar. Los resultados son locales; no certifican CI remoto ni distribución.

### Validación de la sexta entrega

Ejecutada el 3 de octubre de 2026 en el proyecto nuevo `relay-import-schema`,
con PostgreSQL 16 y su base `relay_test` aislada:

| Comprobación | Resultado |
| --- | --- |
| Focalizadas: migración, sesiones, lector STI y API de sesiones | 58 pruebas, 295 aserciones, sin fallos, errores ni omisiones |
| Suite completa Rails/Minitest | 10.814 pruebas, 45.893 aserciones, 0 fallos, 0 errores, 33 omisiones heredadas |
| RuboCop completo | 2.924 archivos, sin infracciones |
| ERB lint completo | 779 plantillas, sin errores |
| Biome | 142 archivos, sin errores |
| Brakeman | 0 errores, 0 avisos activos; conserva las 8 exclusiones heredadas |

Las pruebas de la migración ejecutan upgrade y reversión dentro de sus
transacciones; el runner carga el esquema en su propia base, sin ejecutar el
historial de migraciones. Assets se compilan correctamente en ambas ejecuciones;
`git diff --check` pasa. No se ejecuta suite de navegador: no cambia el flujo
web ni la escritura del producto. No se modifican instalaciones existentes. Los logs
permanecen en `tmp/`, fuera de Git. Las comprobaciones son locales y no
certifican un despliegue, CI remoto ni una release. La definición de la tabla
`import_sessions` coincide con el dump de Rails/PostgreSQL. El dump completo
también reordena y normaliza otras definiciones heredadas; esas diferencias
ajenas al bloque no se trasladan a `db/schema.rb`. Los servicios del proyecto
de pruebas se detienen al terminar, conservando sus volúmenes.

### Validación de la séptima entrega

Ejecutada el 3 de octubre de 2026 en `relay-import-writers` y
`relay-import-writers-system`, con bases `relay_test` independientes:

| Comprobación | Resultado |
| --- | --- |
| Focalizadas: migraciones, lectores, escritores, sesiones y web/API | 238 pruebas, 1.251 aserciones, sin fallos, errores ni omisiones |
| Suite completa Rails/Minitest final | 10.821 pruebas, 45.938 aserciones, 0 fallos, 0 errores, 33 omisiones heredadas |
| Sistema: importaciones y drag/drop, incluido backup Relay | 8 pruebas, 32 aserciones, sin fallos, errores ni omisiones |
| RuboCop completo | 2.926 archivos, sin infracciones |
| ERB lint completo | 779 plantillas, sin errores |
| Biome | 142 archivos, sin errores |
| Brakeman | 0 errores, 0 avisos activos; conserva las 8 exclusiones heredadas |
| OpenAPI | Regenerado: 435 ejemplos, 0 fallos, 89 pendientes documentales heredados |
| Esquema | Tabla `import_sessions` y versión coinciden con el dump de Rails/PostgreSQL |
| API | Verificador de consistencia correcto; Minitest con `X-Api-Key`, rswag documental |

La primera ejecución focalizada pasa. Tras simplificar la selección interna del
tipo, la suite completa valida el código final. Los cambios OpenAPI se limitan
a las descripciones de escritores/preflight/chunks y el enum de sesiones.
Los 89 pendientes documentales y las desviaciones globales heredadas de
FinanceKit/transfers recogidas en la quinta entrega no se resuelven en este bloque.

Assets se compilan en ambas bases. Los tests de migraciones cambian y revierten
el esquema solo dentro de transacciones de pruebas; no se ejecuta `db:migrate`
ni se opera una instalación existente. El navegador usa el servidor temporal
de Capybara. Logs y dump quedan en `tmp/`, fuera de Git. `git diff --check`
pasa; los servicios de ambos proyectos se detienen conservando los volúmenes.
La validación local no certifica CI remoto, publicación ni despliegue.

### Validación de la octava entrega

Ejecutada el 3 de octubre de 2026 en `relay-final-prep` y
`relay-final-browser`, con bases `relay_test` independientes:

| Comprobación | Resultado |
| --- | --- |
| Suite completa Rails/Minitest final | 10.827 pruebas, 45.922 aserciones, 0 fallos, 0 errores, 33 omisiones existentes; 533 segundos |
| Focalizadas de nombres, límites y tareas | 78 pruebas, 327 aserciones, sin fallos, errores ni omisiones |
| Focalizadas de MFA, preview y webhook explícito | 121 pruebas, 480 aserciones, sin fallos, errores ni omisiones |
| Focalizadas iniciales de GitHub/feedback/páginas | 83 pruebas, 349 aserciones, sin fallos, errores ni omisiones |
| Sistema: ajustes y cash flow | 19 pruebas, 181 aserciones, sin fallos, errores ni omisiones |
| Analítica JavaScript offline | 10 pruebas, sin fallos ni omisiones |
| RuboCop completo | 2.926 archivos, sin infracciones |
| ERB lint completo | 779 plantillas, sin errores |
| Biome | 142 archivos sin errores de lint; check de formato/imports del controlador modificado correcto |
| Brakeman | 0 errores, 0 avisos activos; conserva las 8 exclusiones existentes |
| Tokens | CSS y Dart generados vigentes |
| Docker producción | Imagen local `relay-final-prep:validation` construida y assets compilados; sin arrancarla ni publicarla |
| Compose estándar/AI | Configuración válida con imagen explícita; falta de `RELAY_IMAGE` rechazada; perfil externo conserva Pipelock/OpenClaw sin servicios Ollama |
| Whitespace | `git diff --check` correcto |

La suite final incorpora todos los cambios de código de esta entrega. Las
aserciones antiguas de aliases se sustituyen por cobertura de su retirada y de
variables obsoletas ignoradas; la reducción neta de aserciones respecto a la
séptima entrega no procede de omitir pruebas. El primer pase de navegador detectó
un stub de Registry que también bloqueaba proveedores ajenos; se acotó al proveedor
GitHub y la ejecución final pasa. Los stubs prueban destinos locales sin enviar
feedback, actualizar webhooks ni consultar releases reales.

Las pruebas cargan el esquema en bases propias; no se ejecuta `db:migrate` en
una instalación. El navegador usa el servidor temporal de Capybara. La imagen de
producción es una validación del árbol de trabajo sobre la base `6157a7702`, no
una release ni un artefacto publicado. La restauración de datos reales, CI remoto
y corte siguen pendientes del formulario; las pruebas de fixtures no los certifican.
No hay cambios de endpoints, esquema ni especificación OpenAPI en esta entrega.

Los servicios de estos dos proyectos se detienen conservando sus volúmenes.
Logs de validación quedan en `tmp/`, fuera de Git. La instalación Sure existente
no se toca. Los cambios se dejan revisables en el árbol de trabajo, sin commit,
push, tags ni publicación de imágenes.

### Novena entrega: decisiones aplicadas y Relay 0.1.0

El 3 de octubre de 2026 Steve autoriza preparar commits y publicarlos en `main`.
La octava entrega se publica como `cdca804fb6b5e99b8e0c08eac0c1c6045a86efa2`;
su [CI remoto](https://github.com/N7Steve/Relay/actions/runs/37118875855) pasa.
El [formulario respondido](docs/migration/final-decisions.md) fija Docker,
TrueNAS, clientes/funciones actuales, telemetría desactivada y versión propia
0.1.0. Primero se prueba una instalación limpia; los datos se trasladan después
de estabilizarla. La limpieza funcional y de dependencias queda para después.

Cambios de este bloque:

- `.relay-version`, metadatos npm y Flutter comienzan la serie 0.1.0.
- Marca, textos e iconos Relay en Flutter, Tauri y Apple; se conservan paquetes,
  clases y callbacks externos para los clientes actuales.
- PostHog, Sentry, Skylight y Logtail no se inicializan; las variables heredadas
  no los activan. Se retiran SDK web, encuestas, bootstrap y eventos del Sankey.
  Se conservan comparación, ampliación y gráficos. Flutter tampoco inicializa
  telemetría con un DSN configurado. Logs locales y diagnósticos siguen disponibles.
- Las nuevas plantillas y el default de producción usan `relay_production`;
  Compose usa `relay_user` y red Relay. Imagen, contraseña y clave son explícitas.
  No se renombra ninguna base existente.
- `compose.source.yml` permite construir web/worker desde la misma revisión Git.
  TrueNAS 25.10.4 tiene `sure-web-test`, imagen local `sure-staging-web-test`,
  puerto host 3001 → 3000. No se presupone un registro remoto ni se inicia Relay.
- Las guías de hosting/telemetría, decisiones y runbook reflejan el alcance real.
  El ZIP financiero no incluye binarios ni sustituye un backup de instalación:
  el traslado completo requiere PostgreSQL, almacenamiento y configuración
  privada, con inventario y restauración aislada antes del corte.

Archivos afectados: inicializadores/configuración Rails, helper de feedback,
autenticación, cabecera y preview Sankey, controlador Stimulus y sus pruebas;
plantillas de entorno/Compose y workflows de validación; clientes `mobile/`,
`desktop/` y `bitrig/`; metadatos de versión y documentación citada. No cambian
endpoints API, esquema ni migraciones en este bloque.

### Validación de la novena entrega

Ejecutada en Linux Docker el 3 de octubre de 2026 con proyectos independientes
`relay-release-test` y `relay-release-browser`, sin usar la instalación Sure:

| Comprobación | Resultado |
| --- | --- |
| Suite completa Rails/Minitest | 10.818 pruebas, 45.893 aserciones, 0 fallos, 0 errores, 33 omisiones existentes; 589 segundos |
| Focalizadas de feedback, preview y sesiones | 57 pruebas, 233 aserciones, sin fallos, errores ni omisiones |
| Sistema: ajustes y cash flow | 12 pruebas, 120 aserciones, sin fallos, errores ni omisiones; navegación/ampliación sin eventos de analítica |
| RuboCop | 2.926 archivos, sin infracciones |
| ERB lint | 777 plantillas, sin errores |
| Biome | 142 archivos, sin errores de lint |
| Brakeman | 0 errores, 0 avisos activos; conserva 8 exclusiones existentes |
| Flutter 3.32.4 | 181 pruebas pasan; análisis sin errores ni warnings, con 3 infos existentes de `intro_screen_web.dart` |
| Frontend de escritorio | 6 pruebas Node pasan; TypeScript y build Vite correctos |
| Docker de producción | Imagen local `relay-release-test:validation` construida con assets |
| Arranque de producción sin red | Confirma Relay 0.1.0, default `relay_production` y SDK remotos no inicializados, incluso con variables heredadas |
| Compose estándar/AI y override Git | Configuraciones válidas con valores de validación explícitos |
| Whitespace | `git diff --check` correcto |

La reducción de tests respecto al bloque anterior corresponde a las encuestas
y analítica retiradas, no a omitir cobertura restante. La suite completa valida
el código de comportamiento; el ajuste posterior del default de base de
producción se verifica mediante el arranque aislado. No se inicia un servidor
de aplicación ni se ejecutan migraciones sobre datos reales. Capybara usa su
servidor temporal de pruebas. No se compilan aquí los binarios Swift/Tauri ni
se publican clientes en tiendas. Logs y artefactos quedan en `tmp/`, fuera de Git.

La imagen de validación no se publica; el canal autorizado es el repositorio
Git en `main`. Despliegue TrueNAS, exportación/importación real y corte siguen
pendientes de su fase operativa. Los proyectos de pruebas se detienen conservando
sus volúmenes. Para revertir este bloque de código puede usarse Git revert;
tras admitir escrituras reales, el rollback de datos requiere el procedimiento
del runbook y no consiste solamente en sustituir la imagen.

La entrega se publica en `f9e46896d9fafcb502e62dea857fc8566ff60987`.
El primer CI activa el workflow heredado de Helm por el cambio de versión y
rechaza la diferencia respecto al chart Sure. Como Docker es el alcance elegido,
se archiva `chart-ci.yml` en `docs/archive/sure/workflows/`: no se adapta ni
publica el chart histórico para aparentar soporte Helm de Relay. Los workflows
Rails y móvil permanecen activos; sus resultados remotos se verifican aparte.

### Décima entrega: instalación TrueNAS desde un YAML

Steve solicita un YAML completo, instalación inicial automática y bases estables
para actualizaciones futuras. `compose.truenas.yml` y `docs/hosting/truenas.md`
definen una Custom App nueva llamada `relay`, puerto host 3002, sin rutas locales
obligatorias ni `.env` externo. El build remoto fija la revisión validada
`caba5bf58823f8d2571bc8b1bd617a09c0775359` (Relay y Mobile CI pasan); no se publica
una imagen remota ni se usa `main` flotante.

Un servicio init idempotente genera contraseña, secreto de sesiones y tres
claves de cifrado en el volumen privado `relay-config`, sin imprimirlas. Si la
base existe y faltan las claves, se detiene en vez de regenerarlas. PostgreSQL
16 lee su contraseña de archivo; web y worker usan la misma configuración.
Persisten base, adjuntos y Redis AOF en otros tres volúmenes del proyecto.
Web prepara la base mediante el entrypoint vigente y worker espera `/up` saludable.
Las actualizaciones cambian la revisión/etiqueta, conservando nombre de app y
volúmenes. Backups, TLS y restauración Sure se explican por separado.

Validado el 3 de octubre de 2026 en `relay-truenas-validation` local aislado:

- `docker compose config --quiet` acepta el YAML sin variables externas.
- Build desde la URL Git con SHA completo termina y compila assets de producción.
- Init termina con código 0; PostgreSQL/Redis/web saludables y Sidekiq arranca.
- Base efectiva `relay_production`, versión 0.1.0, UI y `/up` responden HTTP 200.
- Tras recrear todos los contenedores usando la imagen realmente construida desde
  Git, persisten un registro de prueba en PostgreSQL, un archivo cifrado de
  almacenamiento y la huella de configuración. El archivo sigue descifrando con
  las mismas claves. `BUILD_COMMIT_SHA` coincide y telemetría sigue desactivada.
- Puerto de validación local 127.0.0.1:32002; el YAML entregado expone 3002.
- `git diff --check` pasa. No cambia código Rails ni migraciones: la suite completa
  y CI verdes del código fijado siguen siendo la referencia de comportamiento.

El ensayo arranca Rails y prepara únicamente una base local nueva, autorizado
por la petición de instalación y validación del despliegue. No se opera TrueNAS,
Sure ni datos reales. Los contenedores del ensayo se detienen al terminar,
conservando volúmenes y logs en `tmp/`. Se prueba recreación, no una migración
futura de esquema ni restauración de la base Sure. La importación completa sigue
requiriendo comprobar cifrado/almacenamiento del origen antes de reemplazar datos.

Mantener por fase una lista de archivos afectados, resultados, riesgos,
compatibilidad y forma de revertir. La migración termina cuando cada referencia
activa a Sure esté sustituida o tenga una razón documentada para permanecer:
historia, licencia, migración histórica o compatibilidad temporal.
