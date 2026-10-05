# Poda fase 9 — Curación de extensiones restantes

Ejecutada el 5 de octubre de 2026 a petición de Steve («continúa con la fase 9»),
con las preferencias finales ya registradas en el [plan](pruning-plan.md).
HEAD inicial: `eca54c6b7`; `main` sincronizado con `origin/main`.
Implementación validada localmente en `main`, sin commit/push, migraciones de
esquema ni operaciones sobre TrueNAS, colas o datos reales.

## Resolución por bloque

| Bloque | Resolución | Estado |
| --- | --- | --- |
| 9A. Mercado y divisas | Retirada la adquisición externa de precios y tipos de cambio | Implementado |
| 9B. Logos | Brandfetch conservado sin cambios funcionales | Conservado |
| 9C. Plan, presupuestos, Goals e insights | Conservados sin cambios | Conservado |
| 9D. Google Drive | Conservado sin cambios | Conservado |
| 9E. Acceso y almacenamiento | Acceso íntegro conservado; Active Storage solo local | Implementado |
| 9F. Clientes nativos y FinanceKit | FinanceKit retirado; demás clientes conservados | Implementado |

Los bloques 9A, 9E y 9F son independientes: cada uno puede publicarse o
revertirse por separado sin dejar referencias rotas en los otros.

## 9E — Almacenamiento local

- `config/storage.yml` solo define `local` (disco en `storage/`) y `test`.
  Se eliminan los servicios Amazon S3, Cloudflare R2, S3 genérico y Google
  Cloud Storage, junto con `aws-sdk-s3`, `google-cloud-storage` y sus
  dependencias exclusivas en `Gemfile.lock`. Google Drive no las usa.
- Desarrollo y producción fijan `:local`. Un `ACTIVE_STORAGE_SERVICE` distinto
  de `local` (o vacío) detiene el arranque con un mensaje explícito, en lugar
  de servir adjuntos ausentes. Los compose de TrueNAS y local ya usan `local`.
- Las plantillas `.env*` documentan el almacenamiento local y dejan de ofrecer
  variables S3/R2/GCS. El sidecar de backups de base de datos con rclone es
  hosting y no se modifica.
- **Transición:** si una instalación tuviera blobs con `service_name` remoto,
  sus ficheros deben copiarse a `storage/` y verificarse antes de actualizar,
  como trabajo operativo aparte. Comprobación de solo lectura:
  `SELECT service_name, count(*) FROM active_storage_blobs GROUP BY 1;`.
  Este trabajo no ha inspeccionado la base de Steve; su compose usa `local`.

## 9F — FinanceKit

- Retirados la API `/api/v1/financekit/*` (capacidades, conexiones, mapeos,
  activación, credenciales, reparación, conflictos y subida de lotes), el
  módulo `Financekit` y su procesamiento, purga, diagnóstico y descarga,
  `Provider::FinancekitAdapter`, `ProviderDisconnectable`, el panel Apple Wallet
  de ajustes, la sección de cuentas Wallet, el aviso de desvinculación, el cron
  `process_financekit_inbox`, los throttles y filtros de parámetros exclusivos,
  los datos de demostración Apple Wallet, su tarea rake, su esquema JSON,
  la guía de operador y las traducciones exclusivas.
- `FinancekitInboxJob` y `FinancekitPurgeJob` quedan como consumidores sin
  efectos para trabajos ya serializados. El arranque del worker elimina el cron
  persistido aunque el acceso bancario esté activo. No se purga Redis.
- Los siete modelos (`FinancekitItem`, `FinancekitAccountLineage`,
  `FinancekitAccount`, `FinancekitBatch`, `FinancekitTransaction`,
  `FinancekitBalanceObservation`, `FinancekitConflict`) conservan solo nombres,
  tablas y relaciones para backup, GlobalID, tenencia y borrado explícito de
  familia. `FinanceKit` se añade a `RetiredAccountConnector`: syncs antiguos
  terminan como `stale`, `DestroyJob` no borra sus filas y no hay adapter.
- Las cuentas enlazadas antes de la retirada se muestran con las cuentas
  ordinarias; conservan su vínculo histórico y estrategia de saldo. Desvincular
  elimina solo el vínculo, sin tocar movimientos ni filas FinanceKit.
- `GET /api/v1/provider_connections` deja de listar FinanceKit; OpenAPI se
  regenera sin sus rutas, esquemas ni el esquema de seguridad de publicador.
  Los clientes nativos del repositorio no usan FinanceKit: no cambian contratos
  de OAuth, push ni API compartidos. Las plantillas del generador de proveedores
  ya no dependen de `ProviderDisconnectable`.

## 9A — Mercado y divisas

Criterio: el resultado se comporta como Relay con la antigua capacidad
`market_data` apagada, y se elimina todo lo que solo existía para adquirir datos.

- Retirados Twelve Data, Yahoo Finance, Tiingo, EODHD, Alpha Vantage, Mansa,
  MFAPI, Binance público, MOEX, Frankfurter y T-Invest, los conceptos
  `SecurityConcept`/`ExchangeRateConcept`, los importadores de precios y tipos,
  `MarketDataImporter` (global y por cuenta), el comprobador de salud, el
  rastreador de restricciones de plan, la reparación de precios de Varsovia,
  la búsqueda de valores por proveedor (`/securities`), la sincronización
  manual de precios de una posición y su selección de proveedor.
- Retirada la capacidad `market_data` de `ExternalAccess`, sus ajustes
  (`external_market_data_enabled`, claves API, proveedor de divisas y lista de
  proveedores de valores), su sección de ajustes de instancia y sus variables
  de entorno. Los valores ya guardados quedan en la tabla `settings` sin lector,
  pendientes de la fase 10.
- `ImportMarketDataJob`, `SecurityHealthCheckJob` y `YahooFinanceHealthCheckJob`
  terminan sin efectos; el worker elimina los cron `import_market_data` y
  `run_security_health_checks` persistidos.
- `ExchangeRate.find_rate` y `ExchangeRate.rates_for` solo leen tipos guardados
  (fecha exacta o los cinco días previos); nunca crean filas. Los precios salen
  de `security_prices`, de operaciones y de posiciones. Si falta un dato, el
  recálculo falla explícitamente y conserva los saldos anteriores, como antes.
  `Security::MissingPriceError` sustituye al error del concern retirado.
- Las operaciones, conversiones a operación, reasignaciones de posición e
  importaciones resuelven tickers contra la base o crean valores locales
  (`offline`). La reasignación de una posición acepta `TICKER` o
  `TICKER|MIC` escritos, sin búsqueda externa.
- Se retiran los avisos que pedían configurar un proveedor (barra lateral de
  cuentas e importación de operaciones), el aviso de historial FX limitado y
  los avisos de proveedor desactivado/historial truncado de posiciones y
  operaciones.
- Se conservan monedas, multimoneda, tipos manuales por movimiento, precios y
  tipos guardados, Brandfetch (también para cripto almacenada con el antiguo
  MIC `BNCX`) y las valoraciones inmobiliarias RentCast/Realie, que no forman
  parte de esta selección.
- `ExchangeRatePair` queda como persistencia histórica de backup global, sin
  lógica. La API de valores mantiene sus campos (`price_provider`,
  `offline_reason`, `first_provider_price_on`) para no romper clientes; las
  columnas se tratan en fase 10.
- **Limitación aceptada:** sin proveedor, el valor de mercado de una inversión
  solo avanza con operaciones, posiciones importadas o valoraciones; Relay no
  inventa precios ni tipos.

## Residuos detectados para fase 10/11

No forman parte de la selección de esta fase y no se han modificado:
traducciones de chat/IA y de proveedores LLM en ajustes, `system_health`,
paneles de conectores retirados en otros idiomas, el parcial
`_categorization_shadow_results`, `Provider::HttpTransport` y
`Provider::EvmExplorer` sin consumidores, cassettes VCR de OpenAI/Plaid/Stripe,
guías `docs/hosting` de conectores retirados y las tablas, columnas y ajustes
históricos de FinanceKit, mercado, Bills, IA y plataforma comercial.

## Verificación

Ejecutada en el entorno Docker de pruebas, sin datos personales ni backups de
instalación. Las ejecuciones intermedias fallidas no cuentan como cierre verde.

- Rails completo definitivo: 5.631 pruebas, 24.521 aserciones, 0 fallos,
  0 errores y las 38 omisiones previas (`tmp/phase9-rails-final.log`). Con
  9E+9F antes de 9A: 5.983 pruebas, 0 fallos/errores (`tmp/phase9ef-rails.log`).
- RuboCop: 1.891 archivos sin infracciones. ERB lint sin errores. Biome: 134
  archivos sin errores. Brakeman: 0 errores y 0 avisos; señala tres exclusiones
  obsoletas anteriores a esta fase (SnapTrade y exports), no modificadas
  (`tmp/phase9-quality.log`).
- OpenAPI regenerado: 291 ejemplos, 0 fallos; sin rutas ni esquemas FinanceKit.
  Comprobador de consistencia API correcto (`tmp/phase9-openapi.log`,
  `tmp/phase9-api-consistency.log`).
- Imagen de producción construida con assets; eager loading sin red correcto con
  variables de mercado antiguas definidas. Con `ACTIVE_STORAGE_SERVICE=amazon`
  el arranque se detiene con el mensaje de transición
  (`tmp/phase9-production-boot*.log`).
- Backup: ida y vuelta de filas históricas FinanceKit con vínculo de cuenta,
  movimiento y conflicto; suite de backups 32 pruebas en verde.
- Navegador: una ejecución completa (137 pruebas) mostró un único error, una
  expectativa de la cuadrícula «Disponibles» que ya no aplica sin Apple Wallet;
  corregida, su archivo pasa (13 pruebas). Steve prefiere probar él la interfaz,
  así que no se repite la suite completa de navegador.
- No se ensaya la restauración de un backup real ni se inspecciona TrueNAS.

## Publicación y reversión

Commit/push requieren la confirmación del resultado conforme a
[AGENTS.md](../../AGENTS.md). Despliegue: actualizar web y worker juntos y
dejar `ACTIVE_STORAGE_SERVICE` sin definir o en `local`. No hay migraciones.

Reversión por bloque con el código anterior: 9E devuelve los drivers remotos
(sin mover ficheros); 9F devuelve la API y el inbox (las conexiones históricas
conservan su estado; ningún dispositivo de este repositorio publica); 9A devuelve los proveedores, que siguen
requiriendo activación explícita. Los datos históricos se conservan en todos
los casos.
