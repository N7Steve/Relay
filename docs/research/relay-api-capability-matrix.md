# Inventario y contrato de acceso de API/MCP de Relay

Fecha: 21 de octubre de 2026. Entrega de las fases 0–1 del
[roadmap](relay-api-mcp-roadmap.md). La autorización del usuario para ejecutar
estas fases incorpora la decisión de crear un MCP propio; el transporte sigue
pendiente de la fase 2. Este inventario cubre el producto mantenido, no los
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

Las rutas exactas y cada acción están en el JSON. «Parcial» significa que existen
endpoints, no que todas las variantes y campos ya estén cubiertos.

| ID / caso de uso | Fuentes web y contratos de campos | API actual / herramienta prevista | Autoridad y gates | Efectos, jobs y fase de cierre |
| --- | --- | --- | --- | --- |
| ID-01 autenticarse, renovar, registrar y enlazar SSO | `sessions`, `passkey_sessions`, `registrations`, `oidc_accounts`; `api/v1/auth`, `OauthBase` | API login/signup/refresh/SSO; flujo de conexión OAuth del cliente MCP | Identidad propia, H para contraseña/SSO/passkey | Sesión/token; no movimiento. API existente; MCP F2, paridad H F8 |
| ID-02 consultar contexto y permiso efectivo | `Current`, `Api::Access`, `api/v1/context`, serializer de cuentas | `GET /api/v1/context`, capacidades por cuenta; `get_context` | Credencial read/read_write, usuario activo | Solo lectura, no secretos; API F1, MCP F2 |
| ID-03 perfil, preferencias, onboarding y sesión actual | `users`, `settings/profiles`, `preferences`, `appearance`, `onboardings`, `current_sessions` | Parcial auth/ajustes familiares; `update_profile`, `update_preferences` | Actor; M para configuración familiar | Nombre/locale/moneda/zona y preferencias; F8 |
| ID-04 sesiones, MFA, passkeys, contraseña y recuperación | `sessions`, `mfa`, `passwords`, `password_resets`, `email_confirmations`, `settings/security`, `webauthn_credentials`, `sso_identities` | Flujos específicos pendientes; `list_sessions`, `revoke_session`, inicio de flujos H | Identidad propia y H; sin lectura de secretos | Revoca credenciales; WebAuthn/OTP no se simulan. F8 |
| ID-05 API keys y clientes OAuth | `settings/api_keys`, `oauth/authorizations`, Doorkeeper | API de gestión pendiente; configuración/consentimiento MCP F2 | Actor/H, autoridad de administración del cliente | Mostrar clave nueva solo en emisión; nunca recuperar tokens existentes. F2/F8 |
| ID-06 invitaciones, miembros y roles | `invitations`, `invite_codes`, `users`, `admin/users`, `admin/families`, `admin/invitations` | Parcial borrado propio/reset; herramientas de gestión explícitas | M/S según ámbito; H en cambios sensibles | Jobs `UserPurgeJob`/`FamilyResetJob`; F8 |
| AC-01 listar y consultar cuentas | `accounts`, `Account`, `api/v1/accounts` | Lectura API; `list_accounts`, `get_account` | L; cuentas activas/disabled según contrato | Incluye capacidades por cuenta F1; MCP F2 |
| AC-02 alta y edición por tipo | `AccountableResource`; `depositories`, `credit_cards`, `loans`, `investments`, `cryptos`, `properties`, `vehicles`, `other_assets`, `other_liabilities` | Pendiente; `create_account`, `update_account` | W/O; nueva cuenta pertenece al actor autorizado | Delegated type, saldo inicial, moneda, subtype, tracking, fiscalidad y campos específicos; sync/recálculo F3/F6 |
| AC-03 archivar, activar, predeterminar, desvincular y borrar | `accounts`, `Account`; decisiones sobre historial antes de borrar | Pendiente; operaciones de cuenta con nombre propio | W/O; conexiones M cuando corresponda | Borrado puede ser asíncrono; no borrar historial al cambiar tracking/subtype. F3/F8 |
| AC-04 compartir y participación financiera | `account_sharings`, `AccountShare` | Pendiente; `share_account`, `update_account_share` | O según web; destino en misma familia | Permisos full_control/read_write/read_only e include_in_finances; invalida ámbitos/caché. F8 |
| TX-01 buscar, consultar, crear, editar y borrar movimientos | `transactions`, `EntryableResource`, `Transaction::Search`; `api/v1/transactions` | CRUD parcial; `search_transactions`, `create_transaction`, `update_transaction`, `delete_transaction` | L/A/W; F1 corrige intersección de permisos | Signos contables, campos anotables, protecciones y `sync_account_later`; paridad de campos F3 |
| TX-02 clasificación, gasto compartido, exclusión y previsión | `transactions`, `transaction_categories`, `Transaction`, `Entry` | Campos parciales; actualizar contrato de movimiento | A para notas/categoría/tags/merchant; W para semántica económica | kind, forecast_behavior, posting_status, excluded, import_protected y shared_expense son independientes. F3 |
| TX-03 dividir/recomponer y operaciones masivas | `splits`, `transactions/bulk_updates`, `bulk_deletions`, `categorizes` | Pendiente; `split_transaction`, `update_transactions`, `delete_transactions`, `preview_categorization` | W/A por campo y cada cuenta | Atomicidad, suma de hijos, padres fuera de agregados y límites por lote; F3 |
| TX-04 duplicados, conversión a trade y desbloqueo | `pending_duplicate_merges`, `transactions` y `trades` | Pendiente; `merge_duplicate`, `dismiss_duplicate`, `convert_transaction_to_trade`, `unlock_entry` | W; ambos registros dentro del ámbito | Conservar IDs/referencias según operación, protecciones y recálculo; F3/F6 |
| TR-01 transferir y emparejar movimientos existentes | `transfers`, `transfer_matches`, `Transfer` | Lectura de transferencias/rechazos; `create_transfer`, `match_transfer`, `update_transfer`, `unmatch_transfer` | L en ambos extremos para detalle completo; W en ambos para efectos económicos | Misma/distinta moneda, kinds por frontera y deuda, fechas/tolerancia y comisiones; F3 |
| OR-01 categorías: alta/edición/fusión/borrado/reasignación | `categories`, `category/deletions`, `Category` | Lectura/alta API; `create_category`, `update_category`, `merge_categories`, `delete_category` | F; no referencias de otra familia | Jerarquía, color/icon, reasignación; F3 |
| OR-02 comercios y logos propios | `family_merchants`, `Merchant`, `FamilyMerchantAssociation` | Lectura y alta por CSV (no alta JSON individual); `create_merchant`, `merge_merchants`, `update_merchant` | F; provider merchants solo si están disponibles para el actor | Logo local/metadatos/CSV; Brandfetch sujeto a ExternalAccess. F3/F8 |
| OR-03 etiquetas y asignación | `tags`, `tag/deletions`, `Tag`, `Tagging` | CRUD API; `manage_tags`, cambios de tags por recurso | F en catálogo; A/W para recurso según flujo | Borrado/reasignación familiar, sin acceso a cuentas ocultas; F3 |
| BU-01 listar/consultar presupuesto doméstico y personal | `plans`, `budgets`, `budget_categories`, `BudgetOwnership` | API lectura parcial; `get_budget` | B; importes domésticos derivados limitados al actor | F1 asigna viewer en detalle; presupuesto compartido usa motor nativo. F5 |
| BU-02 asignar, mover fondos, copiar mes, borrar y rollover | `budgets`, `budget_categories`, `Budget::RolloverCalculator` | Pendiente; `update_budget_allocation`, `move_budget_funds`, `copy_budget` | B escribible; M no implica propiedad personal | Recalcula cadenas; GET API puede materializar carry de cadenas visibles. F5 |
| BU-03 compartir presupuesto y preferencias de hogar | `settings/budget_shares`, preferencias familiares, `BudgetShare` | Pendiente; `share_budget` | Propietario del presupuesto/M en ajuste familiar | El grant no amplía acceso al ledger. F5/F8 |
| AG-01 reglas de pagos previstos | `scheduled_payments`, `ScheduledPayment` | Ausente; `list_scheduled_payments`, `create_scheduled_payment`, `update_scheduled_payment` | Ámbito y writable del modelo, P si lo exige el flujo | Planificar no paga al banco. Periodicidad, importes, fechas, cuenta/contrapartida; F5 |
| AG-02 ocurrencias y estados | `scheduled_payments`, `ScheduledPaymentEntry`, `transactions#retract_scheduled` | Ausente; `confirm_scheduled_entry`, `reject_scheduled_entry`, `restore_scheduled_entry`, `skip_scheduled_date`, `run_scheduled_payments` | W en cuentas afectadas y reglas de acceso de Agenda | Crear/vincular/retractar sin duplicados; jobs y proyección nativos. F5 |
| GO-01 objetivos y cuentas vinculadas | `goals`, `Goal`, `GoalAccount` | Ausente; `create_goal`, `update_goal`, `transition_goal`, `record_goal_consumption` | P y ámbito/autorización de Goal y cuentas | Active/paused/completed/archived, reopen y consumo parcial; progreso desde datos nativos. F5 |
| GO-02 compromisos de ahorro | `goal_pledges`, `GoalPledge`, reconciliador | Ausente; `create_goal_pledge`, `renew_goal_pledge`, `cancel_goal_pledge` | P, acceso al objetivo y cuenta | Open/matched/cancelled/expired; reconciliación por movimiento/valoración y sweep cron. F5 |
| IN-01 operaciones de inversión | `trades`, `Trade::CreateForm`, `api/v1/trades` | CRUD API parcial; `create_trade`, `update_trade`, `delete_trade` | L/W, ambas cuentas en depósitos/retiradas; F1 corrige ámbitos | Buy/sell/sweep/reinvestment/dividend/interest/fee/deposit/withdrawal; resultado puede ser trade/transaction/transfer. F6 |
| IN-02 posiciones y coste base | `holdings`, `Holding`, materializadores | API lectura; `update_holding`, `unlock_cost_basis`, `remap_security`, `reset_security` | L/W | Cantidad, precio, coste y activo local, posiciones autoritativas y recálculo; F6 |
| IN-03 valoraciones y conciliación | `valuations`, `Account::ReconciliationManager` | Lectura/alta/edición API; `reconcile_account` | L/W; F1 corrige detalle/creación/edición | Valor absoluto frente a flujo; upsert conserva su contrato histórico de estado de respuesta. F6 |
| IN-04 valor de cartera gestionada y rendimiento | `investment_values`, `Investment::ValueUpdate`, `roboadvisor_performance` | Pendiente; `update_managed_portfolio_value`, `get_investment_performance` | L/W y cuenta managed_portfolio | Ajuste nativo, no valoración genérica; aportaciones no son rentabilidad. F4/F6 |
| IN-05 valores, precios y FX guardados | `securities`, `security_prices`, `exchange_rates`, modelos de mercado locales | Valores/precios lectura API; contratos de escritura local pendientes | Lectura solo valores vinculados a cuentas autorizadas; escritura global requiere decisión específica F6 | No proveedores externos; cifras exactas, fecha/moneda, error si falta tasa/precio. F6 |
| RE-01 patrimonio, cash flow y Sankey | `cash_flows`, `BalanceSheet`, `IncomeStatement` | API existente; `get_balance_sheet`, `get_cash_flow` | L y participación financiera del actor | Totales servidor, signo activo/pasivo, FX, período y zona; F4 |
| RE-02 actividad, comparativas y gastos compartidos | `reports`, `Reports::Activity` | Pendiente; `get_activity_report`, `get_shared_expense_balance`, `export_report` | L y filtro financiero/fiscal nativo | Reembolso compartido por importe completo, gasto 50/50, ahorro ajustado, inversión sin doble conteo; F4 |
| RE-03 series, previsiones e insights | `accountable_sparklines`, `ScheduledPayment::Forecast/WealthForecast`, `insights` | Insights parcial; `get_account_series`, `get_wealth_forecast`, `list_insights`, `acknowledge_insight` | L/P según función; feed familiar exige visibilidad completa F1 | Datos insuficientes explícitos; generación determinista y estados read/acknowledged/expired. F4/F5 |
| RU-01 reglas y ejecuciones | `rules`, `Rule`, `RuleRun`, jobs de reglas | API lectura; `preview_rule_run`, `apply_rule`, `create_rule`, `update_rule` | Configuración F; ejecución debe restringir cuentas o exigir M | Condiciones/acciones typed, resultados/job; no ejecutar texto libre. F7 |
| IM-01 importación guiada por formato | `imports`, `import/{uploads,configurations,cleans,confirms,mappings,rows,qif_category_selections}` | API parcial; `start_import`, `configure_import`, `preview_import`, `publish_import`, `cancel_import`, `revert_import` | M para API actual familiar F1; alcance por cuenta a diseñar F7 | CSV, trades, cuentas, Mint/Actual/YNAB/QIF, categorías/reglas/comercios; mappings, filas, plantillas, ImportJob. F7 |
| IM-02 intercambio NDJSON y sesiones por bloques | `api/v1/imports`, `api/v1/import_sessions`, `ImportSession`, `RelayImport` | API existente; `upload_import_chunk`, `publish_import_session`, `get_import_session` | M, scope adecuado, snapshot requiere condiciones del lector | IDs de sesión/bloque, orden, checksum y reintentos propios; no nueva semántica de idempotencia F1. F7 |
| DO-01 Statement Vault y adjuntos | `account_statements`, `transaction_attachments`, `AccountStatement`, ActiveStorage | Ausente; `upload_document`, `link_statement`, `reject_statement`, `download_attachment` | L/W/M según nativo y archivo; originales nunca públicos | MIME/tamaño/deduplicación, vincular/desvincular, almacenar PDF sin extraer IA. F7 |
| BA-01 exportación/restauración familiar | `family_exports`, `archived_exports`, `Family::Backup`, jobs de export/import | Crear/listar/detalle/descargar API; `create_family_backup`, `restore_family_backup` | M; H/política concreta para restaurar datos | ZIP con originales, cancelación/borrado pendientes, informe de omisiones y recuperación sintética. F7 |
| SY-01 sincronización y recálculo | `syncs`, `accounts#sync`, `settings/providers`, `Family::Syncer`, `Account::Recalculator` | API sync familiar e historial; `sync_family`, `recalculate_account`, `get_sync`, `cancel_sync` | M para sync familiar; L para historial propio; W para futuro recálculo por cuenta | No precios externos; Sidekiq/SyncJob, hijos, cancelación limitada al trabajo pendiente. F8 |
| EX-01 Enable Banking | `enable_banking_items`, modelos/adapter de proveedor | API estado familiar M; herramientas de iniciar/consultar/reautorizar/vincular/desvincular | M, H bancario y `ExternalAccess.bank_sync` | Metadata/consentimiento, procesamiento/importación; no órdenes bancarias de pago. F8 |
| EX-02 Drive y logos externos | `google_drive_connections`, `oauth_configurations`, `export_schedules`, settings de acceso | Ausente; `connect_drive`, `schedule_export`, `run_drive_export`, `get_external_access` | M/H según conexión; capabilities externas apagadas hasta habilitación | Exportación programada y logos; no se activan por disponer de credenciales. F8 |
| AD-01 configuración, diagnóstico y trabajos | `settings/hosting`, `debug`, `background_jobs`, `admin/system_health`, `admin/sso_providers`, `sso_identity_blocks` | Pendiente; herramientas de estado/configuración permitida | M/S/H según operación | Secrets redactados, cancelación nativa, sin shell/SQL/settings arbitrarios. F8 |
| UI-01 navegación, preferencias de presentación y ayuda | `pages`, `release_highlights`, `currencies`, dropdowns, pickers, PWA, `settings/guides`, Lookbook | No tool por formulario/ruta visual; datos útiles en contexto o endpoints del dominio | Actor/entorno según web | Cambiar layout o mostrar modal no es mutación financiera; preferencias sincronizables F8, resto presentación |
| CT-01 impersonación y operación del host | `impersonation_sessions`; actualizador y backups de servidor fuera de Rails | Sin tool genérica de impersonación, shell o despliegue; no confundir con backup familiar | Flujo humano administrativo existente; host fuera del ámbito API del producto | Exclusión deliberada de automatización MCP genérica; no ampliar Current.user desde argumentos del cliente |

## Contratos de campos y variantes

El JSON vincula cada familia de rutas al archivo y a todas sus expresiones
`permit`, también en concerns de tipos de cuenta e importación. Los siguientes
conceptos deben conservar identidad aunque un cliente los presente juntos:

| Dominio | Contrato y variantes que deben comprobarse en su fase |
| --- | --- |
| Cuenta | Los nueve tipos Accountable; activos/pasivos; subtipos vigentes de inversión y lectura de históricos; owner, compartición, moneda, tratamiento financiero/fiscal, tracking y estado |
| Movimiento | entry ID frente a transaction/trade ID; importe exacto, fecha, moneda, name/notes; category/merchant/tags; kind, forecast_behavior, posting_status, excluded, shared_expense; protecciones de importación/usuario/campo |
| Referencias | Cuenta en misma familia y con permiso; categorías/tags de familia; comercio disponible para el actor; cuenta destino también autorizada; padres/hijos e IDs de matching dentro de ámbito |
| Dinero/fecha | Importe decimal finito, moneda y precisión separadas; importes de ledger positivos=salida, negativos=entrada; valoraciones absolutas. Preservar `amount` formateado y campos cents/signados existentes; fechas ISO y zona familiar |
| Inversión | security/ticker/manual_ticker, mercado, qty/price/fee, tipo/label, cuenta de contrapartida; valor objetivo gestionado usa ValueUpdate. No introducir proveedores |
| Planificación | Agenda: fecha/programación/estado por ocurrencia; Goal: target/cuentas/estado/consumo; pledge: tipo derivado de cuenta, expiración y matching; presupuesto: owner, mes, allocation/carry/share |
| Importación | Raw/upload, tipo, col_sep, formatos de fecha/número/signos, labels/mappings, filas omitidas, parámetros de preflight, client_session_id/chunk_id/sequence y originales/checksums; constantes quedan referenciadas en fuente |
| Seguridad | Token scope frente a permiso de cuenta, rol y gates; sin family_id arbitrario, owner_id o credenciales mass-assigned fuera de un flujo autorizado |

No todos esos campos están ya soportados por la API. El inventario de expresiones
marca lo efectivamente admitido; la fila de dominio asigna su paridad restante a
la fase correspondiente. Particularmente, `shared_expense` y las clasificaciones
financieras completas siguen siendo trabajo de F3, no se declaran hechos en F1.

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
