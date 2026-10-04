# Poda fase 3 — Telemetría y evaluaciones remotas

Seleccionada por Steve el 4 de octubre de 2026. Base: `ee3341fd3`, fase 2 ya
publicada en `origin/main`. Trabajo en `main`, sin commit/push ni despliegue.

## Alcance aplicado

- Retiradas las siete dependencias directas de Sentry, PostHog, Skylight,
  Logtail y Langfuse y sus dependencias exclusivas del lockfile. Retirados
  inicializadores, configuración y variables de ejemplo/Helm sin consumidores.
- Sustituidos los hooks Sentry de sincronización, imports, webhooks, exportación,
  Goals y errores de conexión por `LocalDiagnostics`, Rails logs y
  `DebugLogEntry.capture`. Se conservan identificadores y errores sanitizados;
  se excluyen snapshots de payload y backtraces del registro de diagnóstico.
- Eliminadas las trazas de OpenAI, Anthropic y búsqueda de documentos. Se
  conserva su comportamiento, puertas de acceso, prompts, streaming, registros
  locales `LlmUsage`, extracción PDF y respuestas de error.
- Retirado el sistema `Eval`: runners, métricas, reportes, clientes Langfuse,
  factoría, tareas `evals:*`, seis datasets y pruebas exclusivas. Los tests de
  proveedores conservados siguen verificando su comportamiento con stubs.
- Eliminado el helper inerte de encuestas y traducciones huérfanas del gráfico.
  Se conserva el gráfico, su comparación local y los enlaces de feedback a GitHub.
- Flutter deja de depender de `sentry`/`sentry_flutter`. `DiagnosticsService`
  utiliza el logger local sanitizado y medición local de duración; no almacena
  identidad ni tiene transporte remoto. Login, sincronización y callbacks de
  error conservan sus contratos. Registrantes Android/iOS actualizados.

El cambio visible es mínimo porque los controles de encuestas ya se habían
retirado. Esta fase elimina código y dependencias del runtime.

## Datos, recuperación y transición

No hay migraciones, borrados de datos, conversiones de cuentas ni cambios de
formato de backup. Se mantienen `eval_datasets`, `eval_samples`, `eval_runs`,
`eval_results` y sus migraciones históricas. Son datos de evaluación de instancia,
sin pertenencia familiar, y no forman parte del inventario de `Family::Backup`.
Su recuperación completa sigue disponible mediante backup SQL y el código
anterior conservado en Git; esta versión no ofrece runners ni informes Eval.

No existían jobs ActiveJob ni cron exclusivos de Eval que requieran clases
transitorias. Sus tareas manuales y llamadas remotas ya no están disponibles.
Los cron, trabajos financieros, Agenda y exportaciones Drive siguen intactos.

Las variables heredadas `SENTRY_*`, `POSTHOG_*`, `SKYLIGHT_*`, `LOGTAIL_*` y
`LANGFUSE_*` no activan SDKs. No es necesario cambiar credenciales guardadas para
esta retirada. Antes de desplegar siguen aplicando las activaciones de
Drive/Brandfetch documentadas en fase 2 y la actualización coordinada web/worker.
TrueNAS no se ha inspeccionado ni modificado.

## Validación

| Comprobación | Evidencia |
| --- | --- |
| Tanda focalizada | 215 pruebas, 864 aserciones; 0 fallos, errores u omisiones; incluye IA, errores PDF, sync y backup |
| Navegador | 11 pruebas, 86 aserciones; 0 fallos, errores u omisiones; gráfico, recálculo manual y bandeja sync |
| Flutter | Análisis sin errores/avisos de severidad warning; 3 infos previos en `intro_screen_web.dart`; 170 pruebas correctas |
| Flutter web | Build release correcto |
| Recuperación | Dos restores de 21 registros y 1 original cada uno; valores, relaciones y bytes iguales, rollback confirmado |
| Producción | Imagen construida; arranque/eager loading sin red con variables heredadas; sin gems de telemetría ni tareas Eval |
| Lint y seguridad | RuboCop/ERB/Biome correctos; Brakeman 0 errores y 0 avisos activos, mismas 8 exclusiones |
| Suite Rails completa | 10.824 pruebas, 46.157 aserciones; 0 fallos, 0 errores, mismas 46 omisiones existentes; 1.150,04 s |
| Flutter Android | APK debug construido correctamente; SDK/NDK/CMake solo en el contenedor de pruebas |

La primera pasada Flutter falló porque el contexto aislado omitía
`design/tokens/relay.tokens.json`. Se incorporó ese archivo de referencia y la
suite completa pasó. Las correcciones RuboCop fueron exclusivamente de espacios
y líneas vacías; no se relajaron reglas ni se añadieron skips.

La revisión final preserva `metadata.error_class` cuando el caller ya aporta
la clase original junto con una excepción sanitizada. Sus siete pruebas
específicas pasaron (30 aserciones), y la suite Rails se reinició sobre esa
revisión. El build nativo iOS requiere macOS y no se ha ejecutado aquí; los
tests/análisis y builds web/Android cubren el código Dart compartido.

La reducción del número de tests corresponde a pruebas exclusivas de módulos
retirados; no se añadieron omisiones para obtener verde. Evidencia final local:
`tmp/pruning-phase-3-full-suite-final.log`, `tmp/pruning-phase-3-focused.log`,
`tmp/pruning-phase-3-diagnostics-final.log`, `tmp/pruning-phase-3-system.log`,
`tmp/pruning-phase-3-checks-final.log`, `tmp/pruning-phase-3-lint-final-edit.log`,
`tmp/pruning-phase-3-flutter-tests-final.log`, `tmp/pruning-phase-3-flutter-web.log`,
`tmp/pruning-phase-3-flutter-android.log`,
`tmp/pruning-phase-3-production-build-final.log`,
`tmp/pruning-phase-3-production-boot-final.log` y `tmp/pruning-phase-3-recovery.log`.
No contienen datos del NAS. La suite inicial interrumpida no es evidencia de cierre.
Las respuestas API v1 y su documentación no cambian en esta fase.

## Reversión y continuación

Revertir código y lockfiles conserva el esquema y todos los datos. Antes de
volver a una versión anterior, retirar las variables Langfuse heredadas para
evitar reactivar sus envíos. Los SDK retirados permanecen recuperables en Git.

Estado original de entrega: **implementada y validada, sin commit/push**.
Publicación posterior: incluida en `feccab08c`, observado en `origin/main`
al iniciar la [fase 4](pruning-phase-4.md) el 4 de octubre de 2026. Se puede detener aquí con
Relay utilizable: misma contabilidad, proveedores retenidos y recuperación
comprobada, sin los SDK retirados. Tras publicación autorizada,
continuar con **fase 4 — Retirar la plataforma comercial SaaS**. Preservar permisos,
recuperación, familias/multiusuario, Agenda, inversiones, Drive y Brandfetch.
