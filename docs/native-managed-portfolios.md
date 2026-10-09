# Carteras gestionadas: actualizaciones de valor nativas

Las cuentas con seguimiento gestionado ofrecen tres acciones: aportar dinero,
retirar dinero y actualizar el valor total. Las dos primeras usan transferencias
entre cuentas; la última genera un movimiento nativo `investment_value_adjustment`.
Ningún cálculo depende del nombre de una cuenta, categoría, etiqueta o movimiento.

Al introducir 1.414,71 después de un saldo de 1.000 y una aportación de 300,
se muestra una valoración de +114,71. El movimiento usa la convención contable
habitual de Entry: importe negativo para un incremento del activo. Se excluye
de los ingresos/gastos presupuestables, del pendiente de categorizar y de la
estimación de gastos recurrentes. Sí cuenta como rendimiento de la inversión.

## Registro y correcciones

Cada actualización guarda el total declarado y el saldo de partida en
`transactions.extra.investment_value`. El importe del movimiento es la diferencia,
no una segunda suma del total. Los cierres absolutos prevalecen sobre observaciones
antiguas del mismo día; estas observaciones se conservan.

Los movimientos del día se contabilizan antes del cierre. Reenviar un formulario
para la misma cuenta y fecha corrige ese cierre, sin duplicarlo. Aportaciones
registradas a posteriori recalculan las diferencias y conservan los totales
declarados. El drawer permite corregir un cierre existente; no permite trasladarlo
a una fecha que ya contiene otro cierre. No se admiten fechas futuras ni valores
negativos. Un valor de cero es válido.

Este flujo requiere seguimiento por saldo, sin operaciones ni posiciones
individuales. Los datos históricos de cuentas con posiciones se conservan;
no se convierten operaciones bursátiles en ajustes de valor.

## Migración automática

`20261009120000_normalize_managed_portfolio_movements` se ejecuta mediante el
proceso habitual de migraciones del despliegue. No requiere importar el CSV.

Selecciona todas las familias y las cuentas Investment con seguimiento `managed`.
Para datos anteriores sin seguimiento explícito, reconoce los subtipos
`roboadvisor` y `managed_fund` y el indicador de cartera gestionada. Un seguimiento
explícito de posiciones prevalece sobre esos valores heredados.

Las transacciones ordinarias de rendimiento se convierten en ajustes nativos;
las que ya indican Contribution/Withdrawal se clasifican como aportaciones o
retiradas según su signo. Se conservan los identificadores, importes, fechas,
nombres, notas, categorías, etiquetas, exclusiones, bloqueos y datos de origen.
Las transferencias vinculadas, sus comisiones, los movimientos ya clasificados,
las operaciones bursátiles y los padres de desgloses se mantienen intactos.

Los ajustes históricos conservan su diferencia original: no se inventan cierres
absolutos que el historial no contiene. La normalización es idempotente y anota
la clasificación anterior en `extra.managed_portfolio_migration`. Su reversión
restaura esa clasificación; conserva los nuevos cierres absolutos como nativos.

Las copias completas conservan todos los metadatos. El formato NDJSON portable
también incluye los cierres absolutos para permitir restaurarlos y recalcularlos.
