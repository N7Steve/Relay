# Fase 1 — Contratos de backup preparados para la poda

Fecha: 4 de octubre de 2026. Alcance autorizado: ejecución de fase 1.
Estado: completada, validada y publicada en `origin/main`.
Commit/push autorizados por Steve el 4 de octubre de 2026. Despliegue pendiente.
Base de código: `eb538dae3cda1346fcbd9db9f4e77f6141e1be7d` (fase 0 publicada).

## Resultado

Se conserva el formato existente (ZIP 3, snapshot 1) y todos los módulos actuales.
El backup deja de depender de las clases funcionales del asistente para leer
Chat, Message y ToolCall. Lectores mínimos de persistencia conservan el historial,
incluidos valores STI, sin callbacks, jobs de IA ni broadcasts.

Se separan los nombres persistidos de los nombres de clases internas en registro,
exportación, validación de duplicados y referencias. Tipos históricos desconocidos
se rechazan explícitamente antes de escribir. El asistente actual sigue leyendo
las conversaciones restauradas mediante sus clases habituales.

La [disposición por módulos](pruning-backup-contracts.md) cubre el inventario
actual, datos compartidos, polimorfismo, JSON, STI, GlobalID, cifrado y adjuntos.
La primera retirada de telemetría/evals ya dispone de exclusiones documentadas
de uso/logs/facturación; el lector concreto de conversaciones prepara la retirada
IA/MCP posterior. No se crea una plataforma genérica de archivo ni se sustituye
todo ActiveRecord por lectores históricos.

## Límites de esta base

- Los readers siguen necesitando chats/messages/tool_calls. No se borran tablas.
- Otros módulos conservan sus modelos y scopes actuales; su retirada debe adaptar
  cada contrato concreto en su fase, especialmente Provider, Bills y Goals.
- Quitar las clases activas Chat/Message/ToolCall también exige quitar sus
  consumidores de UI/API/jobs/asociaciones. Este cambio resuelve la dependencia
  del backup, no autoriza borrar esas clases de forma aislada.
- El backup anterior no se pierde ni se omiten registros de módulos no utilizados.
- Sin nuevas dependencias, cambios de esquema, endpoints, claves, configuración
  productiva ni operación TrueNAS. Drive y Brandfetch siguen intactos.

## Comprobaciones

Resultados focalizados actuales: 234 tests, 1.347 aserciones, sin fallos, errores
ni omisiones. Incluyen doble restauración del historial sin instanciar modelos
funcionales, compatibilidad del asistente actual, rechazo de IDs duplicados,
tipos desconocidos y referencias fuera del snapshot, junto con la cobertura
previa de backups/importación/originales.

RuboCop, ERB lint, Biome y Brakeman pasan. Build de imagen productiva local
`relay-pruning-phase1:validation` correcto. La imagen es de ensayo sobre la base
Git más el diff preparado; no se publica ni representa una revisión desplegada.

Eager loading (`bin/rails zeitwerk:check`) correcto. El snapshot sintético de
fase 0, conservado sin sobrescribir, se restaura y reexporta en dos rondas:
21 registros y un adjunto verificados por ronda, con la misma huella financiera
y los bytes originales. No es una restauración del backup privado de Steve.

Pruebas de sistema de importación: 8 tests, 36 aserciones, sin fallos, errores
ni omisiones; incluyen originales ZIP de Sure y los flujos Relay/movimientos.
Suite completa `bin/rails test` en Docker Linux: 10.876 tests, 46.313 aserciones,
0 fallos, 0 errores y 46 omisiones, en 614,84 segundos. Las omisiones coinciden
con la ejecución de fase 0 en este entorno; no se añaden tests omitidos.
Logs en `tmp/pruning-phase-1/`, fuera de Git. Los proyectos de prueba son
independientes de NAS, Sure y app local.

## Reversión y continuación

Revertir el código devuelve los modelos anteriores al backup. El formato, tablas,
filas, tipos y adjuntos son compatibles; no hace falta backfill ni revertir DDL.
Los datos restaurados no se deshacen con Git, como ocurría antes de esta fase.

La fase siguiente es separar recálculo local y adquisición externa. No se
ejecuta esa fase como parte de este trabajo. Las adaptaciones de cada módulo
retirado continúan en sus fases respectivas, sobre el contrato fijado aquí.

Se puede detener aquí: todos los módulos actuales siguen disponibles, el backup
anterior conserva su formato y los ensayos no muestran divergencias financieras.
La validación no sustituye una comprobación operativa tras un futuro despliegue.

## Punto de continuación para otro chat

- Las fases 0 y 1 están cerradas. No repetir su implementación.
- La fase 2 ya está implementada y validada, pendiente de publicación. Consultar
  su [registro y punto de continuación](pruning-phase-2.md#punto-de-continuación-para-otro-chat)
  y el [plan de poda](pruning-plan.md) para el estado actual.
- Leer este registro y los [contratos de recuperación](pruning-backup-contracts.md)
  antes de adaptar modelos, scopes, referencias o jobs. Las disposiciones de
  módulos aún no retirados se completan en sus fases respectivas.
- Preservar Google Drive, Brandfetch, núcleo financiero, Agenda, inversiones,
  permisos y recuperación. No interpretar falta de uso como ausencia de datos.
- Trabajar en `main` siguiendo AGENTS.md. El commit de esta entrega se identifica
  con `git log -1 -- docs/migration/pruning-phase-1.md`; incluye código, tests y
  documentación de la fase 1.
- Publicación Git y despliegue son estados distintos. La última revisión
  confirmada de web/worker en TrueNAS sigue siendo
  `1e279bd8f6fe05d295c074180efccbcd59195ad5`; no se ha actualizado el servidor
  durante estas fases. Comprobar de nuevo la revisión si se necesita su estado real.
