# Inventario y contrato de acceso de API/MCP de Relay

Fecha: 21 de octubre de 2026. Entrega de las fases 0–1 del
[roadmap](relay-api-mcp-roadmap.md). La autorización del usuario para ejecutar
estas fases incorpora la decisión de crear un MCP propio; las fases 2–3 añaden
transporte y operativa cotidiana según el [contrato](../api/mcp.md), y las fases 4–5
incorporan [informes y planificación](../api/reporting-planning.md). Las fases 6–7
añaden [inversión, archivos y procesos](../api/investment-processes.md). Este inventario cubre el producto mantenido, no los
módulos retirados de Sure.

## Evidencia regenerable y criterio de cobertura

[relay-api-surface.json](relay-api-surface.json) enumera las rutas de controladores
propios y sus contratos de strong parameters, incluidos controllers/concerns
compartidos. Cada ruta indica superficie, acción, archivo, fase de entrega y si
solo sirve una pantalla/formulario. Cada fuente incluye un hash que detecta
cambios posteriores. Se excluyen rutas internas de engines y endpoints de prueba.

Generar con `RAILS_ENV=test bundle exec ruby bin/api-surface-inventory` y comprobar
con el mismo comando más `--check`. No consulta la base de datos ni ejecuta
acciones. Las expresiones con constantes o delegación se conservan literalmente:
el contrato efectivo sigue en el modelo/concern referenciado, no se inventa una
lista de campos a partir de una expresión regular.

La matriz siguiente agrupa todas esas rutas en casos de uso. Las rutas de
formulario, diálogos, pickers, navegación, orden y presentación no requieren una
herramienta propia; sí la operación o previsualización que representan. Las
acciones nuevas deben actualizar el inventario y su fila de dominio. No se
declara cobertura completa por contar verbos HTTP.

Leyenda de autoridad:

- **L:** cuenta visible para el actor; **A:** puede anotar; **W:** puede modificar
  datos financieros; **O:** propietario cuando el flujo exige propiedad.
- **F:** dato de organización compartido dentro de la familia, sin acceso a
  movimientos privados por pertenecer a ella.
- **B:** dueño del presupuesto o `BudgetShare`; el presupuesto doméstico es
  compartido. Compartir un presupuesto no comparte sus cuentas.
- **M:** administrador familiar (admin o super_admin de su propia familia).
- **S:** super_admin de instancia para operaciones administrativas globales.
- **H:** interacción humana/reauth/consentimiento exigida por el flujo nativo.
- **P:** gate preview del usuario. Los permisos de credencial siempre se
  intersectan con estas autoridades.

## Matriz funcional

Las rutas exactas y cada acción están en el JSON. El [manifiesto de cierre](relay-api-mcp-coverage.yml)
relaciona los 44 casos con herramientas, evidencia y limitaciones concretas. La
[auditoría y guía de release](../api/mcp-release.md) distingue cobertura delegada,
presencia humana y verificación de producción; no equipara esos resultados.

| ID / caso de uso | Fuentes web y contratos de campos | API actual / herramienta prevista | Autoridad y gates | Efectos, jobs y fase de cierre |
| --- | --- | --- | --- | --- |
| ID-01 autenticarse, renovar, registrar y enlazar SSO | `sessions`, `passkey_sessions`, `registrations`, `oidc_accounts`; `api/v1/auth`, `OauthBase` | API login/signup/refresh/SSO; flujo de conexión OAuth del cliente MCP | Identidad propia, H para contraseña/SSO/passkey | Sesión/token; no movimiento. API existente; MCP F2, paridad H F8 |
| ID-02 consultar contexto y permiso efectivo | `Current`, `Api::Access`, `api/v1/context`, serializer de cuentas | `GET /api/v1/context`, capacidades por cuenta; `get_context` | Credencial read/read_write, usuario activo | Solo lectura, no secretos; API F1, MCP F2 |
| ID-03 perfil, preferencias, onboarding y sesión actual | `users`, `settings/profiles`, `preferences`, `appearance`, `onboardings`, `current_sessions` | Implementado F8; perfil/preferencias y ajustes familiares enumerados; email y onboarding humano nativo | Actor; M para configuración familiar | Nombre/locale/moneda/zona y preferencias; F8 |
| ID-04 sesiones, MFA, passkeys, contraseña y recuperación | `sessions`, `mfa`, `passwords`, `password_resets`, `email_confirmations`, `settings/security`, `webauthn_credentials`, `sso_identities` | Implementado F8; sesiones propias y estado de seguridad; handoffs nativos de contraseña/MFA/passkeys/SSO | Identidad propia y H; sin lectura de secretos | Revoca credenciales; WebAuthn/OTP no se simulan. F8 |
| ID-05 API keys y clientes OAuth | `settings/api_keys`, `oauth/authorizations`, Doorkeeper | Implementado F8; listar/revocar claves y grants propios; emisión/registro en navegador, sin recuperación de secretos | Actor/H, autoridad de administración del cliente | Mostrar clave nueva solo en emisión; nunca recuperar tokens existentes. F2/F8 |
| ID-06 invitaciones, miembros y roles | `invitations`, `invite_codes`, `users`, `admin/users`, `admin/families`, `admin/invitations` | Implementado F8; miembros, invitaciones preparadas/revocación y roles limitados; eliminación/traslado/reset en consola humana | M/S según ámbito; H en cambios sensibles | Jobs `UserPurgeJob`/`FamilyResetJob`; F8 |
| AC-01 listar y consultar cuentas | `accounts`, `Account`, `api/v1/accounts` | Lectura API; `list_accounts`, `get_account` | L; cuentas activas/disabled según contrato | Incluye capacidades por cuenta F1; MCP F2 |
| AC-02 alta y edición por tipo | `AccountableResource`; `depositories`, `credit_cards`, `loans`, `investments`, `cryptos`, `properties`, `vehicles`, `other_assets`, `other_liabilities` | Implementado F3; `create_account`, `update_account` | W/O; nueva cuenta pertenece al actor autorizado | Delegated type, saldo inicial, moneda, subtype, tracking, fiscalidad y campos específicos; sync/recálculo F3/F6 |
| AC-03 archivar, activar, predeterminar, desvincular y borrar | `accounts`, `Account`; decisiones sobre historial antes de borrar | Implementado F3/F8; estado, predeterminada, unlink y borrado con previsualización; cleanup exige autoridad financiera familiar completa | W/O; conexiones M cuando corresponda | Borrado puede ser asíncrono; no borrar historial al cambiar tracking/subtype. F3/F8 |
| AC-04 compartir y participación financiera | `account_sharings`, `AccountShare` | Implementado F8; compartición de owner con previsualización y participación financiera propia | O según web; destino en misma familia | Permisos full_control/read_write/read_only e include_in_finances; invalida ámbitos/caché. F8 |
| TX-01 buscar, consultar, crear, editar y borrar movimientos | `transactions`, `EntryableResource`, `Transaction::Search`; `api/v1/transactions` | Implementado F3 en acciones compartidas; `search_transactions`, `create_transaction`, `update_transaction`, `delete_transaction` | L/A/W; F1 corrige intersección de permisos | Signos contables, campos anotables, protecciones y `sync_account_later`; paridad de campos F3 |
| TX-02 clasificación, gasto compartido, exclusión y previsión | `transactions`, `transaction_categories`, `Transaction`, `Entry` | Implementado F3 en contrato de movimiento compartido | A para notas/categoría/tags/merchant; W para semántica económica | kind, forecast_behavior, excluded, import_protected y shared_expense son independientes. F3 |
| TX-03 dividir/recomponer y operaciones masivas | `splits`, `transactions/bulk_updates`, `bulk_deletions`, `categorizes` | Implementado F3; `split_transaction`, `unsplit_transaction`, `bulk_update_transactions`, `preview_bulk_delete_transactions`, `bulk_delete_transactions`, `preview_categorization` | W/A por campo y cada cuenta | Atomicidad, suma de hijos, padres fuera de agregados y límites por lote; F3 |
| TX-04 duplicados, conversión a trade y desbloqueo | `pending_duplicate_merges`, `transactions` y `trades` | Implementado F3; `merge_duplicate`, `dismiss_duplicate`, `convert_transaction_to_trade`, `unlock_transaction` | W; ambos registros dentro del ámbito | Conservar IDs/referencias según operación, protecciones y recálculo; F3/F6 |
| TR-01 transferir y emparejar movimientos existentes | `transfers`, `transfer_matches`, `Transfer` | Implementado F3; `create_transfer`, `match_transfer`, `update_transfer`, `unlink_transfer`, `delete_transfer` | L en ambos extremos para detalle completo; W en ambos para efectos económicos | Misma/distinta moneda, kinds por frontera y deuda, fechas/tolerancia y comisiones; F3 |
| OR-01 categorías: alta/edición/fusión/borrado/reasignación | `categories`, `category/deletions`, `Category` | Implementado F3; `create_category`, `update_category`, `merge_categories`, `replace_category`, `delete_category` | F; no referencias de otra familia | Jerarquía, color/icon, reasignación; F3 |
| OR-02 comercios y logos propios | `family_merchants`, `Merchant`, `FamilyMerchantAssociation` | Lectura/CSV conservados; alta JSON, edición y fusión F3; logos locales ampliados F8; `create_merchant`, `merge_merchants`, `update_merchant` | F; provider merchants solo si están disponibles para el actor | Logo local/metadatos/CSV; Brandfetch sujeto a ExternalAccess. F3/F8 |
| OR-03 etiquetas y asignación | `tags`, `tag/deletions`, `Tag`, `Tagging` | CRUD API conservado; F3 añade acciones de catálogo, fusión/sustitución y tags por recurso | F en catálogo; A/W para recurso según flujo | Borrado/reasignación familiar, sin acceso a cuentas ocultas; F3 |
| BU-01 listar/consultar presupuesto doméstico y personal | `plans`, `budgets`, `budget_categories`, `BudgetOwnership` | Implementado F5; `list_budgets`, `get_budget`, `list_budget_allocations` | B; importes domésticos derivados limitados al actor | F1 asigna viewer en detalle; presupuesto compartido usa motor nativo. F5 |
| BU-02 asignar, mover fondos, copiar mes, borrar y rollover | `budgets`, `budget_categories`, `Budget::RolloverCalculator` | Implementado F5; crear/editar/borrar, asignar, mover, copiar y recomputar rollover | B escribible; M no implica propiedad personal | Recalcula cadenas; GET API puede materializar carry de cadenas visibles. F5 |
| BU-03 compartir presupuesto y preferencias de hogar | `settings/budget_shares`, preferencias familiares, `BudgetShare` | Implementado F8; listado y cambio de compartición propia con previsualización | Propietario del presupuesto/M en ajuste familiar | El grant no amplía acceso al ledger. F5/F8 |
| AG-01 reglas de pagos previstos | `scheduled_payments`, `ScheduledPayment` | Implementado F5; listar/consultar/crear/editar, estado y borrado de series | Ámbito y writable del modelo, P si lo exige el flujo | Planificar no paga al banco. Periodicidad, importes, fechas, cuenta/contrapartida; F5 |
| AG-02 ocurrencias y estados | `scheduled_payments`, `ScheduledPaymentEntry`, `transactions#retract_scheduled` | Implementado F5; calendario, confirmación/rechazo/retractación/restauración, omisión, reversión futura, purga y generación acotada | W en cuentas afectadas y reglas de acceso de Agenda | Crear/vincular/retractar sin duplicados; jobs y proyección nativos. F5 |
| GO-01 objetivos y cuentas vinculadas | `goals`, `Goal`, `GoalAccount` | Implementado F5; listar/consultar/crear/editar/borrar, transiciones y consumo | P y ámbito/autorización de Goal y cuentas | Active/paused/completed/archived, reopen y consumo parcial; progreso desde datos nativos. F5 |
| GO-02 compromisos de ahorro | `goal_pledges`, `GoalPledge`, reconciliador | Implementado F5; listar/crear/renovar/cancelar/vencer/conciliar compromisos | P, acceso al objetivo y cuenta | Open/matched/cancelled/expired; reconciliación por movimiento/valoración y sweep cron. F5 |
| IN-01 operaciones de inversión | `trades`, `Trade::CreateForm`, `api/v1/trades` | Implementado F6; listado/detalle/alta/edición/borrado y desbloqueo de trades | L/W, ambas cuentas en depósitos/retiradas; F1 corrige ámbitos | Buy/sell/sweep/reinvestment/dividend/interest/fee/deposit/withdrawal; resultado puede ser trade/transaction/transfer. F6 |
| IN-02 posiciones y coste base | `holdings`, `Holding`, materializadores | Implementado F6; coste total/bloqueo, remapeo/reset y borrado con previsualización | L/W | Cantidad, precio, coste y activo local, posiciones autoritativas y recálculo; F6 |
| IN-03 valoraciones y conciliación | `valuations`, `Account::ReconciliationManager` | Implementado F6; listar, previsualizar/conciliar, editar y borrar valoraciones | L/W; F1 corrige detalle/creación/edición | Valor absoluto frente a flujo; upsert conserva su contrato histórico de estado de respuesta. F6 |
| IN-04 valor de cartera gestionada y rendimiento | `investment_values`, `Investment::ValueUpdate`, `roboadvisor_performance` | Lectura F4: `get_investment_report`; F6: `update_managed_portfolio_value` | L/W y cuenta managed_portfolio | Ajuste nativo, no valoración genérica; aportaciones no son rentabilidad. F4/F6 |
| IN-05 valores, precios y FX guardados | `securities`, `security_prices`, `exchange_rates`, modelos de mercado locales | Lectura API y F6: precios/tasas locales y upsert manual | Lectura de valores vinculados a cuentas autorizadas; escritura de precios/FX compartidos exige S y scope write | No proveedores externos; cifras exactas, fecha/moneda, error si falta tasa/precio. F6 |
| RE-01 patrimonio, cash flow y Sankey | `cash_flows`, `BalanceSheet`, `IncomeStatement` | API existente y F4: `get_net_worth`, `get_net_worth_series`, `get_cash_flow` | L y participación financiera del actor | Totales servidor, signo activo/pasivo, FX, período y zona; F4 |
| RE-02 actividad, comparativas y gastos compartidos | `reports`, `Reports::Activity` | Implementado F4; `get_activity_report`, `get_category_report`, `get_shared_expenses`, `get_report_accounts`, `export_transactions` | L y filtro financiero/fiscal nativo | Reembolso compartido por importe completo, gasto 50/50, ahorro ajustado, inversión sin doble conteo; F4 |
| RE-03 series, previsiones e insights | `accountable_sparklines`, `ScheduledPayment::Forecast/WealthForecast`, `insights` | Series/previsiones F4: `get_account_balance_series`, `get_account_forecast`, `get_wealth_forecast`; estado y refresh de insights completados F8/F9 con gates originales | L/P según función; feed familiar exige visibilidad completa F1 | Datos insuficientes explícitos; generación determinista y estados read/acknowledged/expired. F4/F5 |
| RU-01 reglas y ejecuciones | `rules`, `Rule`, `RuleRun`, jobs de reglas | Implementado F7; ciclo de configuración, opciones, previsualización, ejecución y runs | M con visibilidad completa; escritura requiere W en todas las cuentas; ejecución limitada a 100 coincidencias | Condiciones/acciones typed, resultados/job; no ejecutar texto libre. F7 |
| IM-01 importación guiada por formato | `imports`, `import/{uploads,configurations,cleans,confirms,mappings,rows,qif_category_selections}` | Implementado F7; archivos, configuración, filas/mappings, plantillas, selección QIF, publicación y reversión con previsualización | M con visibilidad completa y W en todas las cuentas para escribir | CSV, trades, cuentas, Mint/Actual/YNAB/QIF, categorías/reglas/comercios; mappings, filas, plantillas, ImportJob. F7 |
| IM-02 intercambio NDJSON y sesiones por bloques | `api/v1/imports`, `api/v1/import_sessions`, `ImportSession`, `RelayImport` | Implementado F7; creación, bloques con checksum, estado, previsualización y publicación de sesión | M, scope adecuado, snapshot requiere condiciones del lector | IDs de sesión/bloque, orden, checksum y reintentos propios; F7 añade registro de operación compartido API/MCP. F7 |
| DO-01 Statement Vault y adjuntos | `account_statements`, `transaction_attachments`, `AccountStatement`, ActiveStorage | Implementado F7; metadatos, originales, duplicados, vínculos y adjuntos; canal binario autenticado | L/W/M según nativo y archivo; originales nunca públicos | MIME/tamaño/deduplicación, vincular/desvincular, almacenar PDF sin extraer IA. F7 |
| BA-01 exportación/restauración familiar | `family_exports`, `archived_exports`, `Family::Backup`, jobs de export/import | Implementado F7; listar/detalle/crear/cancelar/borrar, descarga autorizada, `validate_backup` y `restore_backup` | M con visibilidad completa y W para escribir; restauración exige destino vacío y previsualización firmada | ZIP con originales, escape nativo de cancelación, borrado de exports, informe de omisiones y restauración sintética. F7 |
| SY-01 sincronización y recálculo | `syncs`, `accounts#sync`, `settings/providers`, `Family::Syncer`, `Account::Recalculator` | Implementado F8; Sync consultable, recálculo local por cuenta, sync familiar/bancario y cancelación cooperativa | M para sync familiar; L para historial propio; W para futuro recálculo por cuenta | No precios externos; Sidekiq/SyncJob, hijos, cancelación limitada al trabajo pendiente. F8 |
| EX-01 Enable Banking | `enable_banking_items`, modelos/adapter de proveedor | Implementado F8; estado y cuentas cacheadas, setup/link/unlink y sync; configuración, banco y SCA mediante handoff humano | M, H bancario y `ExternalAccess.bank_sync` | Metadata/consentimiento, procesamiento/importación; no órdenes bancarias de pago. F8 |
| EX-02 Drive y logos externos | `google_drive_connections`, `oauth_configurations`, `export_schedules`, settings de acceso | Implementado F8; conexión propia, programaciones, ejecución/runs, logos locales y acceso externo; OAuth/configuración mediante handoff humano | M/H según conexión; capabilities externas apagadas hasta habilitación | Exportación programada y logos; no se activan por disponer de credenciales. F8 |
| AD-01 configuración, diagnóstico y trabajos | `settings/hosting`, `debug`, `background_jobs`, `admin/system_health`, `admin/sso_providers`, `sso_identity_blocks` | Implementado F8; ajustes no secretos enumerados con previsualización, diagnóstico depurado y trabajos; límites administrativos explícitos | M/S/H según operación; no se delega la limpieza histórica que borra FX/precios globales | Secrets redactados, cancelación nativa, sin shell/SQL/settings arbitrarios. F8 |
| UI-01 navegación, preferencias de presentación y ayuda | `pages`, `release_highlights`, `currencies`, dropdowns, pickers, PWA, `settings/guides`, Lookbook | No tool por formulario/ruta visual; datos útiles en contexto o endpoints del dominio | Actor/entorno según web | Cambiar layout o mostrar modal no es mutación financiera; preferencias sincronizables F8, resto presentación |
| CT-01 impersonación y operación del host | `impersonation_sessions`; actualizador y backups de servidor fuera de Rails | Sin tool genérica de impersonación, shell o despliegue; no confundir con backup familiar | Flujo humano administrativo existente; host fuera del ámbito API del producto | Exclusión deliberada de automatización MCP genérica; no ampliar Current.user desde argumentos del cliente |

## Contratos de campos y variantes

El JSON vincula cada familia de rutas al archivo y a todas sus expresiones
`permit`, también en concerns de tipos de cuenta e importación. Los siguientes
conceptos deben conservar identidad aunque un cliente los presente juntos:

| Dominio | Contrato y variantes que deben comprobarse en su fase |
| --- | --- |
| Cuenta | Los nueve tipos Accountable; activos/pasivos; subtipos vigentes de inversión y lectura de históricos; owner, compartición, moneda, tratamiento financiero/fiscal, tracking y estado |
| Movimiento | entry ID frente a transaction/trade ID; importe exacto, fecha, moneda, name/notes; category/merchant/tags; kind, forecast_behavior, excluded, shared_expense; protecciones de importación/usuario/campo |
| Referencias | Cuenta en misma familia y con permiso; categorías/tags de familia; comercio disponible para el actor; cuenta destino también autorizada; padres/hijos e IDs de matching dentro de ámbito |
| Dinero/fecha | Importe decimal finito, moneda y precisión separadas; importes de ledger positivos=salida, negativos=entrada; valoraciones absolutas. Preservar `amount` formateado y campos cents/signados existentes; fechas ISO y zona familiar |
| Inversión | security/ticker/manual_ticker, mercado, qty/price/fee, tipo/label, cuenta de contrapartida; valor objetivo gestionado usa ValueUpdate. No introducir proveedores |
| Planificación | Agenda: fecha/programación/estado por ocurrencia; Goal: target/cuentas/estado/consumo; pledge: tipo derivado de cuenta, expiración y matching; presupuesto: owner, mes, allocation/carry/share |
| Importación | Raw/upload, tipo, col_sep, formatos de fecha/número/signos, labels/mappings, filas omitidas, parámetros de preflight, client_session_id/chunk_id/sequence y originales/checksums; constantes quedan referenciadas en fuente |
| Seguridad | Token scope frente a permiso de cuenta, rol y gates; sin family_id arbitrario, owner_id o credenciales mass-assigned fuera de un flujo autorizado |

No todos esos campos están ya soportados por la API. El inventario de expresiones
marca lo efectivamente admitido; la fila de dominio asigna su paridad restante a
la fase correspondiente. Las acciones compartidas de F3 incluyen `shared_expense`,
clasificaciones, estado de contabilización y protecciones; esta cobertura no se
atribuye retroactivamente a F1.

## Política de acceso implementada en fase 1

1. La clave `read` solo lee. `read_write` permite intentar escrituras, sujetas al
   permiso del recurso. Los tokens existentes no cambian de formato ni scopes.
2. Cuenta propia/full_control: datos financieros. Cuenta read_write: solo
   categoría, tags, comercio y notas. Cuenta read_only: lectura. Admin no obtiene
   acceso financiero directo a una cuenta privada de otro usuario por su rol.
3. Recurso invisible: 404; recurso visible pero acción no autorizada: 403.
   Referencias inválidas y decimales/fechas mal formados: 422. Falta de parámetros
   requeridos: 400. Mantener mensajes heredados donde ya los esperan clientes.
4. Crear/importar/restaurar/listar archivos de importación de familia, sesiones
   por bloques, sync familiar y metadata de conexiones requieren M además del
   scope. Son operaciones familiares sin identidad por cuenta en los jobs
   actuales; no se finge que la credencial del trabajador limita su alcance.
   Es un endurecimiento deliberado respecto del API anterior. F7 podrá ofrecer
   importación acotada por cuenta con autoridad persistida y revisada al ejecutar.
5. Los backups familiares ya exigían M; se conserva ese contrato. Los resúmenes
   familiares de insights requieren además P y visibilidad completa, porque sus
   textos no permiten filtrar con seguridad por cuenta. No se devuelven Bills.
6. Un miembro no administrador ve trabajos de cuentas accesibles; no ve jobs
   familiares/proveedor ni sus identificadores parent/hijos privados. Los
   administradores conservan estado operativo familiar sin conceder por ello
   lectura directa de los movimientos de cuentas privadas.
7. La contrapartida de una transferencia se omite si no es visible. Modificar
   su importe/fecha/naturaleza o borrar una pata exige W en ambas cuentas.
8. El contexto autenticado sustituye cualquier sesión web; credencial bearer
   rechazada no hace fallback a otra identidad enviada simultáneamente. Todas
   las respuestas API se marcan `private, no-store`.
9. No se introduce una segunda jerarquía de roles ni scopes MCP persistidos en
   esta fase. La delegación acotada ya se aplica como intersección en
   `Api::Access`; discovery/consentimiento/audiencia y autorización por herramienta
   pertenecen a F2 y no se anuncian como implementados.

## Contratos de resultado y transición

- `GET /api/v1/context`: actor/familia, método/scopes, capacidades generales,
  zona y contratos. `mcp: false` evita anunciar un transporte inexistente.
- Las cuentas añaden `capabilities: {read, annotate, write}` sin retirar campos.
  Un true indica permiso potencial del actor, no que toda operación futura exista.
- Entradas monetarias revisadas usan `Api::Input`/BigDecimal; filtros no convierten
  basura en cero ni aceptan NaN/Infinity. Los motores actuales conservan validación
  de dominio y recálculo. No se reescribe el dinero formateado de v1.
- Error de conversión conserva el campo `error` heredado y añade `code` estable
  (`missing_conversion`/`missing_price`) y detalle. En los demás errores comunes,
  `error` sigue siendo el código existente. La documentación registra esta
  compatibilidad en lugar de cambiar todos los envelopes de golpe.
- Idempotencia existente de transacciones: account/source/external_id recuperan
  el registro original; no se cambia silenciosamente al contrato futuro de
  fingerprint/409. Sesiones/chunks y conciliación conservan sus semánticas
  documentadas. F3/F7 implementarán el contrato ampliado de reintentos/concurrencia.
- La escritura puede estar guardada con saldo aún pendiente de recálculo. El
  inventario identifica jobs y efectos; no se promete saldo actualizado antes de
  completar los workers. F2 y fases de dominio expondrán seguimiento uniforme.
- No hay migraciones, dependencias nuevas, transportes, proveedores ni cambios
  en los datos financieros de producción durante estas fases.

## Validación de cierre

Minitest de endpoints existentes más regresiones de límites de acceso y contexto;
integración separada de OAuth/sesión; OpenAPI regenerado desde rswag documental.
La evidencia de ejecución y publicación está en el apartado de estado del roadmap.
La cobertura de permisos incluye otra familia, cuenta privada de misma familia,
anotador, read_only, full_control, administrador, invitado, usuario inactivo y
credencial revocada, según las pruebas de cada flujo.

Este inventario se mantiene junto al producto: una función añadida o retirada no
queda cubierta por un documento histórico de poda ni por el catálogo antiguo.
