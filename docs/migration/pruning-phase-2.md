# Fase 2 — Recálculo local y capacidades externas

Fecha: 4 de octubre de 2026. Base: `a5299f36c`. Trabajo sobre `main`.
Estado: **implementada y validada; pendiente de confirmación para commit/push**.
Sin publicación ni despliegue en TrueNAS.

## Contrato financiero

`Account::Recalculator` materializa saldos y holdings en una transacción local.
Los puntos de entrada existentes de cuentas, entries, imports y `SyncJob` siguen
funcionando. `Account::Syncer` deja de importar precios/divisas: la importación de
mercado conserva sus jobs y puntos de entrada propios, sujetos a activación.
Matching se ejecuta con consultas externas de mercado bloqueadas.

Las cuentas enlazadas conservan la estrategia reverse. Suspender un conector no
elimina su relación ni convierte la cuenta a manual. La sincronización familiar
recalcula todas las cuentas cuando bancos está apagado; el botón de una cuenta
enlazada también recalcula localmente. Los overrides históricos IBKR leen los
payloads ya guardados y permanecen dentro de la transacción de recálculo.

Si faltan precios o FX necesarios, el recálculo falla y conserva el estado
financiero anterior. `Sync` conserva el error y se registra un diagnóstico local
con contexto de familia/cuenta. Los totales que consumen una tasa ausente ya no
usan 1:1. La barra lateral muestra un aviso sin bloquear la navegación; una
pantalla que necesita esa conversión informa de datos insuficientes.

## Configuración y transición

Las capacidades nuevas son globales a la instalación, independientes de las
credenciales, y tienen default apagado. No se cambian los valores anteriores de
autosync, proveedores, claves, conexiones ni programaciones de usuario.

| Capacidad | Setting | Variable con prioridad sobre el Setting |
| --- | --- | --- |
| Bancos/brokers/on-chain | `external_bank_sync_enabled` | `RELAY_EXTERNAL_BANK_SYNC_ENABLED` |
| Precios/divisas | `external_market_data_enabled` | `RELAY_EXTERNAL_MARKET_DATA_ENABLED` |
| Valoraciones AVM | `external_property_valuations_enabled` | `RELAY_EXTERNAL_PROPERTY_VALUATIONS_ENABLED` |
| Logos externos | `external_logos_enabled` | `RELAY_EXTERNAL_LOGOS_ENABLED` |
| Google Drive | `external_google_drive_enabled` | `RELAY_EXTERNAL_GOOGLE_DRIVE_ENABLED` |

Una variable presente activa únicamente con `true` o `1`; cualquier otro valor
desactiva. Ausente, se usa el Setting. IA conserva su interruptor existente
`ai_features_enabled`, cuyo default fuera de test ya era apagado. Un valor IA
guardado sigue vigente y debe inventariarse antes del despliegue.

**En la instalación de Steve, activar explícitamente antes de actualizar:**

```dotenv
RELAY_EXTERNAL_LOGOS_ENABLED=true
RELAY_EXTERNAL_GOOGLE_DRIVE_ENABLED=true
```

Estas dos extensiones están confirmadas como utilizadas. Conservar también su
configuración y credenciales actuales. Los demás interruptores nuevos pueden
permanecer ausentes/apagados. No se ha editado la configuración de TrueNAS.

Los tests históricos habilitan explícitamente las capacidades mediante stubs de
Settings. Las nuevas pruebas de límites los desactivan o leen los defaults reales;
los tests del núcleo local funcionan con todas las capacidades nuevas apagadas.

## Superficies y trabajos pendientes

- Login y autosync programado bancario respetan la capacidad antes de encolar.
- Acciones de conectores y webhooks bancarios se bloquean antes de actuar.
- Los clientes HTTParty, Faraday, Plaid, Trade Republic y Google Drive comprueban
  el permiso antes del transporte; también las rutas directas de IA/embeddings.
  Los guardas de transporte cubren llamadas desde web, API, cron y bajo demanda.
- El navegador no carga Plaid con bancos apagados. Las URLs de logos externos no
  se renderizan con logos apagado; imágenes propias adjuntas siguen disponibles.
- El worker reconcilia los cron conocidos al arrancar: elimina solo los cron
  de capacidades apagadas y carga los habilitados. Autosync usa su reconciliador.
  Agenda, mantenimiento, limpieza de syncs/imports y otros trabajos locales quedan.
- Un `Sync` de conector pendiente se consume con la cancelación existente (stale
  y `cancel_requested_at`), sin llamar al proveedor. Los jobs externos auxiliares
  se consumen sin ejecutar y dejan una línea local de cancelación. Las clases
  permanecen; no se purga Redis ni la cola compartida. Los flags antiguos de
  fetch/import siguen sujetos al limpiador existente.
- Trabajos ya en ejecución deben terminar durante una parada ordenada del worker
  anterior. Cambiar variables requiere reiniciar web y worker; el código nuevo no
  puede detener una petición iniciada por el proceso anterior.

Esta fase controla las capacidades financieras y extensiones descritas. Las
retiradas de telemetría, SaaS, SSO y clientes/SDK siguen en sus fases posteriores;
no se presenta esto como un firewall general de todo el proceso.

## Verificación y continuidad

| Verificación | Resultado |
| --- | --- |
| Suite completa `bin/rails test` | 10.898 pruebas, 46.398 aserciones, 0 fallos y 0 errores |
| Omisiones de la suite completa | 46; mismo número que la suite de fase 1, sin omisiones nuevas para esta entrega |
| Tanda específica de modelos/controladores | 137 pruebas, 556 aserciones, 0 fallos/errores/omisiones |
| API y límites web, incluido el nuevo caso FX 422 | 8 pruebas, 31 aserciones, 0 fallos/errores/omisiones |
| Navegador: cuentas, controles de sync y creación manual sin acceso externo | 13 pruebas, 91 aserciones, 0 fallos/errores/omisiones |
| Recuperación sintética | Dos restores con 21 registros y 1 original cada uno; valores, vínculos y bytes iguales, rollback confirmado |
| RuboCop | Suite de lint sin infracciones; revisión final de archivos Ruby modificados sin infracciones |
| ERB lint / Biome / Brakeman | Sin errores de plantillas/lint; 0 errores y 0 avisos activos de seguridad, mismas 8 exclusiones |
| OpenAPI | Regenerado mediante rswag, solo añade la respuesta 422 de balance sheet; specs sin aserciones de comportamiento |
| Assets / diff | Compilación de assets y `git diff --check` correctos |

El caso adicional de API se añadió después de iniciar la suite completa y pasó
en la tanda específica posterior. No cambió código de aplicación después del
build de la suite completa. Su documentación usa el schema compartido
`ErrorResponse` y la autenticación `X-Api-Key` existente.

Logs finales locales: `tmp/pruning-phase-2-full-suite-final.log`,
`tmp/pruning-phase-2-focused.log`, `tmp/pruning-phase-2-api.log`,
`tmp/pruning-phase-2-system.log`, `tmp/pruning-phase-2-recovery.log` y
`tmp/pruning-phase-2-checks.log`. No contienen datos del NAS. Los resultados de
las iteraciones anteriores no son la evidencia de cierre.

El entorno PostgreSQL de pruebas conservaba el rol histórico `sure_test`.
Se creó el rol `relay_test` definido por el Compose actual, exclusivamente dentro
del contenedor local `relay-tests-db-1`. No se alteró el rol anterior ni bases de
producción. El runner carga el schema sobre su base aislada de pruebas.

La reversión consiste en restaurar código/configuración anteriores y arrancar el
worker con su reconciliación de cron. No hay migración, conversión de cuentas,
cambio de formato de backup ni eliminación de datos financieros. Los nuevos
Settings pueden quedar guardados sin consumidores al volver al código anterior.

## Punto de continuación para otro chat

- Fases 0 y 1 publicadas. **Fase 2 lista y validada, todavía sin commit/push**.
- No repetir su implementación. Revisar el working tree y este registro antes
  de publicar; seguir la confirmación de Git exigida por `AGENTS.md`.
- Tras publicar esta entrega, continuar por **fase 3 — Retirar telemetría y
  evaluaciones remotas**, según el [plan de poda](pruning-plan.md).
- Antes de un despliegue, activar Drive/logos en la configuración de Steve y
  revisar los valores guardados de IA. No se ha inspeccionado ni cambiado su NAS.
- Preservar recálculo local, estrategia de cuentas enlazadas, históricos,
  recuperación, permisos, Agenda, Drive y Brandfetch en las siguientes fases.
