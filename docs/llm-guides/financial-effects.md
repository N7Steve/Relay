# Efectos financieros actuales

Primeras entregas de la simplificación del dominio, 6 de octubre de 2026.
Esta matriz describe el código preparado. Las opciones 1A–10A del
[formulario](../research/financial-domain-decisions.md) fueron aprobadas por el
usuario el 7 de octubre de 2026; su ejecución sigue el orden 10A.
La investigación original está en
[financial-domain-simplification](../research/financial-domain-simplification.md).

## Selección de movimientos

`Entry.eligible_for_balance` reúne `excluding_pending` y
`excluding_split_parents`. Conserva movimientos excluidos de analítica, trades
y valoraciones. `Balance::SyncCache` consume esta selección: las valoraciones
son valores absolutos; no se suman como ingresos.

`Entry.eligible_for_forecast_history` parte de esa selección, limita a
transacciones existentes y exige `excluded = false`. La usan las previsiones
de cuenta y patrimonio antes de aplicar sus propias reglas estadísticas.

Ambos scopes conservan el ámbito recibido. No conceden permisos ni seleccionan
familias, cuentas, fechas o monedas. El llamador debe mantener esos filtros.

| Caso | Saldo de cuenta | Informe/presupuesto de ingresos y gastos | Historial base de previsión |
| --- | --- | --- | --- |
| Compra normal contabilizada | Reduce efectivo en cuenta de activo | Gasto | Incluida |
| Ingreso normal contabilizado | Aumenta efectivo en cuenta de activo | Ingreso | Incluido |
| Excepcional (`forecast_behavior = exceptional_once` o `one_time` histórico) | Conserva efecto económico | Excluido por la política común `budget_reportable` | Incluido en base; retirado del residual ordinario |
| Irregular recurrente | Conserva efecto económico | Incluido si no hay otra exclusión | Incluido en base; reserva separada |
| `excluded = true` | Conserva efecto económico | Excluido | Excluido |
| Pendiente de proveedor actual o histórico | Excluido hasta contabilización | Excluido en el scope predeterminado de IncomeStatement | Excluido |
| Padre de división | Excluido para evitar duplicación | `split!` lo marca excluido | Excluido |
| Hijos de división 60/40 | Total 100, aunque el hijo de 40 esté excluido | Solo 60 si el hijo de 40 está excluido | Solo el hijo de 60 en ese caso |
| Valoración | Ancla absoluta de valor/deuda | No es Transaction | Excluida |
| Ajuste nativo de cartera gestionada | Diferencia firmada; los nuevos cierres conservan el total declarado | Excluido de ingresos/gastos y de pendiente de categorizar | Rendimiento de inversión, separado del residual de gastos |
| Trade | Movimiento de efectivo y posiciones | Excluido de IncomeStatement::Totals | Excluido |

Los informes tienen filtros adicionales por estado de cuenta, tratamiento,
participación personal, fiscalidad y actividad de inversión. Un scope de
transacciones suministrado expresamente a `IncomeStatement#totals` sustituye al
predeterminado; no se debe asumir que excluye pendientes automáticamente.

## Transferencias y patrimonio

Cada extremo conserva el efecto sobre su cuenta. En la previsión de cuenta,
los kinds de transferencia no entran en el residual histórico ordinario;
Agenda proyecta los movimientos planificados. En la previsión patrimonial,
una transferencia emparejada se considera interna si ambas cuentas pertenecen
al conjunto de activos históricos seleccionado. No sustituir esta decisión
por una exclusión universal de todos los kinds de transferencia.

| Naturaleza | Kind de salida | Tratamiento en ingresos/gastos |
| --- | --- | --- |
| Transferencia ordinaria dentro de la frontera | `funds_movement` | Excluido |
| Pago de tarjeta u otra deuda distinta de Loan | `cc_payment` | Excluido |
| Pago de préstamo | `loan_payment` | Gasto de la salida; entrada `funds_movement` excluida |
| Aportación desde cuenta no inversora hacia Investment/Crypto | `investment_contribution` | Excluido actualmente |
| Salida hacia fuera de finanzas | `transfer_to_excluded` | Gasto del extremo dentro de finanzas |
| Entrada desde fuera de finanzas | `transfer_from_excluded` | Ingreso del extremo dentro de finanzas |

Las transferencias vinculadas a carteras gestionadas tienen nombre determinista
y clasificación nativa de solo lectura en ambos extremos. No admiten categorías
personalizadas ni aparecen como pendientes de categorizar. Esta presentación no
cambia los kinds, importes ni reglas de frontera de la tabla anterior.

Una cuenta `tracking` queda fuera de informes pero no cambia la frontera de
transferencias. `outside_finances` queda fuera y establece la frontera.
Archivar afecta la navegación, no equivale a excluir de finanzas. El patrimonio
usa saldos y posiciones de las cuentas seleccionadas, con signos de
activo/pasivo y conversión de monedas; no es la suma de este informe de gastos.

## Protección, matching y permisos

### Excepcionales y compatibilidad histórica

`kind` mantiene la naturaleza financiera. Cambiar `forecast_behavior` no lo
reescribe: una transferencia/pago de préstamo excepcional conserva su kind.
`Transaction.budget_reportable` y su fragmento SQL común excluyen excepcionales
además de los kinds históricamente excluidos; informes, desgloses de presupuesto
y gastos compartidos usan esa política. Las aportaciones siguen excluidas (2A).

El valor `one_time` sigue en el enum como entrada/almacenamiento histórico.
Los lectores de previsión y presupuesto lo reconocen sin migrar datos en masa.
Al guardar por la vía validada se normaliza a `standard` más comportamiento
excepcional, salvo elección explícita de comportamiento. El importador NDJSON
interpreta `one_time` + `normal` antiguo como excepcional; la restauración
relacional conserva los atributos originales y los lectores los entienden.
Las divisiones heredan el comportamiento para preservar exclusión y saldo.

Este adaptador puede retirarse únicamente después de inventariar/normalizar todas
las filas `one_time` y de mantener su traducción en los lectores versionados de
backups históricos. No se elimina el contrato de importación antes de eso.

### FX en agregados de ingresos y gastos

Totals, DailyExpenseTotals, FamilyStats y CategoryStats aplican 6A: identidad
solo para la misma moneda; las otras conversiones necesitan tasa guardada en la
fecha consultada. La misma consulta detecta tasas ausentes dentro del ámbito real
del informe. Antes de devolver filas lanza `Money::ConversionError` con moneda
origen/destino y fecha; no devuelve una suma parcial ni una conversión 1:1 ficticia.
El manejo web existente responde con datos insuficientes, sin total convertido.

Las cachés cambian de versión e incluyen moneda y frescura de tasas/cuentas.
Las pruebas de equivalencia con la consulta anterior comparan datos con tasa
conocida; el fallo por FX ausente tiene pruebas específicas. La misma detección
se aplica a búsqueda, totales/rentabilidad de inversión, coste medio de posiciones
y series patrimoniales/de plusvalías. Las series conservan la selección histórica
de tasa guardada (LOCF/primera posterior), pero no inventan una tasa si no hay
ninguna. Los CSV conservan importe y moneda originales sin convertirlos.

### Protección, Agenda y emparejamiento

`import_protected` expresa protección independiente de `excluded`. En filas
históricas con NULL conserva la protección implícita anterior; al editarlas,
se persiste antes de cambiar la exclusión. En altas nuevas excluir no añade esa
protección. `user_modified`, `import_locked`, locks por campo y protección
estructural de splits siguen vigentes. `unlock_for_sync!` limpia expresamente la
protección aunque el movimiento continúe excluido de analítica.

Matching de transferencias, pendientes/posted y Agenda son operaciones distintas.
El autoemparejamiento conserva candidatos/tolerancias, pero exige que la pareja
sea la alternativa única preferida para ambos extremos. Prefiere coincidencia
exacta antes de FX y después menor distancia de fechas. Los empates quedan para
revisión, sin desempatar por orden de filas ni tras consumir otras parejas.
La revisión manual muestra candidatos de cuentas editables.
`ScheduledPayment#explains_forecast_entry?` concentra la heurística de ambas
previsiones: título sin diferencias de mayúsculas/espacios, sentido del efectivo,
importe dentro del 10% (35% si es estimado) y ocurrencia a cinco días o menos.
Son tolerancias de previsión, distintas de las usadas para vincular históricos
de forma persistente (5%/40%).

Ambas previsiones exigen igualdad de cuenta y moneda en la heurística. La de
cuenta convierte el residual histórico a su moneda con tasa guardada para la
fecha; no suma cantidades nominales de monedas distintas.

`ScheduledPayment::HistoryExplanation` prioriza vínculos confirmados válidos de
ambos extremos, aunque difieran título/importe. Rechazados/skipped no explican
movimientos. El mismo predicado retira evidencia de residual y reserva irregular
sin duplicarla. Se conserva `include_agenda: false` y la selección autorizada.

La lectura necesita cuentas accesibles dentro de la familia. La participación
financiera usa `User#finance_accounts`, que no equivale a todas las cuentas
visibles. La edición económica requiere propietario/control total; anotación
admite además `read_write`. Transferencias comprueban ambos extremos. Ningún
scope nuevo reemplaza esas comprobaciones.

## Validación y siguiente unidad

### Transferencias y conectores

`Transaction#paired_transfer` identifica la pareja de la que el movimiento es
un extremo; `Transaction#fee_transfer` identifica la operación a la que pertenece
una comisión. La columna de comisiones sigue siendo `transactions.transfer_id`.
`Transfer#fee_transactions` conserva esa clave y hace explícita la asociación
inversa. `Transaction#transfer` mantiene la lectura anterior como compatibilidad
para consumidores web existentes; puede retirarse cuando todos sus lectores se
migren a `paired_transfer`. Los lectores financieros de Agenda, previsión,
creación idempotente y exportación CSV ya usan el nombre explícito.

`Transfer#reclassify_transactions!` actualiza ambos kinds dentro de un savepoint.
Lo utilizan matching manual, matching automático y cambios de frontera de cuenta.
Los permisos, categorías, orden de candidatos y programación de recálculos siguen
en sus recorridos actuales. Creator y Agenda siguen asignando kinds al construir
los extremos mediante `outflow_kind_for`/`inflow_kind_for`; no se ha sustituido todo
el ciclo de creación/desenlace por una operación nueva ni endurecido índices.

La factoría de conectores resuelve únicamente Enable Banking en cada llamada.
Se han retirado descubrimiento por archivos, registro mutable y autorregistro.
El generador mantiene scaffolding pero no activa proveedores nuevos. Los lectores
de metadatos pending históricos, importación de holdings/trades y recuperación
de backups siguen presentes. Los backups completos usan versión 2 y conservan
compatibilidad de lectura con la versión 1; el NDJSON mantiene su versión.

### Comprobaciones

`test/models/entry/financial_eligibility_test.rb` caracteriza exclusión analítica,
protección, pendientes de todos los proveedores conservados, división/unsplit,
tipos de movimiento, trades/valoraciones y conservación de cuenta/fecha.
También comprueba los importes reportados para compra, irregular, préstamo,
cruces de frontera y kinds excluidos del presupuesto frente al saldo conservado.
Las suites existentes de SyncCache y ambas previsiones verifican consumidores.
`forecast_explanation_test.rb` cubre título/sentido, límites de tolerancia,
fechas, recurrencia, fin de serie y comparación de monedas.
`forecast_agenda_test.rb` comprueba los resultados públicos de ambas previsiones,
los vínculos explícitos, moneda, series coincidentes y Agenda desactivada.
También comprueba que una serie de otra cuenta no explique estos movimientos.
Las pruebas añadidas a `transfer_test.rb` cubren los dos significados de
transferencia, borrado/rechazo con comisiones, clasificación y rollback.
`provider/factory_test.rb` cubre resolución, tipos soportados, disponibilidad,
conexiones opcionales y fallos explícitos. `family/backup_test.rb` añade un
round trip de los extremos y la FK de comisión, para verificar remapeo de IDs.
En Docker pasan 436 pruebas focalizadas (2.549 aserciones) y la suite completa:
5.460 pruebas, 23.856 aserciones, sin fallos ni errores y con 38 omisiones.
RuboCop, ERB lint, Biome y Brakeman pasan. Las pruebas de navegador se registran
en el formulario de decisiones.

Las pruebas adicionales cubren divisas faltantes, protección independiente,
pending/posted, empates, catálogo y fiscalidad/seguimiento sin borrar trades.
Los backups completos v2 conservan atributos independientes y los v1 siguen
admitidos con traducción de protección. La migración preparada añade columnas
nullable; la lectura compatible mantiene significado histórico. El inventario
real y las restricciones finales de integridad requieren una copia aislada.
Consulta el [plan por etapas](../migration/financial-domain-stages.md).
Las decisiones de política y persistencia están en el
[formulario de decisiones](../research/financial-domain-decisions.md).
