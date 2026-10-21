# API/MCP: inversiones, archivos y procesos (fases 6–7)

Estas operaciones amplían el [contrato MCP](mcp.md). Cada herramienta tiene su
ruta fija `POST /api/v1/actions/<nombre>` y esquema estricto en OpenAPI. Las
escrituras requieren permiso efectivo, scope read_write e `idempotency_key`.
No se añaden proveedores, dependencias de ejecución ni migraciones.

## Inversiones y conciliación

| Operaciones | Contrato |
| --- | --- |
| `list_trades`, `get_trade`, `create_trade`, `update_trade`, `delete_trade`, `unlock_trade` | Permisos por cuenta y motor `Trade::CreateForm`; buy/sell, sweep, reinversión, dividendos, intereses, comisiones, depósitos y retiradas |
| `list_holdings`, `get_holding`, `update_holding_cost_basis`, `unlock_holding_cost_basis` | Posiciones nativas. El coste introducido es total: Relay lo convierte a coste por unidad y conserva el bloqueo manual |
| `remap_holding_security`, `reset_holding_security` | Remapeo local, colisiones, vínculo de origen y materialización según el modelo existente |
| `preview_holding_deletion`, `delete_holding` | Previsualización de los trades que elimina el motor nativo, máximo 100; firma ligada a registros/versiones, actor y diez minutos |
| `list_valuations`, `preview_reconciliation`, `reconcile_account`, `update_valuation`, `delete_valuation` | Valores absolutos mediante `Account::ReconciliationManager`; conserva el matching de compromisos manual_save por delta |
| `update_managed_portfolio_value` | `Investment::ValueUpdate`: objetivo absoluto y ajuste de mercado tras aportaciones/retiradas, separado de la valoración genérica |
| `list_local_prices`, `set_local_price`, `list_exchange_rates`, `set_exchange_rate` | Datos locales guardados, sin solicitudes externas ni FX inventado |

Las cantidades y precios son strings decimales. La creación de trades recibe
cantidad/precio positivos; el tipo determina el signo nativo. Buy consume
efectivo y sell lo aporta; la comisión se suma al importe firmado. Los trades
de ingreso tienen cantidad cero e importe negativo. Los depósitos/retiradas
comprueban permiso de escritura sobre ambas cuentas si hay contrapartida.

La edición de un trade con posiciones recalcula su importe desde cantidad,
precio y comisión; los ingresos conservan su signo. Crear/modificar marca las
protecciones nativas y solicita recálculo. Remapear conserva la semántica del
materializador: posiciones calculadas se reconstruyen desde trades; no se
presenta una suma provisional de holdings como posición definitiva.

Los precios solo se leen para valores vinculados a cuentas accesibles. Las tasas
de cambio son datos de mercado compartidos sin información familiar. **Escribir
precios o FX globales exige super_admin de instancia**, además del scope de
escritura; ser administrador familiar no concede esa autoridad. Se valida moneda,
fecha y precio/tasa positiva. Se actualiza la fila local por fecha/moneda; no se
promete que un recálculo de todas las cuentas haya terminado al guardar el dato.

## Reglas

`list_rules`, `get_rule`, `get_rule_options`, `create_rule`, `update_rule`,
`delete_rule`, `preview_rule_run`, `apply_rule` y `list_rule_runs`.

La configuración usa condiciones y acciones tipadas del registro nativo, con
operadores y referencias validados. Admite condiciones compuestas and/or de
un nivel. Omitir condiciones/acciones al editar las conserva; proporcionarlas
reemplaza ese conjunto. `get_rule_options` devuelve los valores admitidos.

La previsualización enumera los movimientos coincidentes y las acciones, con
límite de 100 movimientos. La ejecución comprueba la firma, bloquea los registros
y usa exactamente esa selección con los ejecutores nativos; registra `RuleRun`
y conserva el estado de los trabajos asíncronos. Por defecto respeta bloqueos de
atributos; ignorarlos requiere solicitarlo explícitamente. No se ejecutan cadenas
de texto como código. Las reglas activas mantienen su comportamiento automático
en los procesos de sincronización existentes.

Reglas, importaciones, documentos familiares y backups requieren administrador
familiar con visibilidad completa; las credenciales de escritura requieren además
permiso financiero en todas las cuentas. Esto evita exponer o modificar cuentas
privadas mediante un proceso familiar. La administración de instancia no sustituye
los permisos de sus cuentas.

## Canal de transferencia

`get_upload_channel` describe el canal. Los bytes se suben por multipart con los
campos `file`, `sha256` e `idempotency_key`. El límite de staging es **100 MiB**;
cada dominio aplica además su propio límite (por ejemplo, extractos: 25 MiB;
adjuntos: 10 MiB y diez por movimiento). Se comprueba SHA-256 antes de aceptar.

- Credencial API: `POST /api/v1/files`.
- Credencial MCP: `POST /mcp/files`, con activación, cliente, recurso OAuth y
  política Origin de MCP. Un token OAuth para MCP no se acepta en la ruta API.

La respuesta contiene `upload_token`, nombre, tamaño y SHA-256. La referencia
está ligada al usuario/familia y caduca **una hora tras la primera subida**.
Un reintento con la misma clave y bytes devuelve el mismo archivo sin extender
la caducidad; cambiar bytes/nombre con esa clave falla. Un trabajo limpia staging
sin adjuntar a las dos horas y conserva los originales ya vinculados.

Las herramientas reciben esa referencia, nunca una URL externa arbitraria ni
los bytes completos en el contexto por defecto. `get_file_transfer` devuelve
metadatos y las rutas autenticadas `GET /api/v1/files/download` o
`GET /mcp/files/download`, con `kind`, `id` y, para recibos, `attachment_id`.
Cada descarga comprueba de nuevo la autoridad y transmite el original sin
redirigir a un enlace público de almacenamiento. No se emiten URLs portadoras
temporales que sobrevivan a una revocación de acceso.

## Importaciones y sesiones

`list_imports`, `get_import`, `start_import`, `configure_import`,
`apply_import_template`, `select_qif_categories`, `list_import_rows`,
`update_import_row`, `list_import_mappings`, `update_import_mapping`,
`preview_import`, `publish_import`, `cancel_import`, `preview_revert_import`,
`revert_import` y `delete_import`.

Se usan las clases mantenidas de importación: movimientos, trades, cuentas,
Mint/Actual/YNAB, categorías, reglas, comercios, QIF y lector Relay/Sure.
El original subido se conserva como adjunto, incluso si la interpretación
normaliza codificación o extrae NDJSON de un ZIP. No se reactiva extracción PDF
con IA: los originales PDF pertenecen al Vault y los historiales existentes
conservan su lector y sus permisos.

Configurar regenera filas y mappings; corregir filas admite datos aún inválidos
para repararlos, como la web, y devuelve sus errores. El mapeo usa clases fijas
del modelo, sin constantize de valores del cliente. Las plantillas deben proceder
de una importación completada del mismo tipo. QIF admite formato de fecha y
selección explícita de categorías/tags, incluidos los splits nativos.

Publicar exige una previsualización firmada de contenido, filas, mappings y estado
del destino, válida diez minutos. Se reutilizan validaciones, límites, jobs,
transacciones, protección y deduplicación nativos. Repetir una ejecución idéntica
no vuelve a encolar ni duplica datos; cambiar el payload con su clave falla.
Revertir necesita otra previsualización del impacto y un estado revertible.
No se elimina el historial de una importación que tenga datos comprometidos.

Los trabajos delegados guardan únicamente identificadores de actor/credencial,
sin secretos. Antes de importar, revertir o generar un backup, vuelven a comprobar
actividad del usuario, familia, scopes, permisos y revocación/caducidad de la clave
o token OAuth. La audiencia y cliente MCP se revisan de nuevo para sus tokens.
Perder autoridad impide ejecutar el trabajo y registra diagnóstico; datos ya
comprometidos y bloques completados se conservan para evitar duplicarlos al reintentar.

`create_import_session`, `get_import_session`, `upload_import_chunk`,
`preview_import_session` y `publish_import_session` reutilizan las sesiones
NDJSON existentes. Cada bloque se transfiere por el mismo canal; secuencia,
identificador y SHA-256 detectan colisiones. El número esperado se limita a 100;
un snapshot completo sigue siendo **un único bloque**, según el lector nativo.
La recuperación de trabajos interrumpidos conserva los bloques ya comprometidos.

Cancelar un import pendiente/sin publicar elimina esa preparación. Para uno
en ejecución, solo se permite el escape nativo de trabajo presuntamente perdido;
no se afirma que se pueda interrumpir a voluntad un worker vivo.

## Originales, extractos y adjuntos

`list_statements`, `get_statement`, `upload_statement`, `update_statement`,
`link_statement`, `unlink_statement`, `reject_statement` y `delete_statement`
conservan detección de duplicados, metadatos, original y permisos del Vault.
Ser manager permite gestionar extractos sin cuenta; los vinculados requieren
el permiso de su cuenta. Un duplicado privado no revela su metadata al cliente.
Las sugerencias de cuentas privadas no se incluyen en la respuesta.

`list_documents`, `get_document`, `upload_document` y `delete_document` gestionan
originales familiares sin procesadores externos. `list_attachments`,
`attach_transaction_file` y `delete_transaction_attachment` usan la validación
de adjuntos nativa: anotar permite subir; borrar requiere permiso financiero.
Los originales se descargan por el canal autenticado, con checksum y tamaño.
Los documentos históricos cuyo original no fue retenido lo indican explícitamente.

## Backups y restauración

`list_backups`, `get_backup`, `create_family_backup`, `cancel_backup`,
`delete_backup`, `validate_backup` y `restore_backup` completan el ciclo familiar.
La generación sigue siendo asíncrona. Solo se descarga un export completado;
solo se cancela mediante el escape nativo de trabajo presuntamente perdido.

Subir un backup crea una preparación `RelayImport`. `validate_backup` usa el
lector existente, comprueba manifiesto/checksums/referencias y devuelve conteos,
errores y omisiones. La respuesta diferencia integridad del archivo de disponibilidad
del destino. `restore_backup` exige destino sin datos financieros, autoridad familiar
y la previsualización firmada, ligada a ese archivo y estado del destino. No se
acepta un booleano `confirm` como sustituto de ella. Esta política delega al cliente
autorizado la ejecución del plan concreto; cambios posteriores obligan a previsualizar
otra vez. El lector vuelve a comprobar el destino al ejecutar el trabajo y verifica
atributos, relaciones y originales antes de confirmar la restauración.

Los backups familiares no administran el servidor, el actualizador ni TrueNAS.
El rollback de una preparación NDJSON limpia los bytes que se hubieran cargado
antes de confirmar su transacción; se conserva la atomicidad del resultado
idempotente. [Guía completa de backups](../llm-guides/backups.md).
