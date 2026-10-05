# Fase 10 — limpieza definitiva de persistencia

5 de octubre de 2026. Base: fase 9 publicada en `d2e790ed6`.
Selección autorizada: eliminar completamente los residuos exclusivos de módulos
retirados, manteniendo el resultado financiero del producto conservado.
Preparada sobre `main`, sin aplicarla a TrueNAS ni a datos de instalación durante la preparación.
Publicada en `origin/main` en `eaf35e3ff`. La auditoría de colas de fase 11 (5 de octubre
de 2026) muestra que TrueNAS ejecuta todavía `d2e790ed6` (fase 9): la migración de
esta fase no se ha aplicado en la instalación y lo hará la siguiente actualización.

## Esquema y datos descartados

La nueva migración `20261005120000_remove_retired_product_persistence.rb` mantiene
intactas las migraciones históricas. Su constante `TABLES` es el inventario exacto
de las 72 tablas eliminadas, con sus índices y constraints exclusivos:

- Pares Item/Account de Akahu, Binance, Brex, Coinbase, Coinspot, Coinstats,
  FinanceKit, Fio, IBKR, Indexa Capital, Kraken, Lunchflow, Mercury, Monobank,
  Onchain Wallet, Plaid, Questrade, Redbark, SimpleFIN, SnapTrade, Sophtron,
  Trade Republic, Trading212, Up y Wise; FinanceKit incluye también lineage,
  batches, transacciones, observaciones de saldo y conflictos.
- Las seis tablas Bills: series detectadas, reglas, ocurrencias, asignaciones,
  cambios de precio y rechazos de matching. No se convierten a Agenda.
- Chats, mensajes, tool calls, comparaciones de categorización, uso LLM,
  suscripciones comerciales, pares de tipos de cambio y las cuatro tablas eval.

Se eliminan enlaces `AccountProvider` de esos conectores y sus `Sync` exclusivos;
los hijos de esos syncs conservados quedan sin padre. Se eliminan mappings hacia
registros retirados e insights exclusivos `cash_flow_warning`/`subscription_audit`.
`provider_request_counts` permanece: RentCast/Realie todavía lo utilizan.

Columnas eliminadas:

| Tabla | Columnas |
| --- | --- |
| accounts | plaid_account_id, simplefin_account_id |
| entries | plaid_id (sin consumidores vigentes; source/external_id permanecen) |
| families | ai_prompt_overrides, assistant_type, bills_feed_token, categorization_confidence_threshold, categorization_provider, categorization_shadow_rate, data_enrichment_enabled, recurring_transactions_disabled, stripe_customer_id, vector_store_id |
| users | ai_enabled, show_ai_sidebar, last_viewed_chat_id |
| family_documents | provider_file_id |
| securities | price_provider, offline_reason, failed_fetch_at, failed_fetch_count, first_provider_price_on |

`SETTINGS` enumera las preferencias y credenciales persistidas de IA, asistentes
externos y cotizaciones/tipos externos que se borran. La eliminación es por clave
exacta; Brandfetch, Drive y las capacidades externas conservadas permanecen.
Esto no borra variables de entorno ni copias de seguridad externas.

Se eliminan adjuntos cuyos propietarios son conexiones o conversaciones retiradas.
No se borran archivos del almacenamiento ni blobs compartidos desde la migración.
El posible purge de blobs huérfanos requiere un trabajo separado con inventario,
backup y verificación de propietarios; no se ejecuta automáticamente aquí.

## Preservación financiera y código

Las cuentas financieras permanecen con sus IDs, movimientos, balances, permisos,
reconciliaciones, importaciones y originales soportados. Antes de borrar enlaces:

- `accounts.reverse_balance_history` conserva la estrategia de cuentas antes
  conectadas. Pueden operar como manuales sin recalcular con una estrategia distinta.
- `holdings.imported_snapshot` marca sus posiciones como autoritativas y vacía el
  enlace retirado. Materialización, normalización y selección de posiciones las
  conservan frente a cálculos y purgas de filas calculadas.
- `accounts.imported_balance_history` conserva para IBKR los balances ya guardados
  en la divisa de la cuenta. `Account::ImportedBalanceHistory` aplica estas
  observaciones locales; no lee payloads ni clases de conexión antiguas.
- `accounts.imported_performance` conserva sólo `performance_history` de Indexa;
  `managed_portfolio` conserva la semántica de cartera gestionada, también para
  pensiones. El lector de cifrado vive dentro de la migración y desaparece del
  runtime del producto. Un error de lectura aborta la migración transaccional.

Se retiran modelos, asociaciones, fixtures y pruebas exclusivamente históricas;
las pruebas de contabilidad/autorización pasan a conexiones Enable Banking o datos
locales. No se añaden dependencias. Enable Banking, Brandfetch, Drive,
RentCast/Realie, OAuth/API/MFA/passkeys, clientes conservados, Agenda, presupuestos,
Goals, insights vigentes y multimoneda siguen soportados.

Los sinks de jobs antiguos permanecen hasta auditar queued/retry/scheduled en
fase 11. No se purgan colas. `AssistantResponseJob` ya no necesita modelos de chat;
los GlobalID retirados se descartan mediante la política de deserialización existente.

## Recuperación y contratos

Los backups nuevos contienen el producto soportado, con sus originales; mantienen
ZIP versión 3 y snapshot versión 1. Los antiguos validan manifest y bytes antes de
aplicar `Family::Backup::DiscardPolicy`, una allowlist de nombres y campos sin
modelos históricos. El informe `retired_data_discarded` cuenta registros, adjuntos
y atributos descartados; readback declara `scope: supported_product`.
Se conservan las conversiones financieras anteriores al descartar enlaces.
Referencias financieras faltantes, módulos/campos desconocidos y bytes corruptos
siguen fallando; un payload Indexa enlazado ausente falla explícitamente.

La recuperación del historial exclusivo descartado exige un backup completo de
servidor y código anterior compatible. Una exportación familiar actual ya no lo
contiene. Los imports Bills legacy avisan y cuentan omisiones, conservando los
movimientos ordinarios. No se ejecutan detección, generación ni sincronizaciones
remotas al restaurar. Ver [backups](../llm-guides/backups.md).

API: securities deja de emitir `offline_reason`/`first_provider_price_on`;
reset/status deja de contar `plaid_items`/`recurring_transactions`.
Las verificaciones de imports añaden `scope: supported_product`; los legacy
añaden `discarded_record_counts` y warnings con código, mensaje y conteos.
La autenticación
con `X-Api-Key`, permisos familiares y demás contratos permanecen. Los predicados
de IA siguen devolviendo falso donde los clientes conservados los necesitan,
sin columnas persistidas que puedan activarla.

## Operación y reversión

`up` usa una transacción Rails. ALTER/DROP requieren locks exclusivos y las
actualizaciones de cuentas/posiciones/syncs/mappings/settings generan WAL y filas
muertas. El dump previo de PostgreSQL y originales locales, la parada coordinada
de escritores/workers y un ensayo con copia de la instalación son prerrequisitos
antes de operar datos reales. Ejecutar sólo cuando se autorice ese trabajo.

No hay conteos, duración ni ahorro de espacio medidos en la instalación. El ensayo
sintético no representa volumen, cifrado o concurrencia reales. Los drops liberan
relaciones; las actualizaciones pueden necesitar autovacuum, sin imponer VACUUM
FULL ni mantenimiento bloqueante automático. Reservar espacio para backup y WAL.

`down` lanza `ActiveRecord::IrreversibleMigration`. Recrear tablas vacías o revertir
Git no recupera datos. La recuperación completa restaura PostgreSQL y originales
con código compatible; perdería escrituras posteriores al backup salvo un plan
separado de reconciliación. Mantener web y workers en la misma revisión.

## Validación

El entorno Docker `relay-tests` recrea exclusivamente su base de pruebas para que
una carga de esquema no deje tablas desaparecidas. La prueba de actualización
carga el esquema completo de fase 9 en un namespace PostgreSQL aislado y ejecuta
la nueva migración; comprueba saldos, posiciones, rendimiento, settings conservados,
tablas/columnas retiradas y rechazo de rollback ficticio. La instalación nueva se
ensaya cargando el esquema actual. Los round trips verifican originales, producto
soportado, omisiones, nueva exportación y restauración repetida.

Evidencia confirmada:

- 82 pruebas focalizadas de migración, recuperación, listado de cuentas y
  materialización: 443 assertions, sin fallos, errores ni skips.
- 136 pruebas adicionales de informe legacy, API de imports y migración:
  838 assertions, sin fallos, errores ni skips. API y readback distinguen
  verificación del núcleo de recuperación de módulos descartados.
- Ensayo de actualización con cifrado configurado: 1 prueba, 104 assertions,
  sin fallos; 0,481 segundos de migración con datos sintéticos. Incluye payloads
  en claro y cifrados, sin cambiar la configuración global. El esquema nuevo
  y el actualizado coinciden en tablas, columnas, tipos, defaults y nulabilidad.
- Chromium: 18 pruebas de imports/cuentas, 120 assertions, sin fallos ni skips.
  Incluye aviso de omisiones antes de publicar y round trip de ZIP con originales.
- RuboCop, ERB lint, Biome lint y Brakeman pasan; sin nuevos warnings de seguridad.
- Imagen de producción compilada y eager load completo sin red.
- OpenAPI regenerado: 291 ejemplos documentales, sin fallos. Se retiran también
  las assertions duplicadas de rswag de transferencias; su cobertura equivalente
  ya existe en Minitest. Verificación de consistencia pasa: todas las specs usan
  API key, ninguna contiene assertions y todos los controladores API v1 tienen
  archivo de cobertura Minitest.
- Suite completa final: 5.562 pruebas, 24.227 assertions, sin fallos ni errores,
  38 skips. Carga de esquema, compilación de assets y prueba de actualización
  incluidas en el entorno aislado; `bin/rails test` termina con código 0.

No se ha reensayado en esta fase el archivo privado de Sure ni inspeccionado TrueNAS.
