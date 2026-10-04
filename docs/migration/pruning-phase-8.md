# Poda fase 8 — Retirada de Bills

Seleccionada por Steve el 5 de octubre de 2026, tras indicar que la fase 7
está desplegada y aparentemente funciona correctamente. Esa comprobación es
su reporte; este trabajo no inspecciona ni modifica TrueNAS.
HEAD inicial: `0a4c9c2dc`. Implementación validada localmente en `main`,
sin commit/push ni migraciones de esquema.

## Alcance y disposición

Agenda (`ScheduledPayment` y `ScheduledPaymentEntry`) queda como único motor
de pagos previstos. Se retiran Bills, series detectadas, declaración manual,
planificación por nóminas, calendario/feed ICS, asignaciones y matching,
clasificación, cambios de precio detectados y backfill de recurrencias.

- Retirados controllers, rutas HTML/API, vistas, helpers, el controlador Stimulus
  exclusivo de frecuencia Bills, rake y traducciones
  exclusivas. Las antiguas URLs devuelven 404, incluso con una API key válida.
  Transacciones y transferencias conservan la creación de pagos de Agenda.
- La finalización del sync no agenda detección Bills. El cron nocturno de
  recurrencias desaparece; la reconciliación elimina también su definición
  persistida, conservando el cron de Agenda y las demás tareas.
- `IdentifyRecurringTransactionsJob` y `GenerateRecurringOccurrencesJob`
  son consumidores sin efectos para jobs serializados anteriores. No hacen
  fan-out, materialización ni consultas familiares; no se purga Redis.
  Su retirada definitiva requiere inventario de colas en fase 11.
- Los seis modelos históricos conservan nombres de tablas/GlobalID, relaciones,
  enums y validación de importaciones: `RecurringTransaction`, `RecurrenceRule`,
  `RecurringOccurrence`, `RecurringAllocation`, `RecurringPriceChange` y
  `RecurringMatchRejection`. No conservan motores ni callbacks financieros.
  Se mantienen cascadas necesarias para el borrado explícito de familia/cuentas.
- Snapshot y ZIP mantienen su formato y nombres persistidos. Exportación,
  restauración, imports legacy, preflight y mappings siguen recuperando series,
  reglas, reemplazos, ocurrencias, asignaciones, cambios de precio y rechazos.
  No se convierten ni duplican como `ScheduledPayment`.
- Se retiran `cash_flow_warning` y `subscription_audit` del registro de
  generadores; sus insights históricos siguen en backups y fuera del frontend.
  Las notificaciones históricas encoladas tampoco pueden enviarse; el job
  compartido comprueba el tipo tanto al encolar como al ejecutar.
  Insights locales de gasto, patrimonio, ahorro, efectivo, presupuestos y Goals
  continúan. Forecast estadístico/manual no depende del detector Bills.
- Se elimina la reserva Bills en presupuestos y su UI. Sus cálculos de gasto
  contabilizado y disponibilidad permanecen. No se introduce otra reserva.
- Se elimina `bills_frontend_enabled` y sus guards; test y producción comparten
  la retirada. Columnas históricas, preferencias y token antiguo quedan sin
  consumidores activos, pendientes de su disposición en fase 10.
- API OpenAPI se regenera sin el recurso retirado. No hay dependencias ni código
  Bills en los clientes nativos mantenidos que requieran cambio de contrato.

## Verificación

Todas las verificaciones definitivas pasan. Las ejecuciones intermedias fallidas
no cuentan como cierre verde.

- Rails completo: 6.095 pruebas, 28.003 aserciones, 0 fallos y 0 errores;
  conserva las 38 omisiones anteriores, sin añadir omisiones para esta fase
  (`tmp/phase8-rails-ready.log`).
- Navegador completo: 140 pruebas, 713 aserciones, 0 fallos, 0 errores y
  0 omisiones (`tmp/phase8-system-verified.log`).
- Focalizadas de persistencia, recuperación, cron, jobs, API y movimientos:
  210 pruebas, 906 aserciones, 0 fallos/errores/omisiones.
- Insights y navegación: 28 pruebas, 126 aserciones, 0 fallos/errores/omisiones.
- Entrega de notificaciones, jobs retirados e insights: 59 pruebas,
  190 aserciones, 0 fallos/errores/omisiones. Los tipos Bills no pueden encolar
  ni ejecutar notificaciones, aunque APNs y el dispositivo sean elegibles.
- RuboCop: 1.956 archivos sin infracciones. ERB lint: 553 plantillas sin errores.
  Biome: 134 archivos sin errores. Brakeman: 0 errores/avisos activos;
  se elimina únicamente la exclusión del controller Bills retirado, sin añadir
  exclusiones. Los nuevos guards de notificación pasan también lint focalizado.
- OpenAPI regenerado: 392 ejemplos, 0 fallos, 89 pendientes documentales.
  Comprobador de consistencia API correcto. Los nombres históricos Bills del
  resumen de imports permanecen como datos, sin rutas ni esquemas de su API.
- Imagen de producción con assets y eager loading sin red correctos. Agenda y
  persistencia histórica presentes; motores, rutas, generadores y cron Bills
  ausentes. No se modifica Gemfile/lock ni se añaden dependencias.
- Recuperación anterior → fase 8 → ZIP → segunda restauración: ambas verifican
  30 registros y un original binario con estado `matched`. Conservan tres cuentas,
  balances, holdings, transferencia, Agenda, seis tipos Bills y sus relaciones.
  Valores financieros y SHA-256 del recibo coinciden; no hay ocurrencias adicionales.
  Operaciones SQL revertidas y originales temporales retirados al terminar.
- Dos ejecuciones intermedias de navegador registraron errores transitorios de
  Selenium en cuentas y selección de fechas del gráfico. Sus archivos completos
  pasan al repetirlos: 10 pruebas, 81 aserciones, sin errores. No se cambian esas
  pruebas ni el driver para ocultar los fallos.

La cobertura incluye URLs antiguas, jobs serializados, reconciliación repetida,
ausencia de nuevas ocurrencias al guardar/restaurar, Agenda en web,
insights mantenidos e ida y vuelta histórica con relaciones verificadas.
Se ensaya además un backup sintético producido por la imagen anterior de fase 7,
con Agenda, Bills, transferencias, saldos, holdings y un recibo original.
No se utilizan datos personales ni backups de instalación.

Logs locales: `tmp/phase8-focus-final.log`, `tmp/phase8-insights.log`,
`tmp/phase8-notifications.log`, `tmp/phase8-quality-complete.log`,
`tmp/phase8-openapi.log`, `tmp/phase8-api-consistency.log`,
`tmp/phase8-recovery-verified.log` y
`tmp/docker-test-results/phase8-recovery.json`. Estos artefactos y el dataset
sintético permanecen fuera del commit.

El build y arranque definitivos se registran en
`tmp/phase8-production-closed-build.log` y
`tmp/phase8-production-closed-boot.log`. El navegador se ejecutó en otro proyecto
Docker, con base y Redis propios. Sus servicios y los del ensayo de recuperación
se detuvieron al finalizar; los volúmenes de prueba permanecen.

**Cierre local:** Relay puede detener la poda aquí con Agenda y núcleo financiero
utilizables. La instalación real, sus colas y una recuperación de su backup no
se han inspeccionado: no se afirma verificación de producción.

## Publicación y reversión

Commit/push requieren la confirmación del resultado conforme a
[AGENTS.md](../../AGENTS.md). No se publican cambios ni se opera sobre colas,
credenciales, datos reales o instalación durante esta preparación.

Actualizar web y worker juntos. El arranque del worker retira el cron Bills
persistido y los jobs antiguos terminan sin efectos. Los históricos permanecen
recuperables. No se requieren migraciones de base de datos.

Reversión: volver al código anterior con su puerta de producción desactivada.
No hay conversión automática que deshacer; el esquema se conserva. Restaurar
el motor antiguo puede reactivar detección y cron, por lo que la reversión debe
mantener explícitamente la política operativa deseada. No se inicia fase 9.
