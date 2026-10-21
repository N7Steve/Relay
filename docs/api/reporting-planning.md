# API/MCP: informes y planificación (fases 4–5)

Estas operaciones usan el transporte y la autenticación del [contrato MCP](mcp.md).
Cada nombre tiene también su ruta fija `POST /api/v1/actions/<nombre>`, con
`{"arguments": {...}}`. El catálogo y OpenAPI describen los campos admitidos.
No cambian las rutas REST anteriores. Las escrituras requieren scope read_write,
permiso efectivo del recurso y `idempotency_key`, compartida entre API y MCP.

## Informes y consultas

| Herramienta | Motor nativo y resultado |
| --- | --- |
| `get_report_accounts` | Cuentas accesibles, participación financiera, fiscalidad y elegibilidad para informes de efectivo e inversión; paginado |
| `get_activity_report` | `Reports::Activity`, comparación con el período anterior de igual duración, ahorro neto y ajustado y gasto compartido |
| `get_category_report` | `IncomeStatement.net_category_totals`, categorías netas, totales y pesos |
| `get_shared_expenses` | `SharedExpensesCalculator`: deuda/compensaciones acumuladas, gasto ajustado del período e ingresos de rentas |
| `get_investment_report` | `InvestmentStatement`: aportaciones, retiradas, dividendos, intereses, efectivo, posiciones, ganancias y rentabilidad, con desglose gestionado y fiscalidad |
| `get_net_worth` | `BalanceSheet` con el actor autenticado; activos, pasivos y patrimonio |
| `get_net_worth_series` | Series históricas nativas de patrimonio |
| `get_account_balance_series` | Series de cuenta: balance, cash_balance, holdings_balance o gains |
| `export_transactions` | CSV paginado de la misma búsqueda de movimientos, con filtros, signos e importes en moneda original |
| `get_account_forecast`, `get_wealth_forecast` | Motores existentes de previsión, escenarios, historial y efecto de Agenda |

Los informes reciben fechas ISO `start_date`/`end_date`, ordenadas. Su límite
es 3.660 días; las series, 731 días. Los filtros `account_ids` se intersectan con
las cuentas autorizadas y elegibles; una selección excluida o no disponible se
rechaza, en vez de devolver silenciosamente un total parcial. Las series de una
cuenta requieren lectura de esa cuenta. Las colecciones y el CSV se paginan con
`page`, `per_page` (1–100), `total_count` y `next_page`.

Los informes conservan la moneda familiar de la web; las series de cuenta y las
filas de exportación conservan su propia moneda. Los objetos monetarios se
devuelven con `amount` decimal y `currency`. No hay proveedores nuevos ni
conversiones inventadas. FX ausente devuelve el error financiero correspondiente;
si un motor de previsión registra conversiones incompletas, no se entrega su
proyección parcial como si fuera completa.

Los totales se calculan en Relay, con la selección de pendientes, divisiones,
movimientos excepcionales, transferencias de frontera, rendimientos gestionados
y fiscalidad de los motores originales. Se distingue expresamente entre acceso
a una cuenta y participación en las finanzas. La frescura informa de la hora de
generación y del estado de recálculo de las cuentas seleccionadas; no promete
que una escritura recién confirmada haya terminado de recalcularse.

El CSV protege nombres/notas que podrían interpretarse como fórmulas. Una
respuesta demasiado grande sigue devolviendo un error explícito para reducir
página/período, conforme al límite de respuesta MCP. No se expone un enlace
público a datos financieros ni se solicita al asistente reconstruir agregados.

## Presupuestos

Operaciones: `list_budgets`, `get_budget`, `list_budget_allocations`,
`create_budget`, `update_budget`, `update_budget_allocation`, `move_budget_funds`,
`copy_budget`, `recompute_budget_rollover` y `delete_budget`.

Crear selecciona el mes según el calendario familiar. `household: true`
selecciona el presupuesto doméstico cuando está habilitado; sin él se conserva
la selección nativa de presupuesto personal/doméstico según la configuración.
Los presupuestos personales de otros miembros requieren `BudgetShare`; una
compartición read_only permite consultar sus importes, pero no escribir. Ser
administrador no sustituye esa propiedad o compartición.

Los datos incluyen importes previstos y reales, asignación, dinero disponible,
carry, efectivo, fondos reservados para Goals y efectivo libre. Las asignaciones
se paginan aparte. Copiar requiere un origen anterior de la misma familia y
cadena de propietario, y un destino sin inicializar. El borrado elimina el plan,
sin borrar movimientos. El motor nativo conserva monedas y jerarquías en rollover.

La integración toma el bloqueo asesor de la cadena antes de las filas de
asignación, y lo comparte con `Budget::RolloverCalculator`. Así el registro
idempotente y la recomputación se confirman en la misma transacción sin invertir
el orden de los bloqueos. Leer un presupuesto/asignaciones puede materializar
rollover, como la web; no concede permiso de editar asignaciones.

## Agenda

Operaciones: `list_scheduled_payments`, `get_scheduled_payment`, `get_agenda`,
`create_scheduled_payment`, `update_scheduled_payment`,
`set_scheduled_payment_status`, `delete_scheduled_payment`,
`confirm_scheduled_date`, `skip_scheduled_date`, `run_scheduled_payments` y
`confirm/reject/retract/restore/revert_future/purge_pending_scheduled_entry`.

El calendario conserva las ocurrencias calculadas y las persistidas, sus
estados, importes estimados y monedas separadas. Crear puede enlazar historial
mediante un `from_transaction_id` autorizado de la misma cuenta. Actualizar
reutiliza `sync_confirmed_entries!`, sin reinterpretar importes ya confirmados.
La activación solicita un estado deseado y no reactiva series completadas.

Confirmar fecha/ocurrencia usa los bloqueos y la unicidad del modelo y no crea
dos movimientos al reintentarse. Las transferencias requieren escritura en
ambos extremos. Modificar una serie comprueba también las cuentas de sus
movimientos históricos. Retractar suelta las referencias antes de eliminar el
movimiento; restaurar una fecha pasada vuelve a confirmarla, y una futura
recupera su representación programada. No equivale a enviar dinero al banco.

`run_scheduled_payments` genera lo pendiente de **una serie explícita**, con un
límite de 100 ocurrencias por operación y rollback si lo excede. No ejecuta un
job familiar sin alcance ni reactiva Bills.

## Goals y compromisos

Operaciones: `list_goals`, `get_goal`, `create_goal`, `update_goal`,
`transition_goal`, `delete_goal`, `record_goal_consumption`, `list_goal_pledges`,
`create_goal_pledge`, `renew_goal_pledge`, `cancel_goal_pledge`,
`expire_goal_pledge` y `reconcile_goal_pledge`.

Todas conservan el gate `preview_features_enabled?`. Un Goal con cuentas
vinculadas o compromisos históricos inaccesibles queda fuera del ámbito: no se
devuelve un balance parcial etiquetado como balance completo. Las escrituras
exigen permiso financiero sobre sus cuentas y los nuevos vínculos. No se
aceptan cambios de familia o propietario desde el payload.

`accounts` contiene objetos `{account_id, allocated_amount}`; omitir asignación
mantiene la política nativa de cuenta completa, y null la solicita explícitamente.
La modificación de vínculos y sus asignaciones se guarda a través del Goal,
manteniendo validaciones de moneda, tipos financiables, exclusividad y reservas.
Los tipos one_off/maintained, los modos fixed/months_of_expenses y sus objetivos
derivados usan el modelo existente. Las transiciones admitidas son pause,
resume, complete, archive, unarchive y reopen, siempre bajo sus guardas AASM.

Consumir una cantidad parcial libera la reserva según `Goal#consume!`; puede
atribuirse a un movimiento de salida elegible mediante `transaction_id`, con
permiso en la cuenta. Un Goal mantenido no se convierte en un objetivo consumible.
Borrar un Goal elimina sus vínculos/compromisos y su metadata asociada, sin
eliminar cuentas o movimientos.

El tipo de compromiso se deriva de la conexión de su cuenta: manual_save o
transfer. Su moneda es la del Goal. Renovación, cancelación y vencimiento usan
el ciclo existente; no se permite vencer por API un compromiso aún vigente.
La conciliación explícita de un compromiso transfer exige entrada contabilizada,
no excluida, en su cuenta, ventana e importe tolerados, y conserva la regla de
una sola reclamación. Los compromisos manual_save siguen resolviéndose por el
delta de valoración a través de `Account::ReconciliationManager`, como en la web;
no se les inventa una transacción ni un supuesto ingreso.

## Verificación y publicación

Las pruebas de API usan `X-Api-Key`; rswag sigue siendo solo documental.
La batería compara resultados con los motores nativos y cubre permisos, FX,
signos, categorías, series, exportaciones, reintentos y ciclos de planificación.
La prueba con el SDK oficial amplía el recorrido HTTP a informes, presupuestos,
confirmación/retractación de Agenda y Goals. El roadmap registra los resultados.
Estas fases no añaden migraciones: permanece pendiente de despliegue la
migración preparada en la fase 2. No se ha publicado ni desplegado TrueNAS.
