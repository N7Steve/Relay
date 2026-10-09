# Formulario de decisiones: simplificación financiera

Creado: 6 de octubre de 2026. Respuestas recibidas: 7 de octubre de 2026. Estado: opciones 1A–10A aprobadas; implementación por entregas según 10A.

Marca una opción por apartado, o responde en el chat con sus códigos:
`1A, 2A, 3B, ...`. Puedes añadir condiciones en las notas. Las recomendaciones
se han seleccionado expresamente por el usuario en los diez apartados. No hay condiciones adicionales.

Estas respuestas delimitan la siguiente implementación. No ejecutan migraciones,
modifican la instalación real ni autorizan commit/push.

## Seguimiento de las respuestas aprobadas

| Decisión | Estado de preparación |
| --- | --- |
| 1A | Desacoplamiento de excepcionales preparado; conserva exclusión presupuestaria y lectores históricos |
| 2A | Exclusión de aportaciones conservada en la política común de presupuesto |
| 3A | Catálogo corto en altas; subtipo histórico conservado al editar; fiscalidad/seguimiento independientes sin borrar trades |
| 4A | Explicación compartida con misma moneda/cuenta y enlaces confirmados prioritarios de ambos extremos; sin doble reserva |
| 5A | Mejor alternativa única para ambos extremos; empates disponibles para revisión manual |
| 6A | FX comprobado en ingresos/gastos, búsqueda, inversiones, coste medio y series patrimoniales; CSV conserva moneda original |
| 7A | import_protected independiente, protección histórica y desbloqueo explícito; locks preservados |
| 8A | Comisiones por moneda/extremo; total_fee devuelve nil para monedas mezcladas |
| 9A | Migración aditiva, inventario de solo lectura y plan por etapas preparados; falta copia aislada para inventario real e integridad final |
| 10A | Orden aplicado: excepcionales/presupuesto y FX primero |

Actualizado el 7 de octubre de 2026. En Docker pasan 5.460 pruebas Rails
(23.856 aserciones, 38 omisiones), sin fallos ni errores, y las 436 pruebas
focalizadas (2.549 aserciones). RuboCop, ERB lint, Biome y Brakeman pasan.
Las 31 pruebas de navegador pasan (148 aserciones), sin fallos, errores ni
omisiones. No se ha ejecutado ninguna migración sobre una instalación ni
publicado cambios.

## Resultado preparado

- Selección común de movimientos para saldos e histórico de ambas previsiones.
- Agenda unificada con vínculos confirmados prioritarios y misma moneda en heurísticas.
- Relaciones explícitas `paired_transfer` y `fee_transfer`, conservando `transfer_id`
  en almacenamiento/backups y la lectura antigua `transfer` como compatibilidad.
- Reclasificación de ambos extremos compartida por matching y cambios de frontera.
- Factoría explícita de Enable Banking, sin descubrimiento ni autorregistro.
- Excepcionales separados de `kind`, con exclusión presupuestaria conservada y
  edición compatible de históricos `one_time`.
- Catálogo corto de inversiones, fiscalidad y seguimiento independientes;
  cambiar subtipo o modo no destruye operaciones ni posiciones.
- Autoemparejamiento conservador ante empates y comisiones por moneda/extremo.
- Conversión estricta sin paridad inventada en agregados; CSV con moneda original.
- Protección de importación independiente de exclusión analítica, con desbloqueo
  explícito y traducción de backups anteriores.
- Columnas aditivas para protección, inversión, tratamiento y pending/posted;
  inventario agregado de solo lectura y plan de normalización/integridad.
- Pruebas añadidas de clasificación, comisiones, rollback y recuperación.

Los cambios siguen locales en `main`. No hay inventario ni mediciones sobre la
instalación real.
El [plan de persistencia](../migration/financial-domain-stages.md) separa preparación,
inventario, backfill e integridad. El despliegue requiere las columnas aditivas;
aplicar la migración al destino necesita autorización explícita.

Consulta la [matriz de efectos actuales](../llm-guides/financial-effects.md) y la
[investigación](financial-domain-simplification.md) para el contexto completo.

## 1. Operaciones excepcionales y presupuesto

Actualmente `one_time` queda fuera del presupuesto y del residual ordinario de
previsión, aunque conserva su efecto sobre el saldo. Al separar naturaleza y
previsión, hay que escoger quién conserva la exclusión presupuestaria.

- [x] **1A — Conservar el resultado actual (recomendado para la transición).**
  Una compra excepcional de 1.000 € reduce saldo y queda fuera de presupuesto y
  previsión recurrente; su exclusión se expresa sin reutilizar `kind`.
- [ ] **1B — Incluir excepcionales en el presupuesto.** La compra cuenta como
  gasto real del mes, pero no se repite en la previsión. Cambian cifras históricas
  de informes/presupuestos cuando se recalculan.
- [ ] **1C — Aplazar el desacoplamiento.** Conservar temporalmente ambos campos
  y su sincronización hasta definir el contrato.

Respuesta: A. Condiciones: ninguna adicional.

## 2. Aportaciones a inversión

Actualmente `investment_contribution` está excluido de los presupuestos. No se
debe cambiar esa regla siguiendo comentarios antiguos que decían lo contrario.

- [x] **2A — Conservar la exclusión presupuestaria (recomendado).** Mover 300 €
  desde efectivo a una inversión incluida no se presenta como consumo.
- [ ] **2B — Contar la aportación como gasto presupuestario.** Permite tratar el
  ahorro invertido como una partida de salida; el patrimonio sigue evitando
  duplicar transferencias internas.
- [ ] **2C — Aplazar esta política.** Mantener la regla actual y decidirla en una
  entrega específica de presupuestos.

Respuesta: A. Condiciones: ninguna adicional.

## 3. Catálogo y seguimiento de inversiones

El subtipo comercial, la fiscalidad y el seguimiento de posiciones representan
conceptos distintos. Hay cuentas históricas con subtipos regionales y carteras
gestionadas que deben conservar su información.

- [x] **3A — Catálogo corto para altas nuevas (recomendado).** Ofrecer bróker,
  cartera gestionada/roboadvisor, pensión y otra inversión. Conservar subtipos
  existentes para lectura/edición compatible, sin convertir datos automáticamente.
  Fiscalidad y seguimiento se diseñan como atributos independientes.
- [ ] **3B — Mantener el catálogo actual.** Separar fiscalidad/seguimiento cuando
  se implementen sus contratos, sin reducir las opciones comerciales.
- [ ] **3C — Definir un catálogo propio.** Escribir abajo los tipos deseados.

Respuesta: A. Catálogo/condiciones: ______.

Cambiar seguimiento nunca debe borrar trades, posiciones autoritativas o historia
de rendimiento silenciosamente. Cualquier conversión se prepara por separado.

## 4. Explicación de históricos por Agenda

La previsión de cuenta permite coincidencias de importes nominales de monedas
distintas; la patrimonial exige igualdad de moneda. Los vínculos explícitos se
tratan también en recorridos distintos, especialmente para movimientos irregulares.

- [x] **4A — Unificar con moneda igual y vínculo explícito prioritario
  (recomendado).** Un enlace válido de Agenda explica la evidencia sin exigir
  título/importe heurísticos; la heurística solo opera con misma cuenta y moneda.
  Se comprueban ambos extremos y se evita repetir un movimiento en reserva/residual.
- [ ] **4B — Conservar las diferencias actuales.** Mantener las políticas ya
  caracterizadas mientras se centralizan más mecanismos internos.
- [ ] **4C — Usar únicamente vínculos explícitos.** Las coincidencias sin enlazar
  dejan de explicar el historial; cambia la previsión de históricos no vinculados.

Respuesta: A. Condiciones: ninguna adicional.

## 5. Autoemparejamiento ambiguo de transferencias

Actualmente se consumen candidatos de forma voraz por prioridad y distancia de
fechas. Si dos entradas resultan igual de plausibles para una salida:

- [x] **5A — Dejar el caso ambiguo para revisión (recomendado).** No crear una
  pareja automáticamente cuando no haya una alternativa claramente preferible.
  Preparar el criterio exacto y la presentación de candidatos en una entrega propia.
- [ ] **5B — Mantener la elección automática con desempate determinista.**
  Conservar el comportamiento automático y usar un orden estable ante empates.
- [ ] **5C — Mantener exactamente el algoritmo actual.** Posponer cambios de
  prioridad, desempate y tratamiento de ambigüedad.

Respuesta: A. Condiciones: ninguna adicional.

## 6. Informes sin tipo de cambio disponible

Algunas consultas agregadas conservan una alternativa 1:1 si falta la tasa,
mientras el recálculo local falla explícitamente. Para 100 USD en un informe EUR
sin tasa, no se debe presentar 100 EUR como una conversión comprobada.

- [x] **6A — No mostrar el total convertido y explicar qué tasa falta
  (recomendado).** Conservar importes originales y señalar moneda/fecha necesarias.
- [ ] **6B — Mostrar un total parcial explícito.** Identificar claramente importes
  omitidos y monedas sin convertir, evitando que parezca un total completo.
- [ ] **6C — Aplazar el cambio de política.** Mantener temporalmente cada
  superficie actual y priorizar caracterización de FX antes de modificarla.

Respuesta: A. Superficies prioritarias (dashboard, presupuesto, CSV, API): ______.

No se añadirán proveedores externos de FX. Una tasa 1:1 solo es exacta cuando
la moneda es la misma; tasas manuales/guardadas conservan procedencia y fecha.

## 7. Exclusión analítica y protección de importación

Actualmente `excluded` afecta a informes/previsión y también protege el registro
frente al proveedor. Pendientes y padres divididos tienen reglas propias.

- [x] **7A — Separar conceptos conservando la protección existente (recomendado).**
  Excluir de analítica no elimina el efecto sobre saldo. Los registros actualmente
  protegidos siguen protegidos tras la transición; desbloquear requiere una acción
  explícita. Mantener locks por campo y prioridades de importación.
- [ ] **7B — Mantener el campo y su efecto doble.** Documentar y concentrar
  lectores sin cambiar la protección ni añadir persistencia independiente.
- [ ] **7C — Diseñar protección solo por campo.** Preparar antes una matriz de
  campos del banco/usuario y pruebas de pending→posted. No se implementa directamente
  sin ese contrato ni se eliminan protecciones históricas por defecto.

Respuesta: A. Condiciones: ninguna adicional.

## 8. Comisiones en transferencias multimoneda

Actualmente `total_fee` suma cantidades numéricas de las dos cuentas. Una comisión
de 2 EUR y otra de 3 USD no tienen un total económico de «5» sin moneda/conversión.

- [x] **8A — Mostrar comisiones por moneda/extremo (recomendado).** Conservar
  cantidades originales y evitar un total combinado cuando las monedas difieran.
- [ ] **8B — Convertir ambas para un total común.** Elegir moneda y fecha de
  conversión explícitas; si falta FX, aplicar la política seleccionada en el punto 6.
- [ ] **8C — Aplazar el contrato multimoneda.** Mantener el método actual y
  revisar todos sus consumidores antes de cambiar su retorno.

Respuesta: A. Si eliges 8B, moneda y fecha de conversión: ______.

## 9. Cambios de persistencia

Incluyen normalizar pending/posted conservando metadata original, hacer canónico
`financial_treatment` y reforzar integridad de extremos/Entry. Reducir la lista de
proveedores pending sin convertir datos históricos no es una migración válida.

- [x] **9A — Preparar cambios por etapas tras inventario aislado (recomendado).**
  Inventariar primero; preparar mapeo, lectores de backups antiguos y pruebas.
  Entregas separadas para pending, tratamiento de cuenta e índices, con revisión
  de anomalías antes de aplicar restricciones.
- [ ] **9B — Mantener por ahora el esquema actual.** Continuar refactorizaciones
  de lectores y operaciones sin nuevas columnas/índices.
- [ ] **9C — Priorizar un cambio concreto de persistencia.** Indicar cuál;
  conserva los requisitos de inventario, backups y reversión.

Respuesta: A. Prioridad/ubicación de una copia aislada para inventario: ______.

Seleccionar 9A/9C autoriza preparar el diseño y las migraciones de ese alcance,
no ejecutarlas en una base real. Duplicados/huérfanos no se eliminan automáticamente.

## 10. Orden de la siguiente entrega

- [x] **10A — Excepcionales/presupuesto y FX primero (recomendado).** Abordar
  las decisiones 1, 2 y 6 en unidades separadas, una vez validada esta refactorización.
- [ ] **10B — Agenda y transferencias primero.** Priorizar 4, 5 y 8; completar
  gradualmente enlace/desenlace y actualización atómica de operaciones.
- [ ] **10C — Otro orden.** Indicar catálogo, protección, persistencia u otra
  prioridad usando los números anteriores.

Respuesta: A. Orden/condiciones: ______.

## Límites y trabajo técnico pendiente

En todas las opciones se conservan la familia como aislamiento, propiedad y
permisos, participación financiera personal, entidades Entry/Transaction/Trade/
Valuation y el modelo de dos extremos. Cambiarlos exige un alcance distinto.

Antes de publicar cualquier entrega:

- [x] Ejecutar las pruebas focalizadas y la suite Rails completa en Docker.
- [x] Ejecutar los checks aplicables; comprobar controllers, exports y generador.
- [x] Ejecutar los escenarios de navegador afectados: cuentas, transacciones,
  transferencias y formulario de tipo de cambio.
- [x] Verificar recuperación y remapeo de comisiones en backups actuales/anteriores.
- [ ] Mostrar el diff final y recibir confirmación de commit/push.

Quedan trabajos técnicos sin decisión de producto: retirar gradualmente el alias
`Transaction#transfer`, concentrar más operaciones de enlace/desenlace y edición,
y revisar invalidación de cachés. Las restricciones de concurrencia y el ahorro
de rendimiento requieren evidencia; no se declaran resueltos por este diff.

## Hoja de respuesta

```text
1=A
2=A
3=A
4=A
5=A
6=A
7=A
8=A
9=A
10=a
Notas=Sin notas adicionales
```
