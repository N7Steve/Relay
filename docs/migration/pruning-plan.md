# Plan de poda de Relay

Preparado el 4 de octubre de 2026 sobre
`1e279bd8f6fe05d295c074180efccbcd59195ad5`.
Base: [análisis de migración y poda](pruning-analysis.md).
Estado: fases 0, 1 y 2 completadas, validadas y publicadas en `origin/main`
el 4 de octubre de 2026. Evidencia y límites en los
[registros de fase 0](pruning-phase-0.md) y [fase 1](pruning-phase-1.md).
Fase 3 implementada y validada, sin publicar; fases 4–11 pendientes.

La petición autoriza preparar este plan. La selección de una fase autorizará
su implementación dentro del alcance descrito. Commit/push y operaciones sobre
la instalación siguen las reglas de [AGENTS.md](../../AGENTS.md).

## Objetivo y reglas de ejecución

Reducir Relay a un núcleo financiero self-hosted y curado, preservando exactitud,
Agenda, informes, inversiones, permisos, importaciones y recuperación de datos.
Cada fase produce una versión completa y utilizable: **se puede parar después de
cualquier fase sin necesitar la siguiente para arreglar la aplicación**.

- Cada fase incluye todos los consumidores afectados: modelo, controller/API,
  vistas, jobs, callbacks, dependencias, configuración, clientes, backups y docs.
  No dejar referencias rotas para que otra fase las quite después.
- Trabajar en `main`, preservar cambios existentes y preparar unidades pequeñas.
  No publicar una mitad de fase que requiera la otra para funcionar.
- No cambiar cálculos financieros por el mero hecho de eliminar un conector.
  No borrar datos, tablas, adjuntos ni migraciones históricas en fases de código.
- Mantener lectores históricos cuando sean necesarios para recuperación.
  El código del producto retirado queda recuperable en Git, fuera del runtime.
- Una puerta temporal tiene alcance completo y criterio de retirada. No basta
  ocultar navegación; tampoco crear un sistema de plugins para esta poda.
- La ejecución no exige implementar todas las fases. Las opcionales requieren
  una decisión funcional; pueden quedar excluidas sin bloquear el cierre.
- El informe de cada fase registra qué se conserva, elimina, suspende o convierte,
  archivos/contratos afectados, pruebas y limitaciones. Actualizar el mapa de
  preservación si cambia una decisión de producto.

## Orden y dependencias

| Fase | Resultado | Requiere | Prioridad |
| --- | --- | --- | --- |
| 0 | Referencia financiera y recuperación comprobables | — | Crítica |
| 1 | Backups preparados para retirar módulos | 0 | Crítica: base de todas las retiradas con datos |
| 2 | Cálculos locales separados de adquisición externa | 0–1 | Crítica: base de proveedores y automatismos |
| 3 | Telemetría y evaluaciones remotas retiradas | 0–2 | Alta; primera eliminación |
| 4 | Relay exclusivamente self-hosted, sin negocio SaaS | 0–2 | Alta |
| 5 | MCP y asistente externo retirados | 1–4 | Alta |
| 6 | IA integrada retirada, si se confirma ese alcance | 1–5 | Alta |
| 7 | Conectores no usados retirados por lotes independientes | 1–6, o IA conservada expresamente | Alta; mayor poda técnica |
| 8 | Bills retirado; Agenda como único dominio de pagos previstos | 1–7 | Alta; poda funcional |
| 9 | Extensiones restantes seleccionadas y reducidas | Bases 0–2 y módulos previos que afecten a cada extensión | Opcional por bloque |
| 10 | Esquema y datos residuales tratados | Retirada y estabilidad del módulo concreto | Última; operaciones persistentes |
| 11 | Cierre de soporte, documentación y métricas | Fases elegidas completadas | Cierre |

El orden de presentación es el recomendado. Una fase posterior solo puede
adelantarse si sus dependencias reales están resueltas y se registra el cambio.
Si se decide conservar IA, esa decisión satisface la selección de la fase 6:
no obliga a eliminarla para poder retirar conectores.

## Contrato de cierre común

Antes de declarar terminada una fase de código:

1. Arranque y eager loading correctos; assets e imagen de producción construidos.
2. Tests focalizados del comportamiento que cambia y del núcleo afectado; suite
   completa `bin/rails test` verde en Docker Linux antes de publicar. Ejecutar
   lint Ruby/ERB/JS, Brakeman y tests de sistema/clientes según el cambio.
3. Si cambia API v1: Minitest de comportamiento, rswag solo documental, OpenAPI
   regenerado y checklist de consistencia. Comprobar consumidores mantenidos.
4. Backup nuevo exportable/restaurable. Si cambian modelos, relaciones o datos:
   restaurar también un backup previo a la fase en un entorno aislado y verificar
   relaciones y originales, no solo conteos.
5. Ausencia de mutaciones o envíos del módulo retirado mediante rutas directas,
   API, webhooks, jobs nuevos/antiguos y callbacks. Gates con valores de producción,
   aunque los defaults de test sean distintos.
6. Comparación financiera sin divergencias no explicadas en cuentas/saldos,
   transferencias, inversiones, informes, Agenda y previsiones afectadas.
7. Configuración y UI coherentes: ninguna opción solicita activar algo ya retirado.
   No deshabilitar validaciones de recuperación o del núcleo para conseguir verde.
8. Resultado revisable con plan de reversión y requisitos de despliegue. Pruebas
   fallidas o pendientes significan fase preparada, no completada.

Para documentación/inventario no ejecutar suites sin necesidad; registrar las
comprobaciones que sí se hicieron. La exigencia de suite completa antes de push
sigue vigente. Referencias: [testing](../llm-guides/testing.md),
[Docker tests](../llm-guides/docker-tests.md) y
[verificación](../llm-guides/development.md).

La validación del despliegue real es un paso separado cuando se autorice:
backup de instalación previo, misma revisión web/worker, `/up`, login, navegación,
recálculo de cuenta manual, Agenda y exportación/descarga. No avanzar a otra
entrega operativa si esa revisión falla. No fijar una duración de observación
arbitraria: incluir al menos los recorridos y ciclos programados afectados.

## Fase 0 — Fijar la referencia y cerrar la foto de migración

**Propósito:** poder demostrar que la poda conserva lo que hoy funciona.

- Consolidar estados de migración incorporando las entregas posteriores de
  backups y hosting. Distinguir revisión de código de revisión desplegada.
- Preparar inventario de uso: conectores con datos, cuentas enlazadas, IA/MCP,
  Bills, Goals/presupuestos, Drive, SSO, clientes y almacenamiento activo.
- Definir referencia financiera privada: cuentas y tratamientos, saldos a fechas
  concretas, movimientos/transferencias, holdings, Agenda, informes y adjuntos.
  No guardar datos personales o credenciales en Git.
- Usar el backup de pruebas disponible o fixtures representativos para un ensayo
  de ida y vuelta. La lectura del destino y el backup real requieren acceso y
  autorización operativa; si faltan, preparar instrucciones y marcar ese paso
  pendiente sin inventar una verificación de producción.
- Recoger métricas iniciales reproducibles: dependencias, rutas, cron activos,
  código por módulo, duración de CI e imagen. No convertirlas en metas arbitrarias.

**Final estable:** comportamiento idéntico; referencia y pendientes documentados.
**Cierre:** recuperación ensayada en entorno aislado e inventario suficiente para
seleccionar la primera retirada. Un módulo con uso/datos desconocidos no se borra.
**Reversión:** solo documentación/artefactos de prueba; sin cambios persistentes.

## Fase 1 — Proteger backups y datos frente a la poda

**Propósito:** dejar de exigir la plataforma completa de Sure para recuperarse.

- Mapear cada modelo de `Family::Backup`, asociaciones/polimorfismo, STI,
  GlobalIDs y adjuntos que alcanzan los módulos candidatos.
- Establecer una disposición por módulo: lector mínimo de datos históricos,
  conversión comprobada al núcleo, o archivo recuperable con contenido/relaciones
  íntegros. La ausencia de uso no sustituye esa disposición.
- Adaptar el inventario de exportación/restauración con el mecanismo mínimo que
  necesite la primera retirada, conservando el formato actual cuando sea posible.
  No desarrollar un framework genérico de serialización o plugins.
- Si hace falta otro formato, versionarlo con lector explícito para el anterior.
  Probar rechazo claro de entradas realmente incompatibles, sin saltar registros
  desconocidos ni afirmar que una restauración parcial fue completa.
- Mantener la cobertura de tablas de familia y verificación de bytes/relaciones.
  Las adaptaciones concretas de cada módulo se completan en su fase de retirada;
  esta fase proporciona el contrato y la primera implementación comprobada.

**Final estable:** todas las funciones siguen disponibles y los backups existentes
siguen recuperables. No se borran clases de producto todavía.
**Cierre:** backup previo → restauración → reexportación → segunda restauración
con equivalencia del estado soportado y preservación explícita de datos retirables.
**Reversión:** código anterior si no se introdujo formato nuevo; si se introdujo,
documentar el lector mínimo que debe permanecer para leer backups nuevos.

## Fase 2 — Separar recálculo local y operaciones externas

**Propósito:** poder apagar conectores sin apagar la contabilidad de Relay.

- Separar materialización de saldos/holdings, matching y reglas de importación
  remota de movimientos, precios y divisas. Mantener los puntos de entrada de
  cuentas/entries y su procesamiento asíncrono.
- Preservar la estrategia actual de cuentas enlazadas al suspender su conexión.
  Pasarlas a manual requiere conversión y pruebas específicas en fase 7.
- Definir pocas capacidades coherentes para acceso externo, con valor apagado
  en instalaciones nuevas y activación explícita de las extensiones conservadas.
  Inventariar ajustes existentes: cambiar el default no cambia valores guardados.
- Cubrir login, cron, acciones manuales, API, webhooks y llamadas bajo demanda.
  Tratar precios/divisas y logos como capacidades separadas de bancos/IA.
- Evitar conversiones silenciosas a tipo 1 o valores de inversión engañosos al
  faltar datos: conservar datos históricos y ofrecer un estado explícito de
  información insuficiente o entrada manual donde haga falta.
- Hacer idempotente la reconciliación de cron persistidos. Conservar Agenda,
  limpieza de trabajos atascados y mantenimiento local.
- Definir transición para jobs retirables: dejar terminar/drenar de forma acotada
  o consumirlos como cancelados sin efectos. El arranque no debe fallar por clases
  desaparecidas; no purgar indiscriminadamente Redis ni la cola compartida.

**Final estable:** edición/importación manual recalcula correctamente; conexiones
retenidas funcionan si se activan; con capacidades externas apagadas no hay
solicitudes de esas capacidades desde servidor ni navegador.
**Cierre:** núcleo probado sin red externa, cron reconciliados tras reiniciar y
trabajos anteriores ensayados. No se retiran SDK/conectores todavía.
**Reversión:** código y configuración anteriores, incluyendo reconciliación de
cron; registrar preferencias alteradas. No hay conversión de cuentas en esta fase.

## Fase 3 — Retirar telemetría y evaluaciones remotas

- Sustituir referencias Sentry por logging/diagnóstico local apropiado.
- Retirar PostHog, Sentry, Skylight, Logtail y Langfuse, gems exclusivas,
  inicializadores, middleware, trazas, encuestas y variables sin consumidores.
- Retirar evaluaciones IA y sus tareas/configuración, sin eliminar todavía
  proveedores IA que continúan presentes hasta fase 6.
- Revisar clientes mantenidos y callbacks de errores para que sigan funcionando.

**Final estable:** misma aplicación financiera, sin esos SDK ni envíos, incluso
con variables heredadas configuradas. Errores siguen siendo diagnosticables.
**Cierre específico:** build/arranque de producción y recorridos de fallo;
IA conservada aún ejecutable con respuestas stub y sin instrumentación remota.
**Reversión:** revert de código/lockfiles; revisar que no reactive telemetría
inadvertidamente. Sin cambios de datos.

## Fase 4 — Retirar la plataforma comercial SaaS

- Establecer self-hosted como comportamiento propio, quitando modo managed,
  Stripe, suscripciones, trials, upgrade y webhooks comerciales.
- Revisar `Family::Subscribeable`, callbacks de borrado, onboarding, correo,
  sync y limpieza de familias dependiente de suscripción.
- Mantener familias, roles, permisos de cuentas, invitaciones y recuperación de
  acceso. No tratar multiusuario como una función comercial prescindible.
- Retirar SDK Stripe y su configuración; conservar tablas/datos históricos
  hasta la fase persistente correspondiente, con disposición en backup.

**Final estable:** instalación nueva y existente permite login/onboarding sin
suscripción; no existe lógica de caducidad comercial ni borrado por trial.
**Cierre específico:** alta, invitación, roles y destrucción explícita de familia
en tests sin llamadas Stripe; no ejecutar ese borrado sobre datos reales.
**Reversión:** código anterior y ajustes documentados; no se restauran cobros
automáticamente. Esquema compatible conservado.

## Fase 5 — Retirar MCP y el asistente externo

- Retirar `/mcp`, metadata/registro dinámico específicos, ajustes y transporte
  del asistente externo. Auditar funciones compartidas antes de eliminarlas.
- Conservar OAuth/Doorkeeper, API keys, autenticación y scopes necesarios para
  API y clientes actuales. No cambiar indiscriminadamente contratos nativos.
- Preservar conversaciones, documentos originales y backup; definir el estado
  local del historial de asistente externo hasta la retirada IA posterior.
- Retirar jobs exclusivos y resolver tokens/colas del módulo con el inventario
  previo; no revocar tokens de clientes distintos.

**Final estable:** MCP y asistente externo no accesibles; web, API, clientes y
asistente integrado todavía conservado funcionan.
**Cierre específico:** endpoints retirados devuelven rechazo claro; autenticación
de clientes/API y lectura/exportación de documentos siguen válidas.
**Reversión:** código y ajustes previos; registrar cualquier revocación de tokens
que requiera reconexión. No borrar registros históricos en esta fase.

## Fase 6 — Retirar IA integrada

**Selección:** ejecutar si se decide prescindir de IA, incluida la local.
Si se desea un caso local concreto, acotar lo conservado y adaptar esta fase.

- Retirar chat asistido, autocategorización IA, detección/enriquecimiento IA,
  extracción PDF por modelos, embeddings/vector stores y narración IA.
- Retirar OpenAI/Anthropic/Jev y dependencias exclusivas tras eliminar todos
  sus consumidores; preservar generadores deterministas útiles.
- Mantener reglas locales e importaciones CSV/QIF/OFX/backup. Auditar PDF antes
  de quitar `pdf-reader`: conservar cualquier recorrido local retenido.
- Conservar recibos, documentos y originales; historial de chat recuperable
  según fase 1. Adaptar web/API, frontend nativo y configuración en la misma fase.
- Resolver jobs IA pendientes; retirar la puerta IA solo cuando no queden
  consumidores, salvo lectores de historia que necesiten una política explícita.

**Final estable:** Relay funciona sin credenciales/SDK IA, clasifica mediante
reglas explícitas y conserva documentos e importaciones soportadas.
**Cierre específico:** reglas, imports, adjuntos, insights locales y clientes;
no existen rutas ni trabajos que soliciten un proveedor retirado.
**Reversión:** código; datos históricos conservados. Documentar si el historial
se representa mediante un lector nuevo que deba permanecer.

## Fase 7 — Retirar conectores externos por lotes autocontenidos

No ejecutar como un gran borrado. **Cada lote es una subfase desplegable y pasa
todo el contrato de cierre antes de comenzar el siguiente.**

Orden: conectores sin registros ni uso → conectores con payload histórico pero
sin cuentas activas → conectores con cuentas enlazadas que se decide desconectar.
Agrupar por dependencia real, no por orden alfabético o número de archivos.

Por lote:

1. Enumerar clientes/adapters, concerns, items/accounts, processors, jobs,
   webhooks, rutas, locales, dependencias y referencias de backup.
2. Aplicar la disposición histórica; preparar conversión a manual si corresponde,
   sin lanzar callbacks destroy como método genérico de desconexión.
3. Comparar saldos de partida e historia, holdings, cash, transferencias y
   metadatos tras la conversión; cubrir estrategia reverse/forward y multimoneda.
4. Retirar entrada/sync/adapters y configuración, incluidos descubrimiento de
   factoría y reflexión de asociaciones. Mantener solo lectores necesarios.
5. Resolver cron/jobs pendientes, verificar eager loading, backup y núcleo.

**Límite:** cotizaciones/divisas no son conectores de cuentas y se tratan en 9A.
FinanceKit se conserva mientras se mantenga el cliente Apple que lo utiliza.
**Final estable:** cuentas previamente enlazadas siguen consultables y exactas,
con funcionamiento manual cuando se ha aprobado su conversión.
**Reversión:** sin conversión, revert de código; con conversión, restauración o
procedimiento inverso ensayado. Volver al código anterior no revincula una cuenta.

## Fase 8 — Retirar Bills y recurrencias detectadas

- Suspender detección/materialización Bills y retirar sus cron, feeds, endpoints,
  asignaciones, detección de series y consumidores en movimientos/transferencias.
- Retirar insights exclusivamente Bills; adaptar cualquier cálculo compartido
  con presupuestos/Goals aún retenidos antes de eliminarlo.
- Aplicar conservación histórica de recurrencias y backup sin mezclar ni convertir
  automáticamente datos a `ScheduledPayment`.
- Retirar guards/puertas que solo existían para ocultar Bills, sus opciones y
  pruebas exclusivas. Mantener regresiones que prueban la integridad de Agenda.

**Final estable:** Agenda sigue generando, confirmando, rechazando y enlazando
pagos; no hay segundo motor oculto produciendo recurrencias.
**Cierre específico:** Agenda, forecast, transferencias, edición/splits,
presupuestos/Goals retenidos, insights y restauración histórica.
**Reversión:** código anterior con puertas de producción; históricos conservados,
sin conversión automática que deshacer.

## Fase 9 — Curar las extensiones restantes

Cada bloque se decide, implementa y entrega por separado. Conservar una extensión
con propósito explícito cuenta como resolución; no obliga a eliminarla.

| Bloque | Decisión y alcance | Final estable y validación específica |
| --- | --- | --- |
| 9A. Mercado y divisas | Elegir entrada manual o pocos proveedores a demanda. Retirar proveedores y cron no elegidos, manteniendo precios/rates históricos y cálculos. | Inversiones/roboadvisor/multimoneda exactos con datos disponibles; ausencias claras, sin fallback engañoso. Validar precios en distintas divisas y fechas. |
| 9B. Logos | **Conservar Brandfetch: Steve confirma su uso en fase 0.** Curar URLs remotas ajenas si procede, manteniendo adjuntos e iniciales como alternativas. | Resolución Brandfetch conservada cuando se permite esa capacidad; modo sin logos remotos y originales locales válidos. |
| 9C. Plan, presupuestos, Goals e insights | Elegir por función. Si se suspende: cerrar rutas, cron, callbacks y generación; si se elimina: completar consumidores/backup. Conservar señales locales elegidas. | Dashboard, Agenda, categorías e informes sin referencias rotas; no se generan datos de módulos suspendidos; permisos y cálculos de módulos retenidos correctos. |
| 9D. Drive | **Conservar: Steve confirma su uso en fase 0.** Preservar OAuth por usuario y exportaciones/programaciones propias; separar esta capacidad del autosync bancario. | Renovación/permisos/destino y reintentos ensayados; backup y CSV local siguen funcionando. |
| 9E. Login externo y almacenamiento | Retirar solo protocolos/drivers no usados. Comprobar primero un acceso local válido y dónde residen los originales. No confundir S3 self-hosted con cloud. | Login/MFA/passkeys y originales accesibles. Cambiar almacenamiento requiere copiar/verificar archivos en un trabajo operativo aparte. |
| 9F. Clientes nativos y FinanceKit | Mantener decisión previa hasta seleccionar clientes soportados. Retirar frontend/distribución/API exclusivos solo después de esa selección. | Clientes conservados compilan y usan los contratos vigentes; quitar uno no rompe OAuth/push/API de otro. |

**Reversión por bloque:** registrar estado/configuración alterados. Cambios de
almacenamiento, identidades o cuentas no se revierten únicamente con Git.

## Fase 10 — Tratar datos y esquema residuales

Ejecutar por módulo retirado y estable; no es una migración masiva obligatoria.

- Enumerar tablas, columnas, settings, tokens, índices y referencias que quedaron.
- Confirmar ausencia de consumidores actuales y disposición recuperable de datos.
- Preparar migraciones Rails nuevas; mantener las históricas. Retirar constraints
  e índices solo cuando corresponda y mantener cobertura de backups.
- Ensayar sobre una copia aislada, verificar historial/restauración y expresar
  bloqueos de tablas, espacio, duración estimada y carácter reversible/irreversible.
- Presentar eliminación persistente concreta antes de operar datos reales;
  backup completo de instalación y recuperación ensayada son prerrequisitos.
- Conservar cualquier tabla/lector cuya retirada cueste más que mantenerlo.
  Una app pequeña no exige destruir toda huella histórica.

**Final estable:** mismo resultado financiero y datos necesarios recuperables,
con esquema reducido solo donde hay beneficio demostrado.
**Cierre específico:** instalación nueva, actualización desde versión previa y
recuperación de backup anterior con la disposición elegida.
**Reversión:** si se borraron datos, restauración del backup; identificar las
escrituras posteriores que se perderían. Un `down` que recrea tablas vacías no
restaura información y no se presenta como rollback completo.

## Fase 11 — Cerrar el soporte y medir la reducción

- Eliminar documentación/configuración activa de hosting y canales no soportados;
  archivar solo referencias útiles, preservar licencia e historia.
- Consolidar configuración, guías de instalación/actualización, OpenAPI, mapa de
  preservación y cierre de migración según el producto realmente mantenido.
- Revisar CI/Dependabot después de quitar dependencias y plataformas, conservando
  comprobaciones de seguridad y calidad aplicables.
- Retirar compatibilidad de jobs transitoria solo tras verificar que no quedan
  queued/retry/scheduled jobs de las versiones que la necesitan. Distinguirla de
  lectores de backups históricos, que pueden permanecer.
- Comparar métricas iniciales y finales; registrar las extensiones retenidas y
  su motivo. No declarar ahorro de rendimiento que no se haya medido.

**Final estable:** producto y documentación coinciden; instalación nueva,
actualización y recuperación de datos soportadas y probadas.
**Reversión:** unidades concretas de código/docs; lectores necesarios conservados.

## Registro de ejecución

La fase 0 está publicada en `eb538dae3`, la fase 1 en `a5299f36c` y la fase 2
en `ee3341fd3`. La fase 3 está implementada y validada, sin publicar;
su [registro](pruning-phase-3.md) recoge alcance, pruebas y pendientes.
El [punto de continuación de fase 2](pruning-phase-2.md#punto-de-continuación-para-otro-chat)
registra la transición de configuración. Las fases 4–11 siguen pendientes.
No se ha desplegado la poda en TrueNAS en estas entregas.
Para cada fase/subfase registrar:

| Campo | Contenido |
| --- | --- |
| Selección | Alcance aprobado y extensiones conservadas |
| Estado | Pendiente / en preparación / validada / publicada / comprobada en instalación |
| Referencias | HEAD inicial/final, revisión desplegada cuando se inspeccione |
| Datos | Conteos privados, disposición histórica y cambios persistentes |
| Contratos | API, clientes, backups, jobs y configuración afectados |
| Evidencia | Pruebas ejecutadas, resultados, comparaciones y pendientes |
| Reversión | Código/configuración, recuperación de datos y límites |
| Cierre | Confirmación de que se puede detener aquí con Relay utilizable |

El siguiente paso es confirmar la publicación de fase 3 preparada y validada.
Después, continuar por **fase 4**, retirada de la plataforma
comercial SaaS. Las fases 1 y 2 construyeron la base segura.
El avance a cualquier fase requiere cerrar la anterior aplicable, sin trasladar
fallos, contratos rotos ni decisiones pendientes que bloqueen su funcionamiento.
