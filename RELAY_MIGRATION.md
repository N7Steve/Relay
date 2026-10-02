# Migración de Sure a Relay

Fecha de inicio: **2 de octubre de 2026**.

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

Los ejemplos apuntan hoy a `ghcr.io/we-promise/sure:stable`. Preparar imágenes y
chart propios antes de cambiar instrucciones de instalación. Revisar todos los
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

Las herramientas Rails/Bundler se ejecutan en Docker/Linux. La primera entrega
usa los proyectos Compose **`relay-unit-tests`** (suite completa final) y
**`relay-tests`** (sistema y comprobaciones), con `compose.test.yml` y
`docker/test.env`. Cada proyecto tiene su propia base; ambas conservan el nombre
interno `sure_test` para respetar el guard del runner. Así las ejecuciones no se
interfieren ni comparten el entorno `sure-tests` del origen. Este ajuste de
ejecución no cambia los scripts heredados, pendientes de la fase 3.

Desde la raíz de Relay, con Docker Desktop en contenedores Linux:

```powershell
# Suite completa sobre su propia base de pruebas.
docker --context desktop-linux compose --project-name relay-unit-tests --env-file docker/test.env --file compose.test.yml build runner
docker --context desktop-linux compose --project-name relay-unit-tests --env-file docker/test.env --file compose.test.yml up --detach --wait db redis
docker --context desktop-linux compose --project-name relay-unit-tests --env-file docker/test.env --file compose.test.yml run --rm runner unit

# Navegador, sobre otra base para evitar interferencias con la suite completa.
docker --context desktop-linux compose --project-name relay-tests --env-file docker/test.env --file compose.test.yml build runner
docker --context desktop-linux compose --project-name relay-tests --env-file docker/test.env --file compose.test.yml --profile browser up --detach --wait db redis selenium
docker --context desktop-linux compose --project-name relay-tests --env-file docker/test.env --file compose.test.yml --profile browser run --rm --use-aliases -e SELENIUM_REMOTE_URL=http://selenium:4444 -e CAPYBARA_APP_HOST=runner -e CAPYBARA_SERVER_PORT=3001 runner system test/system/onboardings_test.rb test/system/admin/system_health_test.rb

# Detener únicamente las pruebas de Relay, conservando sus volúmenes.
docker --context desktop-linux compose --project-name relay-unit-tests --env-file docker/test.env --file compose.test.yml down
docker --context desktop-linux compose --project-name relay-tests --env-file docker/test.env --file compose.test.yml --profile browser down
```

El entrypoint de pruebas crea/carga únicamente el esquema de su base aislada;
no aplica las migraciones históricas ni conecta con la instalación estable.

Antes de push, la suite completa `bin/rails test` debe pasar. Para futuros PRs,
cumplir además las pruebas de sistema aplicables, RuboCop, ERB lint, Biome y
Brakeman según [development.md](docs/llm-guides/development.md). Verificar build,
tokens, contratos y pruebas de compatibilidad según el área; registrar resultados
reales y distinguir pendientes. No ocultar fallos heredados como validación.

Validación completada el 2 de octubre de 2026:

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

Mantener por fase una lista de archivos afectados, resultados, riesgos,
compatibilidad y forma de revertir. La migración termina cuando cada referencia
activa a Sure esté sustituida o tenga una razón documentada para permanecer:
historia, licencia, migración histórica o compatibilidad temporal.
