# API completa y MCP propio de Relay: análisis por fases

Fecha: 21 de octubre de 2026. Base inspeccionada: `main`, commit `b7834d24d`,
sin divergencia respecto de `origin/main` tras fetch. Fases 0–1 implementadas y
validadas el mismo día por autorización de Steve, incluido commit/push a `main`.
Las fases 2–9 están preparadas en el árbol de trabajo por autorización de Steve,
pendientes de confirmación para commit/push. La implementación y las verificaciones
de repositorio están completas; queda la comprobación final de la instalación de
fase 9 después del despliegue. No se ha desplegado ni modificado TrueNAS.

## Estado de ejecución — 21 de octubre de 2026

| Fase | Estado | Resultado concreto |
| --- | --- | --- |
| 0 | Completada | [Matriz de capacidades y contratos](relay-api-capability-matrix.md), 539 rutas propias y 164 fuentes de controladores/concerns en [inventario regenerable](relay-api-surface.json); fuentes, campos permitidos, autoridad, efectos, jobs, fases y exclusiones de presentación documentados |
| 1 | Completada | `Api::Access`/`Api::Input`, contexto API y capacidades por cuenta; ámbitos y permisos corregidos, referencias validadas, decimales/fechas y errores compatibles; OpenAPI y regresiones |
| 2 | Implementada y validada, sin publicar | MCP opt-in, catálogo acotado, transporte 2025-11-25/2026-07-28, OAuth con recurso y PKCE, cliente oficial por HTTP |
| 3 | Implementada y validada, sin publicar | Operaciones compartidas API/MCP de cuentas, movimientos, lotes, divisiones, protección, transferencias y organización |
| 4 | Implementada y validada, sin publicar | Informes nativos, comparativas, categorías, gastos compartidos, series, rentabilidad, previsiones y CSV filtrado |
| 5 | Implementada y validada, sin publicar | Presupuestos y rollover; Agenda y ocurrencias; Goals, compromisos, conciliación y consumo |
| 6 | Implementada y validada, sin publicar | Trades, holdings, coste base/remapeos, conciliación, valor gestionado y precios/FX locales con autoridad de instancia |
| 7 | Implementada y validada, sin publicar | Reglas con previsualización, importación y bloques, originales, Vault/adjuntos y backups/restauración |
| 8 | Implementada y validada, sin publicar | Integraciones bancarias/Drive, administración, acceso, seguridad y seguimiento de trabajos; presencia humana explícita para credenciales y consentimiento |
| 9 | Código y paridad validados; instalación pendiente | Auditoría de 44 casos/244 herramientas, API/MCP compartidos, cliente oficial, límites y procedimiento de publicación; TLS/proxy MCP final pendiente del despliegue |

### Entrega de fases 8–9

El [contrato de integraciones y administración](../api/integrations-administration.md)
añade **60 herramientas** y el cierre de paridad otras **8**, para un catálogo de
**244 herramientas y rutas API fijas**. El [manifiesto de cobertura](relay-api-mcp-coverage.yml)
relaciona los **44 casos originales** con operaciones, evidencia y **11 límites**
de presencia humana, presentación o exclusión. La auditoría automática comprueba
catálogo, rutas, implementación, esquemas OpenAPI y disposición de cada caso.

Se conserva el aislamiento familiar y de cuentas; compartición, roles y ajustes
sensibles requieren previsualizaciones firmadas. Los trabajos delegados vuelven
a validar identidad, credencial y permisos. Banco y Drive conservan sus guardas
de acceso externo; credenciales, MFA y consentimiento requieren el flujo humano
nativo. No se expone como limpieza inocua el borrado global heredado de precios/FX.
Los resultados de escritura mayores de 256 KiB revierten dominio y registro de
idempotencia juntos. Hay cobertura de reintentos compartidos entre REST y MCP.

Verificación de esta entrega (Docker Linux aislado):

- Suite Rails completa: **5.634 pruebas, 25.756 aserciones, 0 fallos,
  0 errores y 38 omisiones existentes**, 139,47 segundos, cuatro procesos.
- RuboCop: **1.832 archivos sin infracciones**; ERB lint correcto; Biome:
  131 archivos correctos; Brakeman: cero avisos activos, cinco exclusiones previas.
- OpenAPI: **1.523 ejemplos documentales en dry-run**, sin fallos. Inventario:
  **794 rutas y 171 fuentes**, comprobación de regeneración y cumplimiento API correctos.
- Auditoría: **44 casos, 244 herramientas, 244 rutas y 11 límites**, sin huecos
  de disposición; complementa las pruebas de comportamiento y no certifica producción.
- Cliente oficial TypeScript **1.32.1**, HTTP/OAuth: catálogo de 244 herramientas,
  validación de salidas y flujos previos más perfil, preferencias, seguridad,
  integraciones, transferencias y Sankey. Probe local de discovery/PKCE/challenge/
  Origin y handshake autenticado: **1 prueba, 6 aserciones, sin fallos, errores
  ni omisiones**. El HTTP de loopback no certifica TLS público.
- `git diff --check` correcto. Sin cambios de interfaz en estas fases.

El [procedimiento de publicación](../api/mcp-release.md) incluye el probe de lectura,
TLS/proxy, configuración, revocación y recuperación. Steve indica que el destino
es `https://relay.n7core.com/mcp` y que esta versión aún no está desplegada.
El 21 de octubre, Windows obtiene **HTTP 404 por HTTPS** en esa ruta; el probe
desde Docker no puede resolver el dominio. Estos resultados no validan MCP en
producción: la comprobación completa queda para después del despliegue autorizado.
Sin nuevas migraciones en fases 8–9, dependencias del producto, commit/push o
cambios de instalación. La migración aditiva de fase 2 sigue pendiente de despliegue.

### Entrega de fases 6–7

El [contrato de inversiones y procesos](../api/investment-processes.md) añade
**24 operaciones de inversión y 54 de procesos**. El catálogo suma **176
herramientas**, compartidas con rutas fijas API. Se conservan los motores nativos,
signos, comisiones, rendimiento gestionado, tipos de inversión, tracking y fiscalidad.
La escritura de precios/FX compartidos exige super_admin de instancia; la lectura
de precios está limitada a valores vinculados a cuentas accesibles.

La ejecución de reglas está acotada a 100 coincidencias y requiere una
previsualización firmada con versiones. Importaciones y reversiones usan el lector,
las filas/mappings, los jobs y la recuperación nativos, con previsualizaciones ligadas
al estado del destino. La restauración exige snapshot íntegro y destino sin datos
financieros. Los procesos familiares requieren administración y visibilidad completa;
una credencial de escritura requiere también permisos financieros en todas las cuentas.

El canal de bytes valida SHA-256, limita staging a 100 MiB y vincula referencias
al actor durante una hora. Descargas siempre autenticadas; no se exponen enlaces
portadores de almacenamiento. Se conservan originales y se limpian archivos sin
adjuntar. Se resolvió la lectura anticipada de adjuntos NDJSON dentro de la
transacción de idempotencia, con limpieza de bytes si hay rollback.
Los trabajos delegados vuelven a comprobar usuario, credencial y permisos al
ejecutarse; revocaciones o pérdida de acceso detienen trabajo aún pendiente sin
convertir datos ya comprometidos en una importación repetible.

Verificación de esta entrega (Docker Linux aislado):

- Suite Rails completa: **5.607 pruebas, 25.453 aserciones, 0 fallos,
  0 errores y 38 omisiones existentes**, 109,92 segundos, cuatro procesos.
- RuboCop: **1.818 archivos sin infracciones**; ERB lint correcto, Biome:
  131 archivos correctos, Brakeman: cero avisos activos y cinco exclusiones previas.
- OpenAPI: **1.183 ejemplos documentales en dry-run**, sin fallos. Inventario:
  **726 rutas y 171 fuentes**, con `--check` correcto. Cumplimiento API correcto:
  specs con `X-Api-Key`, solo documentales y controllers con Minitest.
- Cobertura de signos/comisiones, remapeos con colisión, FX/precios y autoridad
  de instancia, valor gestionado, rollback, tokens de subida, originales,
  previsualizaciones obsoletas, importación/reversión y restauración sintética.
  Trabajos delegados: clave/token revocado, scope reducido, cuenta privada y
  recuperación de una importación ya comprometida.
- Cliente oficial TypeScript **1.32.1**, Streamable HTTP/OAuth: recorrido de
  las **176 herramientas**, compra/borrado de trade, reglas, previsualización de
  importación y subida/descarga de original por el canal MCP, además de los flujos
  anteriores. **1 prueba, 3 aserciones, sin fallos, errores ni omisiones**;
  validación de esquemas de salida y comparación de los bytes descargados.
- `git diff --check` correcto. Sin cambios de UI ni pruebas de sistema nuevas.

Estas fases no añaden migraciones ni dependencias del producto. No se ha hecho
commit/push, ejecutado migraciones en la instalación del usuario ni modificado TrueNAS.

### Entrega de fases 4–5

El [contrato de informes y planificación](../api/reporting-planning.md) detalla
11 consultas financieras y 39 operaciones de planificación nuevas, compartidas
por API y MCP. El catálogo suma **98 herramientas**. Se reutilizan los motores
de la web, sus importes, monedas, permisos y máquinas de estado. La selección de
cuentas distingue visibilidad, participación financiera y tratamiento fiscal.

Presupuestos conserva propiedad/compartición y el orden de bloqueos del rollover.
Agenda comprueba ambos extremos e historial de transferencias y confirma sin
duplicados. Goals mantiene preview, cuentas autorizadas, compromisos históricos,
consumo y reclamación única de ingresos; manual_save conserva la conciliación
por valoración. No se añaden migraciones ni dependencias del producto.

Verificación de esta entrega (Docker Linux aislado):

- Suite Rails completa: **5.578 pruebas, 25.164 aserciones, 0 fallos,
  0 errores, 38 omisiones**, 126,40 segundos.
- RuboCop: **1.802 archivos sin infracciones**; ERB lint correcto, Biome:
  131 archivos correctos y Brakeman sin avisos activos.
- OpenAPI: **784 ejemplos documentales en dry-run**, sin fallos. Inventario:
  **644 rutas y 168 fuentes**, con `--check` correcto. Cumplimiento API correcto.
- Cliente oficial TypeScript **1.32.1** por HTTP/OAuth: catálogo de 98
  herramientas, informes, presupuestos, confirmación/retractación de Agenda y
  Goals, además del recorrido anterior. **1 prueba, 3 aserciones, sin fallos,
  errores ni omisiones**. El cliente valida los esquemas de salida MCP.

Permanecen pendientes la confirmación de commit/push y el despliegue; no se ha
modificado ni activado MCP en TrueNAS. La paridad global se cierra en fase 9.

### Entrega de fases 2–3

El [contrato MCP y de operativa cotidiana](../api/mcp.md) registra activación,
audiencia OAuth, clientes permitidos, política de delegación y límites. Hay
48 herramientas y rutas fijas `/api/v1/actions/<nombre>` sobre
`Api::DailyOperations`; la API anterior conserva sus formatos e imports CSV.
El registro `Api::Operation` hace atómicas las escrituras y sus resultados,
con reintentos/fingerprint por actor. Borrados por lote requieren previsualización
firmada y comprobación de versiones, y no incluyen restauraciones o borrado familiar.

La migración `20261021120000` está preparada. PKCE ya estaba declarado en
Doorkeeper, pero faltaban sus columnas: la migración las añade junto a audiencia
y registro de operaciones. Solo se ha verificado en la prueba de actualización
de esquema aislada. No se han ejecutado migraciones en la instalación del usuario.

Verificación de esta entrega (Docker Linux aislado):

- `bin/rails test`, cuatro procesos: **5.563 pruebas, 24.968 aserciones,
  0 fallos, 0 errores, 38 omisiones existentes**, 101,60 segundos.
- RuboCop: **1.796 archivos sin infracciones**. ERB lint correcto;
  Biome: 131 archivos correctos; Brakeman sin avisos activos y las exclusiones previas.
- OpenAPI regenerado: **534 ejemplos documentales en dry-run**, sin fallos;
  inventario: **594 rutas y 168 fuentes**, con `--check` correcto; cumplimiento
  API: claves `X-Api-Key`, specs sin aserciones y Minitest para todos los controllers.
- Cliente objetivo: **SDK oficial TypeScript `@modelcontextprotocol/sdk` 1.32.1**,
  Streamable HTTP `2025-11-25`, servidor temporal Capybara/Puma y base `relay_test`.
  Token OAuth con audiencia MCP; recorrido de catálogo paginado, contexto, alta
  con reintentos concurrentes, división y borrado. Prueba real: 1 prueba,
  3 aserciones, sin fallos, errores ni omisiones.
  El protocolo `2026-07-28` se verifica por integración, separado del handshake
  anterior; no se atribuye esa versión al cliente oficial probado.
- Consentimiento OAuth, S256, recurso, canje, renovación, revocación, Origin,
  credenciales inválidas, aislamiento y denegación por permisos: Minitest.

No se ha publicado, desplegado ni activado MCP en TrueNAS. La compatibilidad
de otros clientes y el cierre de paridad global siguen en las fases de dominio/9.

La fase 1 incorpora:

- `GET /api/v1/context` con identidad/scopes/capacidades; el campo MCP permanece
  false. Las cuentas añaden capacidades read/annotate/write sin retirar campos.
- Transacciones: lectura por cuenta autorizada, distinción entre anotación y
  escritura financiera, control de ambos extremos de transferencias y ocultación
  de su contrapartida cuando no es accesible.
- Trades y valoraciones: listado/detalle/alta/cambio/borrado según las acciones
  existentes, con ámbito de cuenta y permiso de escritura donde corresponde.
- Categorías/tags/comercios relacionados validados antes de guardar; datos de otra
  familia o no disponibles no producen mutaciones parciales.
- Importaciones/sesiones, inicio de sync familiar y estado de conexiones exigen
  administrador además del scope; el historial de otros miembros no revela jobs
  familiares/proveedor ni parent IDs/hijos privados. Backups mantienen su gate.
- Insights limitados a preview y visibilidad completa del feed familiar; tipos
  Bills retirados excluidos. Detalle de presupuesto con viewer autenticado.
- Contexto API independiente del navegador y sin fallback de un Bearer inválido
  a otra credencial. Respuestas privadas/no-store. Decimales finitos sin float y
  fechas ISO en transacciones/trades/valoraciones revisadas; códigos de conversión
  añadidos conservando el error heredado.

El [contrato de acceso para clientes](../api/access.md) explica las restricciones
y su transición. No cambian los scopes ni formatos de las credenciales existentes.
La idempotencia ampliada/fingerprint y el seguimiento uniforme de operaciones
continúan asignados a las fases 3/7 y 2/dominio respectivamente: F1 documenta y
preserva los contratos actuales, no los anuncia como sustituidos. La autorización
OAuth propia de MCP y su consentimiento/audiencia siguen en F2.

### Verificación de esta entrega

- Rails completo (`bin/rails test`, Docker Linux aislado, cuatro procesos):
  **5.536 pruebas, 24.634 aserciones, 0 fallos, 0 errores, 38 omisiones**;
  110,27 segundos. No se añaden omisiones.
- RuboCop: 1.782 archivos, sin infracciones. ERB lint correcto. Biome: 131
  archivos correctos. Brakeman: cero avisos activos, cinco exclusiones existentes.
- OpenAPI regenerado con `RAILS_ENV=test bundle exec rake rswag:specs:swaggerize`:
  294 ejemplos documentales en dry-run, sin errores de generación; no se usa como
  sustituto de Minitest ni como validación de ejecución de sus ejemplos.
- Inventario regenerado y `--check` correcto: 539 rutas/164 fuentes. Verificador
  API con `--compliance`: specs con API key y sin aserciones; todos los controllers
  API cuentan con archivo Minitest. `git diff --check` correcto.

Las primeras ejecuciones detectaron mensajes heredados que debían conservarse y
el requisito arquitectónico de usar `current_resource_owner` en controladores
API. Se corrigieron sin debilitar los límites. La única ampliación explícita del
bridge de sesión permitida por su prueba es borrar una identidad web heredada
antes de autenticar, sin leerla para autorizar. El modelo de acceso recibe la
identidad API; el bridge `Current.session` sigue sirviendo al dominio existente.

La suite completa también reprodujo un fallo previo, de forma aislada, en la
prueba histórica de previsiones: el ejemplo de diez días antes del cutoff podía
caer en un mes parcial que el motor no consume. Se situó el ejemplo en un mes
familiar completo y se añadió la comprobación de que efectivamente participa.
No se cambia el motor de previsiones. La ejecución completa final está en verde.

No se ejecutan migraciones, servidores de desarrollo ni despliegues. Sin nuevas
dependencias o cambios de esquema. La interfaz web no cambia; las verificaciones
son de API, dominio y contratos, sin nuevas pruebas de sistema de UI.
Evidencia local no versionada: `tmp/mcp-phase1-full-suite.log`,
`tmp/mcp-phase1-checks.log`, `tmp/mcp-phase1-openapi.log`,
`tmp/mcp-phase0-inventory.log` y `tmp/mcp-phase0-inventory-final.log`.

## 1. Objetivo y definición de cobertura completa

Convertir la API en una interfaz completa del producto mantenido de Relay y
construir un MCP propio que permita a asistentes externos consultar y ejecutar
sus operaciones con los permisos de la persona que los autoriza.

La unidad de cobertura será un caso de uso completo, no una tabla ni una ruta
HTML. «Confirmar un pago previsto», por ejemplo, incluye validación, creación o
vinculación del movimiento, protección contra duplicados, recálculo y consulta
del resultado. Exponer solo el registro del pago no completa esa capacidad.

La API debe cubrir toda operación relevante del producto. El MCP debe poder
representar esas capacidades, con acceso condicionado por identidad, permisos,
configuración de instancia y funcionalidades preview. La administración sensible
también necesita una decisión explícita de exposición; no se confunde cobertura
con conceder todos los permisos a cualquier cliente.

No se consideran capacidades pendientes los componentes retirados del producto:
chat integrado, proveedores LLM, embeddings, extracción PDF automática, Bills,
conectores retirados, proveedores de precios/FX, SaaS o almacenamiento remoto.
Crear el MCP es una nueva decisión de producto sobre acceso externo, no la
restauración automática de esos módulos ni de sus persistencias.

## 2. Evidencia y límites del análisis

El análisis inicial inspeccionó rutas, controladores API y web relevantes, permisos de
cuentas, serialización de transacciones y guías de arquitectura, efectos
financieros, Goals, clientes y consistencia API. Era una revisión estática; las
fases 0–1 añaden el inventario detallado y la verificación descritos arriba. La
tabla siguiente conserva la foto funcional inicial para orientar fases futuras;
el estado de permisos y contratos vigente está en la matriz de capacidades.

Fuentes locales principales:

- `config/routes.rb` y `app/controllers/api/v1/`.
- `app/models/current.rb`, `app/models/account.rb` y
  `app/controllers/concerns/account_authorizable.rb`.
- `app/controllers/transactions_controller.rb`, `scheduled_payments_controller.rb`,
  `goals_controller.rb`, `reports_controller.rb` e `investment_values_controller.rb`.
- `docs/llm-guides/architecture.md`, `financial-effects.md`, `goals.md`,
  `api-endpoint-consistency.md`, `docs/clients.md` y `docs/product-scope.md`.

### Cobertura inicial observada

| Área | API actual | Brecha para completar el producto |
| --- | --- | --- |
| Identidad y contexto | Login, refresh, SSO, ajustes familiares de lectura, uso de credencial | Contexto del actor, permisos efectivos, capacidades, ajustes y seguridad con alcance definido |
| Cuentas | Listado y detalle | Alta y edición por tipo, tratamiento financiero/fiscal, propietario, compartición, archivo, activación, cuenta predeterminada, desvinculación y borrado |
| Transacciones | Listado, detalle, alta, edición y borrado; idempotencia parcial de creación | Paridad de campos y búsqueda, divisiones, lotes, adjuntos, duplicados, desbloqueo, conversión a trade y vínculos con Agenda |
| Transferencias | Lectura de transferencias y decisiones rechazadas | Crear, editar, deshacer, emparejar movimientos existentes, rechazo y etiquetas; permisos sobre ambos extremos |
| Categorías y comercios | Lectura y creación | Edición, borrado, sustitución, fusión y jerarquía; logos propios donde corresponda |
| Etiquetas | CRUD | Verificar semántica, asignación por lotes y permisos consistentes |
| Presupuestos | Lectura de presupuestos y categorías; actualización de rollover al consultar categorías | Edición, asignaciones, movimiento de fondos, copia de mes, rollover y compartición |
| Goals y compromisos | Sin rutas API | Ciclo completo, cuentas vinculadas, proyección, compromisos, conciliación y consumo parcial |
| Agenda | Sin rutas API | Pagos programados, ocurrencias, confirmar, rechazar, restaurar, retractar, omitir y ejecución |
| Inversiones | Trades CRUD; posiciones, valores y precios en lectura | Edición de posiciones/coste base, remapeo, desbloqueos, valor de cartera gestionada, rentabilidad y series |
| Valoraciones y saldos | Saldos de lectura; valoraciones de lectura, alta y edición | Borrado, conciliación completa, restricciones por cuenta y distinción frente a valor de cartera gestionada |
| Informes | Cash flow/Sankey y balance patrimonial | Actividad, gastos compartidos, ahorro ajustado, comparativas, inversión, previsiones y exportaciones con paridad web |
| Reglas | Lectura de reglas e historial | Alta, edición, borrado, previsualización y ejecución con resultados consultables |
| Importaciones | Listado, detalle, filas, creación, preflight y sesiones por bloques/publicación | Paridad de formatos, configuración, mappings, corrección, plantillas, cancelación, reversión y seguimiento |
| Documentos | Sin rutas API de Statement Vault o adjuntos de transacciones | Subida, descarga autorizada, metadatos, vinculación, rechazo y eliminación; sin reintroducir extracción IA |
| Backups | Crear, listar, consultar y descargar backup familiar, restringido a admin | Cancelación, eliminación y restauración del producto soportado con informe de validación |
| Sincronización | Inicio familiar, historial y estado de conexiones | Recálculo por cuenta, cancelación y ciclo de conexiones Enable Banking con autorización bancaria humana |
| Drive y logos | Sin administración API completa | Conexión, estado, exportaciones programadas y ejecución respetando ExternalAccess |
| Usuarios y administración | Autenticación y algunas acciones de cuenta propia | Perfil/preferencias, invitaciones, roles, seguridad, sesiones, configuración, diagnósticos y trabajos según autoridad |
| MCP | Ausente | Transporte, autenticación, contratos de herramientas, configuración y pruebas propias |

No se asigna un porcentaje de cobertura: sin inventario de casos de uso y campos,
contar endpoints daría una precisión ficticia.

### Discrepancias iniciales resueltas en fase 1

1. `TransactionsController#set_transaction` en API usa cuentas accesibles para
   lectura, edición y borrado. En la web, `permitted_entry_params` distingue
   anotación de edición financiera. Un scope de token `read_write` no sustituye
   ese permiso sobre la cuenta.
2. `TradesController` API lista/busca con `family.trades.visible` y crea sobre
   `family.accounts.visible`; `visible` no demuestra autorización del actor.
3. `ValuationsController` API limita el listado a cuentas accesibles, pero su
   búsqueda de detalle/edición y el alta usan relaciones familiares sin el mismo
   filtro explícito de cuenta.
4. Hay rescates generales que pueden convertir errores de entrada o de búsqueda
   en `500`, y filtros monetarios que pasan por `to_f` en transacciones.
5. El scope `read_write` de una credencial y el permiso `read_write` de una cuenta
   representan cosas distintas: este último permite anotar, no cambiar importes.
6. La lectura de categorías presupuestarias puede materializar rollover. Debe
   documentarse ese efecto derivado y limitarse al ámbito autorizado.

Estas observaciones motivaron las regresiones de fase 1 y sus correcciones; los
flujos futuros deben mantenerlas. La cobertura incluye contrapartidas,
serializadores y agregados: ocultar un recurso en su listado no basta si otro
endpoint revela sus datos. Los detalles de rollover y presupuestos compartidos
permanecen documentados como efectos nativos, no como permisos de escritura sobre
las cuentas subyacentes.

## 3. Arquitectura propuesta

```text
Web / PWA ── controlador HTML ─┐
                             │
Clientes ─── API REST ────────┼── operaciones y consultas de dominio de Relay
                             │        │
Asistentes ─ MCP /mcp ────────┘        ├── permisos del actor y familia
                                      ├── modelos / concerns / POROs
                                      └── transacciones, jobs y recálculo
```

Se propone alojar el MCP en el mismo Rails y despliegue de Relay. API y MCP
invocarán las mismas operaciones de dominio; el MCP no hará peticiones HTTP al
propio servidor ni ejecutará controladores web. La web reutilizará esas
operaciones cuando haya lógica compartida que extraer.

La extracción será incremental, dentro de modelos, concerns y POROs próximos al
dominio. No se propone una segunda aplicación financiera, una reescritura general
ni un directorio genérico de servicios. Tampoco convertir automáticamente cada
acción de OpenAPI en una herramienta: las herramientas necesitan nombres,
descripciones, límites y resultados adecuados a cada tarea.

El MCP tendrá un catálogo explícito de herramientas, sin descubrimiento dinámico
de clases. Sus adaptadores no contendrán reglas de saldo, presupuesto, permisos
o rentabilidad. La API seguirá siendo utilizable por clientes convencionales sin
dependencia de MCP.

### Contratos transversales

- **Identidad:** `Current.user` y `Current.family` derivados de la credencial;
  contexto nuevo por petición, sin heredar impersonación del navegador. Un
  `family_id` enviado por el cliente no cambia la familia autorizada.
- **Permiso efectivo:** intersección de rol, permiso sobre cada recurso, permiso
  de credencial/cliente y gates de funcionalidad. Distinguir ver, anotar,
  escribir finanzas, compartir, exportar y administrar.
- **Compatibilidad:** ampliar v1 de forma aditiva y conservar contratos Android,
  OAuth, importación e idempotencia existentes. Cambios incompatibles necesitan
  un contrato versionado y transición; no una v2 completa por defecto.
- **Dinero:** decimales exactos o unidades menores según contrato, moneda
  explícita, sin cálculos con float. Conservar campos heredados de v1. Separar
  importe contable, dirección del flujo y valor absoluto de una valoración.
- **Semántica financiera:** exponer naturaleza, comportamiento de previsión,
  estado contabilizado/pendiente, exclusión analítica, protección de importación,
  tratamiento de cuenta y gasto compartido como conceptos independientes.
- **Lecturas financieras:** reutilizar motores actuales, incluido
  `Reports::Activity`, cash flow y previsiones; declarar período, zona horaria,
  moneda, ámbito, fecha del dato y estado del recálculo. FX o precios ausentes
  producen datos insuficientes explícitos, nunca paridad ficticia o totales
  aparentemente completos.
- **Escrituras:** atomicidad de cada operación, validación de referencias dentro
  del ámbito, idempotencia ante reintentos y control de versiones/conflictos donde
  haya edición concurrente. Una clave repetida con contenido distinto se rechaza.
- **Asincronía:** separar escritura guardada de saldo recalculado. Devolver un
  identificador de trabajo/operación y estado consultable en tareas largas;
  cancelar solo cuando el motor lo permita y sin prometer rollback del trabajo
  ya aplicado. No construir un segundo planificador.
- **Errores:** códigos estables de validación, permiso, conflicto, límite,
  funcionalidad deshabilitada, conversión ausente y fallo operativo. La API usa
  HTTP y el MCP los traduce a errores de protocolo o de herramienta según caso.
- **Trazabilidad local:** actor, cliente/credencial identificados sin secretos,
  acción, recursos, estado y correlación de petición/job. `DebugLogEntry.capture`
  para fallos relevantes; no registrar originales ni tokens en logs.

## 4. Fases de ejecución

Cada fase de dominio entrega API, documentación, pruebas y herramientas MCP
correspondientes una vez disponible el transporte. No se deja todo el MCP para
después de terminar la API. Las fases son unidades de producto, no necesariamente
un único commit.

### Fase 0 — Inventario verificable y contrato del producto

**Estado:** completada. Entregados la matriz funcional, el contrato de autoridad,
el inventario regenerable y la actualización de documentación vigente.

**Trabajo:** recorrer las acciones web, campos permitidos, modelos, jobs y
serializadores. Registrar cada caso de uso con rol, permisos de cuenta, gates,
efectos financieros, asincronía, endpoint y herramienta prevista. Separar funciones
de usuario, familia e instancia; clasificar acciones puramente visuales.

Actualizar documentación contradictoria: `wealth-agent-harness.md` y su entrada
en el índice aún hablan de herramientas integradas retiradas. Registrar esta nueva
decisión en alcance/arquitectura y en el mapa de preservación sin alterar las
crónicas históricas como si fueran documentación del presente.

**Cierre:** matriz exhaustiva revisable y contrato de acceso aprobable; cada
función tiene entrega asignada o exclusión justificada. Incluir los tipos de
cuenta y variantes de inversión, no solo el caso de cuenta corriente.

### Fase 1 — Permisos y fundamentos de la API existente

**Estado:** completada y validada. Véanse resultados, compatibilidad y límites
del apartado de ejecución; no incluye el transporte de la fase 2.

**Trabajo:** reproducir las discrepancias identificadas con Minitest y corregir
los ámbitos de lectura, anotación, escritura, borrado y relaciones. Revisar
invitados, cuentas privadas/compartidas, presupuestos personales/compartidos,
exportaciones, sincronización, contrapartidas y usuarios desactivados.

Introducir contexto/capacidades consultables y contratos comunes de errores,
cantidades y fechas. Definir delegación acotada para MCP: la credencial nunca
amplía al usuario. Conservar credenciales v1 existentes; añadir restricciones
mediante una transición explícita, sin reinterpretarlas silenciosamente.

**Cierre:** un cliente con clave de escritura no puede modificar una cuenta que
solo ve o anota; tampoco puede acceder por ID a una cuenta privada de otro miembro
de la misma familia. Pruebas de otra familia, usuario inactivo, gates y referencias
cruzadas. Corregir estos fallos antes de exponer las mismas acciones por MCP.

### Fase 2 — MCP mínimo utilizable e identidad delegada

**Trabajo:** endpoint `/mcp`, transporte Streamable HTTP, validación de mensajes,
versiones, autenticación, listado y ejecución de un conjunto inicial de consultas:
contexto, cuentas, búsqueda de movimientos, cash flow y estado de operaciones.
Catálogo determinista y contratos estructurados de entrada/salida; paginación y
límites de respuesta, sin recortes silenciosos.

Evaluar el SDK Ruby disponible frente a un adaptador pequeño con pruebas de
conformidad; justificar cualquier dependencia. Usar Doorkeeper como base para
OAuth, verificando qué falta para cumplir MCP: discovery, PKCE, recurso/audiencia,
consentimiento, revocación y registro de clientes compatible. No dar por hecho
que el OAuth móvil actual cubre ese contrato. Una API key puede ofrecer un modo
explícito para clientes propios que admitan cabeceras; no equivale al flujo OAuth
estándar de interoperabilidad ni debe ser un token global ligado por variable a
un usuario fijo.

Añadir habilitación específica del MCP por instancia y control de clientes.
`ExternalAccess` regula hoy salidas bancarias/logos/Drive; no debe activar ni
desactivar accidentalmente el acceso entrante MCP. Habilitar MCP no habilita
proveedores ni reactiva IA integrada.

**Cierre:** conexión real con al menos un cliente objetivo y pruebas de protocolo,
caducidad/revocación, credenciales incorrectas, Origin, aislamiento entre
peticiones y denegación por herramienta. Cliente y versiones probadas quedan
documentados; no basta una llamada manual a `tools/call`.

### Fase 3 — Cuentas, movimientos y organización: operativa diaria

**Trabajo:** alta/edición de cuentas de todos los tipos mantenidos, archivo,
activación y cuenta predeterminada; completar parámetros y filtros de movimientos.
Categorías, comercios y etiquetas con sus ciclos de edición, sustitución y fusión.
Transferencias con creación, edición, emparejamiento, rechazo y desvinculación.

Divisiones, lotes, duplicados, protección/desbloqueo, conversión a trade y
etiquetado. Mantener las protecciones de hijos/padres de división y distinguir
borrado de transferencia de borrado de sus movimientos según la operación nativa.
No eludir controles de propiedad ni permisos sobre la segunda cuenta.

**Cierre:** administrar una cuenta y sus movimientos de principio a fin por API
y MCP; reintentar altas sin duplicados; dividir y revertir conforme al motor;
transferir en misma/distinta moneda sin alterar naturaleza ni reglas de frontera.

### Fase 4 — Informes y consultas financieras completas

**Trabajo:** actividad, comparativas, categorías, gastos compartidos y
liquidaciones, ahorro ajustado, series de saldo/patrimonio, rentabilidad y
previsiones. Completar filtros, exportaciones y frescura de datos. Exponer las
distinciones que la web ya utiliza: cuentas accesibles frente a cuentas incluidas
en las finanzas, inversión y tratamiento fiscal.

**Cierre:** misma consulta, usuario, período, moneda y estado de datos producen
los mismos resultados en web/API/MCP. Casos de FX ausente, pendientes, divisiones,
movimientos excepcionales, transferencias de frontera y gasto compartido; no
pedir al modelo que reconstruya los informes sumando movimientos.

### Fase 5 — Presupuestos, Agenda y Goals

**Trabajo:** presupuestos personales/compartidos, asignaciones, fondos, copia y
rollover. Agenda con reglas, ocurrencias y todas sus transiciones; proyección
por cuenta/patrimonio. Goals con altas/cambios/estados, cuentas vinculadas,
compromisos, renovación, conciliación, reapertura y consumo parcial.

Usar las máquinas de estado y reconciliadores existentes. Un compromiso de Goal
no es una transacción ejecutada ni una orden bancaria. Confirmar una ocurrencia
no puede crear dos movimientos al reintentarse.

**Cierre:** planificar un pago, confirmarlo o rechazarlo, consultar su efecto y
retractarlo según reglas; gestionar presupuesto y objetivo con permisos/gates,
rollover, vencimientos y matching preservados. Bills permanece retirado.

### Fase 6 — Inversiones, conciliación y datos locales de mercado

**Trabajo:** completar operaciones de inversión, holdings, coste base, remapeos
y desbloqueos; conciliaciones, borrado de valoraciones y actualización de valor de
cartera gestionada mediante `Investment::ValueUpdate`. Tipos de inversión,
tracking y fiscalidad con sus variantes mantenidas.

Definir operaciones para precios/FX manuales o importados, con ámbito de lectura
y escritura explícito: no asumir que una tabla global puede modificarse con una
credencial familiar. Reutilizar precios guardados y motores de rentabilidad;
ningún proveedor nuevo de cotizaciones/FX.

**Cierre:** compra/venta, posiciones y efectivo coherentes; reconciliación y valor
de cartera gestionada conservan su significado distinto. Aportaciones/retiradas
no se convierten en rendimiento ni se duplican en informes.

### Fase 7 — Reglas, importaciones, documentos y recuperación

**Trabajo:** ciclo completo de reglas y ejecución con alcance/previsualización.
Importaciones por formato con configuración, mappings, filas corregibles,
publicación, cancelación, reversión y sesiones por bloques. Manejar tamaños,
checksums, interrupciones, colisiones e idempotencia.

Statement Vault y adjuntos: subir originales, detectar duplicados, consultar
metadatos, vincular/desvincular/rechazar y descargar con autorización propia.
No copiar archivos completos al contexto del modelo por defecto. Dar a clientes
autorizados un canal de transferencia; si un enlace firmado actúa como credencial
temporal, explicitar caducidad y limitaciones de revocación.

Completar backups familiares: consultar, crear, cancelar, descargar, borrar,
validar y restaurar según el lector existente y su informe de omisiones. Separar
esto del backup de servidor de TrueNAS y del actualizador del host.

**Cierre:** importación con error y reintento sin duplicados; originales íntegros
y no accesibles desde otra identidad; exportación/restauración sintética con
valores y relaciones iguales. Restauraciones y operaciones masivas sensibles
requieren una previsualización concreta y autorización definida en fase 0.

### Fase 8 — Integraciones, familia, seguridad y administración

**Trabajo:** Enable Banking (conectar/seleccionar/vincular/reauthorizar/desvincular),
sincronización y recálculo por cuenta; estado, errores y cancelación. La
autorización bancaria se completa en el navegador/banco: el MCP inicia y consulta
el flujo, no sustituye el consentimiento ni realiza pagos bancarios inexistentes.

Drive, programaciones y exportaciones; logos y preferencias de acceso externo.
Perfil, idioma/moneda/zona horaria, miembros, invitaciones, roles, compartición
de cuentas/presupuestos. Seguridad: sesiones, revocación, claves y conexiones
con las restricciones de autoridad y reautenticación que correspondan.

Administración de instancia: configuración permitida, diagnóstico local y
trabajos. Exponer estado configurado/marcado y errores depurados; no devolver
contraseñas, secretos de proveedor, MFA ni tokens existentes. Acciones como
WebAuthn, MFA y consentimientos SSO necesitan interacción humana; las APIs deben
permitir comenzar/completar el flujo cuando proceda, sin fabricar la presencia
del usuario. No ofrecer SQL, shell, edición arbitraria de settings ni
impersonación genérica a un agente.

**Cierre:** capacidades de usuario/familia/admin separadas, controles de salida
respetados y navegación humana documentada. Cada operación administrativa de la
matriz tiene endpoint/herramienta autorizada o una limitación explícita revisada;
no se declara paridad completa ocultando este bloque.

### Fase 9 — Conformidad, cierre de paridad y despliegue

**Trabajo:** reconciliar inventario inicial con implementación y OpenAPI. Pruebas
integradas de flujos completos, clientes MCP reales, concurrencia, reintentos,
cancelación, caducidad, permisos cambiantes, límites y respuestas voluminosas.
Auditar operaciones masivas, exportación y administración con permisos mínimos.

Documentar habilitación, conexión de clientes, compatibilidad, revocación,
errores, recuperación y observación local. Verificar reverse proxy de la
instalación, TLS, timeouts y exposición elegida sin abrir puertos ni modificar
TrueNAS durante el desarrollo. Mantener rollback y compatibilidad de clientes.

**Cierre:** toda capacidad del producto tiene resultado trazable en la matriz,
pruebas y documentación; ninguna operación depende de automatizar HTML para
compensar una ausencia. API/MCP producen resultados equivalentes y denegaciones
consistentes. Despliegue y exposición de red se validan por separado del código.

## 5. Diseño específico de herramientas MCP

Nombres propuestos, sujetos al contrato de fase 0:

| Familia | Ejemplos |
| --- | --- |
| Contexto | `get_context`, `get_capabilities`, `get_operation` |
| Consulta financiera | `search_transactions`, `get_cash_flow`, `get_activity_report`, `get_wealth_forecast` |
| Operativa | `create_account`, `create_transaction`, `update_transaction`, `split_transaction`, `match_transfer` |
| Planificación | `update_budget_allocation`, `create_scheduled_payment`, `confirm_scheduled_entry`, `create_goal`, `record_goal_consumption` |
| Inversiones | `create_trade`, `reconcile_account`, `update_managed_portfolio_value` |
| Procesos | `preview_rule_run`, `apply_rule`, `start_import`, `publish_import`, `create_family_backup` |

Son herramientas de negocio concretas. Evitar `execute_sql`,
`update_any_record` o una herramienta universal con acciones abiertas. Agrupar
variantes solo cuando compartan validación y significado; no fragmentar cada
campo en una herramienta distinta. Mantener paginación del catálogo y datos,
descripciones concisas, esquemas estrictos y resultados estructurados.

Las anotaciones de lectura/escritura/destrucción ayudan al cliente a explicar
acciones, pero no autorizan su ejecución. El servidor vuelve a comprobar permisos
en cada llamada aunque la herramienta apareciera antes en el catálogo. Contenido
de notas, documentos y comercios es dato no confiable, nunca instrucciones para
el servidor; las herramientas no ejecutan texto como comandos ni aceptan URLs
arbitrarias para recuperar documentos.

Para acciones corrientes ya autorizadas, no introducir confirmaciones repetidas.
Para restauraciones, destrucción masiva o cambios sensibles de acceso, proponer
previsualización y ejecución ligadas al actor, operación, payload y versión de
datos, con caducidad y control de concurrencia. Un `confirm: true` escrito por
el modelo no demuestra una aprobación humana. El mecanismo exacto y la política
de delegación deben definirse antes de implementar esas operaciones.

No se requieren sampling, prompts remotos, memoria de agente ni persistencia de
conversaciones para ofrecer estas herramientas. Recursos MCP adicionales solo
cuando aporten una ventaja comprobada para los clientes elegidos.

### Protocolo y autenticación: evitar supuestos del MCP antiguo

La revisión oficial `2026-07-28` de MCP es stateless y cambia el transporte y
el ciclo de vida frente a `2025-11-25`: no debe imponerse el handshake o las
sesiones antiguas a un cliente nuevo. Antes de fijar compatibilidad se prueba
qué versiones hablan los clientes objetivo. Si hace falta soportar la revisión
anterior, se implementa y prueba un adaptador explícito, sin mezclar contratos.

La autorización actual contempla discovery de recurso protegido/servidor,
OAuth y validación del destinatario del token. El registro dinámico está
deprecado en esa revisión: no restaurar `/register` como requisito universal;
elegir registro previo, metadatos de cliente o compatibilidad heredada según
clientes reales y requisitos normativos. Recuperar la antigua documentación de
Sure no sustituye ese análisis.

Referencias oficiales consultadas el 21 de octubre de 2026:

- [Transporte Streamable HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http).
- [Autorización](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization).
- [Herramientas](https://modelcontextprotocol.io/specification/2026-07-28/server/tools).
- [Cambios de la revisión](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/changelog.mdx).

## 6. Validación, publicación y orden recomendado

En cada fase: Minitest de comportamiento y permisos, fixtures y pruebas de los
efectos financieros que cambien. Cada endpoint añadido/modificado tendrá rswag
solo documental, schemas reutilizables y regeneración de `docs/api/openapi.yaml`.
Mantener el patrón `X-Api-Key` exigido en esas pruebas/specs; verificar OAuth y
el transporte MCP con pruebas de integración separadas según sus contratos.

Para permisos: propietario, full_control, anotador read_write, read_only,
invitado, admin, otra familia, cuenta privada de la misma familia y usuario
desactivado. Verificar que un admin no obtiene automáticamente facultades
financieras distintas de las que establece Relay. Incluir datos derivados,
contrapartidas, archivos y trabajos; no solo CRUD principal.

Para integridad: signos, monedas de distinta precisión, FX/precio ausente,
pendientes, divisiones, concurrencia, import protection, gastos compartidos,
rentabilidad gestionada y estados de Agenda/Goals. Probar idempotencia concurrente
y cambios de permisos entre creación, ejecución y consulta de un trabajo.

Antes de cada push: `bin/rails test` completo y verificaciones aplicables del
repositorio. Trabajo directo en `main`; presentar resultados concretos y obtener
confirmación antes de commit/push. No crear ramas, worktrees ni PR sin excepción
expresa. No ejecutar migraciones ni modificar despliegues automáticamente.

Orden recomendado: **0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9**.
Primer hito utilizable: fase 2, MCP de consulta sobre base autorizada. Segundo:
fase 3, operativa diaria por API/MCP. Cierre de cobertura: fase 9; los hitos
anteriores no se presentan como «todo Relay».

El esfuerzo mayor está en cerrar contratos, permisos y flujos de la API,
especialmente importaciones, planificación y administración. El adaptador MCP es
solo una parte. Estimar fechas o número de herramientas antes del inventario y
de la prueba de compatibilidad produciría compromisos poco fiables.
