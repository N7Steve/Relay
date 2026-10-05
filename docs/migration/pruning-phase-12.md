# Fase 12 — refinado final

5 de octubre de 2026. Base: `646548f0d` (fase 11 desplegada en TrueNAS en
`b6ba8735a`). Selección de Steve registrada en el
[plan](pruning-plan.md#fase-12--refinado-final): retirar restos sin uso, la familia
demo, RentCast/Realie, los clientes Apple/macOS y los profilers; conservar idiomas,
Lookbook, la app Flutter para Android y la API para clientes propios futuros.

## Alcance aplicado

### Familia demo (back y front)

- Retirados `Demo::Generator`, `Demo::DataCleaner`, `DemoFamilyRefreshJob`, su
  mailer y plantilla, `config/demo.yml`, la tarea `demo_data` y el aviso de
  `db/seeds.rb`.
- Front: ajustes de refresco demo en *Instancia*, distintivo «Demo data» en la
  administración de usuarios, banner y credenciales precargadas en el login y la
  acción «Restablecer con datos de ejemplo» del perfil (ruta, acción y parámetro
  de `FamilyResetJob`). El restablecimiento normal se conserva.
- `ApiKey` pierde la clave de monitorización demo y su protección (`visible`,
  guardas de revocación/borrado); todas las claves vuelven a ser revocables.
- Cron `refresh_demo_family` retirado.

### RentCast y Realie

- Retirados los proveedores, `PropertyValuationConcept`, `RateLimitable`,
  `ProviderRequestCount`, `Property::AvmImport`, `SyncPropertyValuationsJob`, el
  alta de inmuebles por valoración automática (selector, búsqueda, vista previa
  firmada y confirmación), sus ajustes cifrados y la capacidad externa
  `property_valuations`. Los inmuebles se crean y valoran manualmente.
- `Provider::Registry` queda reducido al cliente de notas de versión de GitHub.
- Cron `sync_property_valuations` retirado.

### Clientes

- Retirados el escritorio macOS (`desktop/`, Tauri) y su SSO por `sure://`
  (`/auth/desktop/:provider`, `/sessions/desktop_exchange`), la app SwiftUI
  (`bitrig/`, `Project.json`, `appStoreConnect/`) y los destinos iOS y web de
  Flutter, con su job de CI y guías iOS/TestFlight.
- Notificaciones push APNs: API `/api/v1/push_subscriptions`, modelo y entrega,
  cliente APNs, jobs de insight y de prueba, panel de prueba en *Salud del sistema*
  y la gem `apnotic`. Solo las usaban clientes iOS.
- Se conservan Flutter Android (OAuth, SSO móvil `sureapp://`, MFA) y toda la
  API v1 para un cliente Windows o un front Angular futuros.

### Gems de desarrollo

- Retiradas `vernier` y `rack-mini-profiler` (cargadas también en producción),
  `stackprof`, `derailed_benchmarks` y `benchmark-ips`, con `perf.rake`,
  `lib/tasks/benchmarking.rake` y el inicializador del profiler. El lockfile solo
  pierde esas gems y sus dependencias exclusivas (14 specs), sin cambios de versión.
- Se conserva Lookbook (`/design-system`, solo fuera de producción).

### Restos sin uso

- Controladores Stimulus sin referencias (`ai_prompt_form`, `ai_prompt_editor`,
  `color_select`, `stale_account_action`), ocho imágenes sin uso, el helper
  `assistant_icon`, la limpieza de caché IA sin llamadas (`clear_ai_cache` y
  `family_scope`) y tres módulos de test de interfaces de proveedores retirados.
- Esquema OpenAPI huérfano `RetryResponse` (reintentos de chat).
- Traducciones: 7.150 entradas de 681 claves sin uso, en todos los idiomas,
  pertenecientes a módulos retirados (conectores, IA/chat, Bills, demo, AVM, push).
  Se seleccionaron cruzando `i18n-tasks unused` con los nombres de esos módulos;
  se eliminaron solo sus líneas y se verificó que cada archivo resultante carga
  exactamente los datos originales menos esas claves. 60 archivos quedaron vacíos
  y se borraron. Se conservan las etiquetas `trade_republic_items.activities.labels`:
  `i18n-tasks` solo busca en `app/`, pero las lee una migración histórica. Las demás claves que `i18n-tasks` marca como sin uso pueden
  usarse dinámicamente y se conservan.
- Se revisó y **conserva** el filtro «IA» de transacciones: también cubre la
  categorización automática local (Bayes), que sigue activa.

## Esquema y datos

Migración `20261005180000_remove_demo_valuation_and_push_persistence.rb`:

- Elimina `push_subscriptions` y `provider_request_counts`.
- Elimina `properties.avm_provider`, `properties.avm_last_synced_on`, su índice
  y su restricción. Las valoraciones ya creadas son movimientos normales y se
  conservan.
- Borra los ajustes `demo_family_refresh_*`, `external_property_valuations_enabled`,
  `rentcast_api_key` y `realie_api_key`, y la clave API de monitorización demo:
  sin su guarda sería una credencial conocida y válida.
- `down` es irreversible. Recuperar estos datos exige el backup de servidor que
  `update-relay.sh` crea antes de actualizar.

`ExternalSchedule` vuelve a tener una lista de cron retirados, limitada a
`refresh_demo_family` y `sync_property_valuations`: la auditoría de la fase 11 mostró
`refresh_demo_family` persistido en Redis, y quitarlo solo de `schedule.yml` lo
dejaría lanzando una clase inexistente.

Los backups antiguos que traigan `avm_provider`/`avm_last_synced_on` en inmuebles
los descartan con informe, como los demás atributos retirados. Las suscripciones
push nunca formaron parte del backup familiar.

## Métricas

Medidas con `script/pruning/measure.ps1` sobre el árbol final
(`tmp/pruning-phase-12/final-metrics.json`).

| Métrica | Fase 0 | Fase 11 | Fase 12 |
| --- | ---: | ---: | ---: |
| Archivos versionados | 7.189 | 5.161 | 4.910 |
| `app/`: archivos / líneas | 2.338 / 244.490 | 1.403 / 119.034 | 1.365 / 114.971 |
| Proveedores: líneas | 24.061 | 1.430 | 941 |
| Controllers: líneas | 33.147 | 18.105 | 17.685 |
| Jobs: archivos / líneas | 63 / 2.793 | 32 / 1.193 | 28 / 883 |
| `test/`: archivos / líneas | 1.135 / 201.513 | 646 / 104.045 | 629 / 101.175 |
| Flutter `mobile/`: líneas | 28.011 | 24.502 | 24.486 |
| Tauri / SwiftUI: líneas | 2.402 / 1.557 | 2.402 / 1.157 | 0 / 0 |
| Declaraciones Gemfile / specs lockfile | 99 / 323 | 84 / 276 | 78 / 262 |
| Entradas cron estáticas | 16 | 10 | 8 |
| Tablas del esquema | 158 | 86 | 84 |
| Archivos de locales | 2.463 | 1.946 | 1.886 |

No se ha medido rendimiento ni memoria. Retirar `rack-mini-profiler` y `vernier`
evita cargarlos en producción, sin cifra medida.

## Validación

- Suite completa en Docker: 5.398 pruebas, 23.527 assertions, sin fallos ni
  errores, 38 skips. Una primera ejecución detectó que la migración histórica de
  Trade Republic lee sus etiquetas traducidas; se restauraron y la suite pasa.
- Ensayo de actualización: el esquema de fase 11 cargado en una base aislada y
  migrado reproduce exactamente el `db/schema.rb` nuevo. La prueba de migración
  encadena fases 10 y 12 desde el esquema de fase 9 y comprueba ajustes, clave
  demo eliminada, clave propia conservada, tablas y columnas retiradas.
- Chromium: ajustes, salud del sistema, inmuebles y cuentas (16 pruebas, 133
  assertions, sin fallos).
- RuboCop (1.735 archivos), ERB lint, Brakeman (0 avisos) y Biome pasan.
- OpenAPI regenerado: 289 ejemplos documentales, sin fallos.
- Imagen de producción compilada; eager load completo y `Rack::MiniProfiler` ya
  no se carga.
- No se ha compilado la APK de Flutter en este entorno; el cambio en `mobile/`
  solo retira destinos iOS/web y su configuración de iconos.

## Despliegue

Pendiente: la próxima ejecución de `update-relay.sh` aplica la migración con
backup previo. No requiere cambios en `relay.env`; `RENTCAST_API_KEY` y
`REALIE_API_KEY` dejan de leerse si existían.
