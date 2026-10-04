# Contratos de recuperación para la poda

Fase 1, 4 de octubre de 2026. El nombre `BackupRecord.data.model` es un contrato
persistido, no necesariamente el nombre de una clase activa de producto.
El ZIP financiero sigue siendo versión 3 y el snapshot relacional versión 1.
No se introducen formatos alternativos ni un registro genérico de plugins.

## Disposición por módulo

| Dominio y modelos | Disposición | Referencias sensibles antes de una retirada |
| --- | --- | --- |
| Núcleo: Family, User, Account, AccountShare, nueve Accountable y Address | Conservar modelos y datos | Family/User, propietarios/shares, User.default_account_id y last_viewed_chat_id, polymorphic accountable, Address→Property; autenticación no portable |
| Entry, Transaction, Trade, Valuation, Balance, Holding, AccountProvider | Conservar datos; convertir conexiones solo con equivalencia ensayada | entryable/accountable polimórfico, import_id, reconciled_by_statement_id, proveedor/holding; signos, reverse/forward y multimoneda |
| Category, Tag, Merchant, MerchantCustomization, FamilyMerchantAssociation, Tagging | Conservar taxonomía y originales | Merchants compartidos vs familia, Rule operands, tags polimórficos, logos locales/Brandfetch |
| Transfer, RejectedTransfer | Conservar | Dos movimientos, fechas/divisas, comisiones y referencias cíclicas de Transaction |
| Rule, Rule::Condition, Rule::Action, RuleRun, NotificationDelivery | Conservar reglas locales | UUID en operands/texto/JSON y deduplicación; al quitar una acción IA adaptar su regla explícitamente |
| ScheduledPayment, ScheduledPaymentEntry | Conservar Agenda | account/target_account, entry/transfer_entry, categorías/tags, estados y próxima ejecución |
| Security, Security::Price, ExchangeRate, ExchangeRatePair | Conservar históricos y cálculos | Registros compartidos nunca sobrescritos; currencies de entries/holdings/Goals; proveedores de mercado se eligen aparte |
| Import, ImportSession, ImportSourceMapping, Import::Row, Import::Mapping | Conservar lectores y originales históricos | STI RelayImport/SureImport y otros tipos, sesiones/chunks/GlobalID, mappings polimórficos y source IDs; no sustituir import completo por import de movimientos |
| FamilyDocument, AccountStatement | Conservar originales locales e historia | Recibos, reconciliación, adjuntos Active Storage, documentos que nunca guardaron original; vector indexes remotos no portables |
| Chat, Message, ToolCall | **Lectores históricos implementados en fase 1** | Chat→User, Message→Chat, ToolCall→Message, User.last_viewed_chat_id; type STI se conserva como dato, sin callbacks de proveedor |
| Insight, DataEnrichment, CategorizationComparison | Conservar por ahora; decidir consumidores al retirar IA/Bills | JSON con UUID, enrichment polimórfico y resultados locales vs remotos; no descartar por nombre genérico |
| RecurringTransaction, RecurrenceRule, RecurringOccurrence, RecurringAllocation, RecurringPriceChange, RecurringMatchRejection | Conservar hasta fase Bills; lector/conversión definidos antes de borrar clases | Movimientos/transferencias, categorías/merchants, budgets/insights y Agenda son contratos distintos; no doble escritura |
| Budget, BudgetCategory, BudgetShare, Goal, GoalAccount, GoalPledge | Conservar hasta selección funcional | Usuario/sharing, cuentas, transaction.extra, pledges/matching y monedas; detener producción de datos es distinto de borrarlos |
| GoogleDriveConnection, GoogleDriveOauthConfiguration, GoogleDriveExportSchedule, GoogleDriveExportTarget, GoogleDriveExportRun | Conservar, usados por Steve | Cifrado y OAuth por usuario, accesos a cuentas, destino fileId, programación y reintentos |
| FinancekitItem, FinancekitAccountLineage, FinancekitAccount, FinancekitBatch, FinancekitTransaction, FinancekitBalanceObservation, FinancekitConflict | Conservar hasta decisión del cliente Apple | Escritor exclusivo, lineage/provider polimórfico, inbox durable; sync_id excluido y consentimiento/reautorización externos |
| 25 pares de Provider Item/Account de `Family::Backup::PROVIDERS` | Conservar hasta el lote de conectores correspondiente | Credenciales cifradas, payloads, claves externas, AccountProvider/provider polymorphic, holdings; no ejecutar destroy callbacks para archivar |
| Subscriptions, LlmUsage, DebugLogEntry, Invitation, FamilyExport | Ya excluidos con motivos en el contrato actual | Facturación/uso/diagnóstico pertenecen a la instancia, enlaces auth deben regenerarse, exports son salidas; quitar SDK/evals no exige conservar sus funciones para restaurar un backup familiar |

La lista de proveedores es la allowlist explícita en código: Akahu, Binance,
Brex, Coinbase, Coinspot, Coinstats, EnableBanking, Fio, Ibkr, IndexaCapital,
Kraken, Lunchflow, Mercury, Monobank, OnchainWallet, Plaid, Questrade, Redbark,
Simplefin, Snaptrade, Sophtron, TradeRepublic, Trading212, Up y Wise.
No se modifica esa allowlist ni se afirma ausencia de filas en producción.

## Facturación histórica tras fase 4

Stripe y la plataforma SaaS están retirados. `Subscription` y los campos de
facturación de instancia permanecen como historia, sin callbacks comerciales.
Sus exclusiones de backup y la eliminación de `Family.stripe_customer_id` del
snapshot portable no cambian. Restaurar no activa pagos, trials ni webhooks;
los vínculos financieros y originales mantienen su verificación.
Ver [registro de fase 4](pruning-phase-4.md).

## Implementación mínima de historial de conversaciones

`Family::Backup::ConversationRecords::{Chat,Message,ToolCall}` lee las tablas
existentes mediante modelos de persistencia independientes. No hereda de las
clases funcionales Chat/Message/ToolCall, no activa STI y no tiene callbacks de
asistente, broadcasts o jobs. Las asociaciones declaran el nombre contractual
del padre para que el restorer compruebe y remapee referencias.

Los registros mantienen los nombres `Chat`, `Message`, `ToolCall`, atributos,
UUID de origen y tipo histórico. Solo se aceptan tipos que el producto actual
entiende: Message/UserMessage/AssistantMessage y ToolCall/ToolCall::Function.
Los nombres desconocidos se rechazan antes de escribir, no se omiten ni ejecutan.
El código de producto sigue presente y puede leer las conversaciones restauradas.

El restorer usa la clave contractual para detectar duplicados, exclusiones y
referencias; no usa el namespace interno del lector como identidad del archivo.
Persistencia mediante insert/update de bajo nivel conserva el comportamiento
actual sin disparar efectos de producto. La validación/readback de atributos y
de originales, pertenencia familiar y rechazo de referencias inexistentes sigue
vigente.

Esto prepara una dependencia concreta de la retirada IA/MCP. No convierte todos
los modelos de Sure en lectores históricos. Cada módulo siguiente necesita su
adaptación concreta en su propia fase: scopes, relaciones, cifrado, adjuntos,
consumidores y jobs. Copiar automáticamente la reflexión de un modelo ya borrado
no resolvería su contrato.

## Reglas para siguientes retiradas

1. Comprobar presencia del módulo en backup privado/datos, y elegir conservación
   o conversión. Inventario de uso no prueba ausencia de datos.
2. Mantener el nombre del archivo y sus campos o introducir versión/lector
   explícitos. No quitar silenciosamente nombres de `MODEL_NAMES`.
3. Resolver scopes y referencias externas al módulo: SQL, polymorphism, JSON,
   STI, adjuntos/record_type, cifrado, GlobalID y queues.
4. Ensayar backup anterior → restore → nuevo export → restore, con atributos,
   relaciones, datos financieros y bytes verificados. No marcar pérdidas como éxito.
5. Conservar tablas mientras estos lectores las necesiten. La eliminación de
   esquema tiene su propia fase y recuperación ensayada.

La reversión de esta fase es de código: las tablas, filas y archivos no cambian
de formato ni se migran. No se borran ni recodifican tipos históricos.

## Historia del asistente externo tras fase 5

Se conservan Family.assistant_type histórico, Chat/Message/ToolCall, instrucciones,
modelos, contenido, estados y originales locales. La importación no encola
respuestas ni reconstruye índices externos. Los ajustes de instancia y tokens
OAuth/API siguen fuera del backup familiar; no se revocan ni borran por retirar
MCP. Las filas cifradas external_assistant_* permanecen en la instancia sin un
consumidor activo. La prueba de conversaciones recorre export → restore → export
→ restore con una familia externa y un modelo histórico OpenClaw.


## Actualización de fase 7

Los conectores retirados conservan sus 48 clases Item/Account como lectores de
persistencia (cifrado, relaciones y originales), sin transportes, Syncable ni
callbacks remotos. El contrato de snapshot mantiene esos nombres y payloads.
Se mantienen también cálculos locales de historial IBKR y rentabilidad Indexa,
metadatos de movimientos y traducciones consumidas por migraciones históricas.
La recuperación no convierte cuentas enlazadas ni activa sus antiguos conectores.
Los resultados de recuperación anterior → importación → exportación → importación
se registran en [fase 7](pruning-phase-7.md).
