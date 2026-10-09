# Etapas de persistencia financiera

Decisiones 1A–10A aprobadas el 7 de octubre de 2026. No se han ejecutado
migraciones ni consultado datos de la instalación real.

## Inventario previo

Crear una copia aislada restaurable y verificar su destino antes de cualquier
despliegue. No conectar este procedimiento a producción. La tarea de inventario
es de solo lectura (transacción PostgreSQL READ ONLY) y entrega conteos agregados:

```sh
RELAY_FINANCIAL_INVENTORY_ISOLATED=1 FAMILY_ID=<id-en-la-copia> bin/rails financial_domain:inventory
```

Conservar el resultado y un backup completo probado. Revisar duplicados de
Entry, huérfanos, extremos usados en roles distintos, flags pending contradictorios
y fronteras inconsistentes antes de avanzar. No borrar ni elegir ganadores.
Las pruebas sintéticas no sustituyen este inventario histórico.

## Etapa 1: atributos aditivos y lectores compatibles

`20261007120000_add_independent_financial_attributes.rb` prepara columnas nullable:

| Entidad | Campo | Compatibilidad para NULL |
| --- | --- | --- |
| Entry | import_protected | Conserva la protección implícita de excluded histórico |
| Investment | tax_treatment | Fiscalidad histórica derivada del subtipo |
| Investment | tracking_mode | Subtipo gestionado y managed_portfolio conservados |
| Account | financial_treatment | included/tracking/outside_finances desde flags existentes |
| Transaction | posting_status | Todos los namespaces pending históricos |

Las escrituras nuevas normalizan pending/posted sin borrar `extra`; los cambios
de subtipo/seguimiento no convierten ni borran trades, holdings o rendimiento.
Una edición de un Entry antiguo conserva su protección aunque deje de excluirse
de analítica. El desbloqueo explícito limpia import_protected, los locks y las
protecciones manuales; la estructura de splits continúa protegida.

Los backups completos v2 conservan los nuevos atributos. Los v1 continúan
admitidos y traducen excluded a protección independiente; NDJSON antiguo hace
la misma traducción. No se cambia la naturaleza de las filas restauradas.

## Etapa 2: normalización histórica, después del inventario

Preparar lotes separados y reversibles con sus conteos antes/después:

1. pending/posted: cualquier flag true significa pending; sin true significa
   posted. Resolver contradictorios con evidencia del banco antes de cerrar
   el inventario. Conservar íntegro extra como procedencia.
2. financial_treatment: cashflow_boundary true → outside_finances;
   exclude_from_reports true sin frontera → tracking; ambos false → included.
3. import_protected: excluded histórico → true; resto → false. Mantener también
   user_modified, import_locked y locks por campo. No desbloquear en bloque.
4. one_time → kind standard + exceptional_once, salvo anomalías que requieran
   revisión. Conservar siempre traductores de backups v1/NDJSON.

El código realiza normalización compatible al editar. No se incluye un backfill
automático sobre toda la instalación: requiere el inventario y su revisión.

## Etapa 3: integridad, después de resolver anomalías

Preparar por separado un índice único `(entryable_type, entryable_id)` y comprobación
de extremos diferentes. La exclusión de un mismo Transaction entre ambos roles
de Transfer requiere una tabla canónica de extremos o un trigger con bloqueo;
dos índices únicos independientes no garantizan esa condición concurrente.
Las referencias polimórficas Entry requieren un contrato de eliminación y
validación adicional, no una FK convencional a tres tablas.

No añadir esas restricciones mientras el inventario presente anomalías. Validar
concurrencia, rollback, recuperación y política de borrado en la copia antes de
escribir la migración final. La preparación aditiva no declara resuelta esta etapa.

## Despliegue y reversión

La aplicación actual requiere las columnas aditivas al desplegar. Aplicar la
migración solo con autorización explícita sobre el destino verificado. Primero
probar backup v2 y restauración v1/v2 en la copia. No hacer rollback del esquema
tras escribir atributos independientes sin exportarlos: suprimir columnas pierde
esa información. Se puede revertir código conservando columnas y backup.
