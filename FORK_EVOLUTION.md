# Dirección del fork y política de integración selectiva

Fecha de adopción: **2 de octubre de 2026**.

Este fork de Sure es, desde esta fecha, un producto independiente con prioridades,
decisiones funcionales y ritmo de evolución propios. Upstream sigue siendo una
fuente de soluciones y correcciones que podemos aprovechar de forma selectiva.
Mantener paridad con su rama `main` deja de ser un objetivo.

Esta guía define cómo decidir qué incorporamos y cómo hacerlo. El inventario
[FORK_CUSTOMIZATIONS.md](FORK_CUSTOMIZATIONS.md) describe las funcionalidades que
debemos preservar y sus puntos sensibles. Las convenciones técnicas, permisos y
comprobaciones siguen en [AGENTS.md](AGENTS.md) y los
[documentos de desarrollo](docs/llm-guides/README.md).

## 1. Identidad y prioridades del producto

El fork está orientado a finanzas personales curadas: datos comprensibles y
controlados por el usuario, una visión fiel de su situación financiera y
previsiones que ayuden a anticipar compromisos y disponibilidad de dinero.

Las prioridades son:

- Exactitud de saldos, movimientos, transferencias, patrimonio e informes.
- Previsiones, Agenda y comprensión de compromisos y liquidez futura.
- Control sobre qué cuentas y movimientos participan en cada cálculo.
- Claridad de las comparaciones, períodos familiares y filtros.
- Comodidad de uso: menos fricción, navegación coherente, vistas compactas y
  preferencias que se conservan.
- Seguridad, aislamiento por familia, protección de datos y exportaciones fiables.
- Fiabilidad y mantenimiento sostenible de las funciones que realmente usamos.

La sincronización bancaria, IA e inversiones pueden apoyar estas prioridades.
Su expansión no constituye por sí misma una razón para incorporar cambios.
El roboadvisor y las capacidades de inversión ya utilizadas forman parte del
producto y deben conservar su exactitud y utilidad.

Agenda sigue siendo nuestro producto de pagos programados. Bills, Plan,
presupuestos y objetivos conservan la frontera definida en el inventario. La IA
mantiene su puerta global. Cambiar estas decisiones requiere una propuesta
funcional y una aprobación expresa del usuario.

## 2. Criterios para seleccionar una mejora

Una incorporación debe cumplir **todos** estos criterios:

1. **Beneficio claro.** Resolver un problema concreto del fork o aportar una mejora
   útil para sus usuarios. Explicar el comportamiento anterior y el propuesto.
2. **Encaje con el producto.** Apoyar las prioridades anteriores y respetar nuestras
   decisiones funcionales, personalizaciones y límites de acceso.
3. **Ventaja frente a lo que ya tenemos.** Comprobar que la solución no existe ya ni
   equivale a una adaptación propia. Si sustituye código del fork, justificar por
   comportamiento qué mejora y qué se conserva.
4. **Coste proporcionado.** Valorar implementación, dependencias, regresiones,
   mantenimiento futuro y complejidad añadida, además del beneficio inmediato.
5. **Alcance delimitable.** Poder identificar la funcionalidad y sus dependencias
   necesarias sin arrastrar una expansión ajena al objetivo aprobado.
6. **Validación posible.** Definir cómo demostrar que funciona y que preserva las
   funciones del fork. Distinguir comprobaciones ejecutadas de las pendientes.

Tienen prioridad las correcciones de seguridad, errores en cálculos y datos,
fallos de persistencia, fiabilidad, rendimiento con impacto concreto y mejoras
de comodidad. Las actualizaciones de dependencias también se valoran por su
necesidad y compatibilidad, no por seguir automáticamente la versión upstream.

Se descartan o aplazan las novedades sin uso identificado, duplicaciones de
Agenda u otros sistemas propios, cambios meramente cosméticos que empeoran
nuestra experiencia y refactorizaciones cuyo coste supera la ventaja demostrable.
Que una funcionalidad pueda quedar oculta no elimina su coste de mantenimiento.

## 3. Proceso obligatorio en dos fases

Toda incorporación de upstream se divide en dos fases. **La fase de integración
solo comienza después de que el usuario decida qué funcionalidades entran y
cuáles quedan fuera.** Solicitar una revisión de upstream autoriza el análisis;
no autoriza aplicar los cambios encontrados.

Esta separación también se aplica a correcciones técnicas o de seguridad. Su
urgencia puede justificar una presentación inmediata y breve, pero no elimina
la decisión del usuario.

### Fase 1: análisis y presentación

El análisis puede leer y comparar código, historial, pruebas, documentación e
issues, y actualizar referencias remotas cuando corresponda. Puede producir un
informe. No aplica parches ni cherry-picks, no modifica código de producto y no
ejecuta migraciones o despliegues.

Pasos del análisis:

1. Leer esta guía y el inventario de personalizaciones. Comprobar el estado real
   del fork y la referencia de la última revisión.
2. Fijar el intervalo upstream examinado con SHA inicial y final. Revisar los
   diffs y las pruebas; los títulos de commits son solo una pista.
3. Agrupar los commits por funcionalidades completas, correcciones coherentes o
   mejoras de mantenimiento. Una propuesta puede requerir uno o varios commits.
4. Identificar prerrequisitos, correcciones posteriores y contactos con nuestras
   funciones. Comprobar si ya incorporamos una solución equivalente.
5. Evaluar cada propuesta con los criterios de selección y recomendar incorporar,
   aplazar o descartar. Explicitar las incertidumbres.

**La presentación se organiza por funcionalidades, nunca como una lista de
commits útiles uno por uno.** El detalle de commits y sus dependencias queda como
trazabilidad técnica; no es la unidad sobre la que se pide decidir al usuario.

Para cada propuesta se presenta:

- Un nombre comprensible y estable para poder referirse a ella al decidir.
- Qué problema resuelve y qué cambiaría en el uso de nuestra aplicación.
- Por qué encaja y qué valor añade frente al comportamiento actual.
- Su alcance, dependencias relevantes, funciones propias afectadas y riesgos.
- Una estimación cualitativa del esfuerzo y cómo se comprobaría.
- La recomendación y una pregunta explícita sobre si se quiere implementar.

Ejemplo de presentación:

> **Proyección de amortización de préstamos.** Permitiría estimar cuándo se termina
> de pagar una deuda y comparar saldo real con calendario previsto. Encaja con
> nuestras previsiones. Requiere motor de cálculo y adaptación del gráfico; hay
> que comprobar tipos variables, divisas y convivencia con Agenda. Esfuerzo medio.
> Recomiendo incorporarla. ¿Quieres implementar esta funcionalidad?

Al final se resumen las propuestas y se pide decidir qué entra, qué se aplaza y
qué se descarta. Los descartes se pueden resumir por áreas. El silencio, una
pregunta sobre una propuesta o el simple interés no constituyen aprobación.

Si varias propuestas necesitan una base común, se explica antes de decidir.
No se presenta como independiente algo que obliga a incorporar otra funcionalidad.
Se puede proponer adaptar la solución para evitar esa dependencia.

### Fase 2: incorporación e integración

La selección expresa del usuario inicia esta fase y autoriza preparar los cambios
necesarios dentro de ese alcance. No hay que pedir permiso de nuevo para cada
archivo o prerrequisito técnico ya explicado y aprobado.

Pasos de la integración:

1. Registrar las funcionalidades aprobadas y sus límites. Comprobar si el fork o
   upstream cambiaron desde el análisis y si eso afecta a la propuesta.
2. Trabajar directamente en `main`, respetando los cambios existentes del usuario.
   No crear ramas ni PR salvo petición expresa; hacer commit y push a `origin/main`
   solo cuando el usuario confirme los cambios preparados y validados.
   Mantener separadas las unidades funcionales cuando puedan integrarse solas.
3. Elegir por propuesta entre cherry-pick, adaptación parcial o implementación
   equivalente. Un cherry-pick es una herramienta; no obliga a aceptar todo el
   contenido de un commit upstream.
4. Incorporar únicamente los cambios aprobados y sus dependencias necesarias.
   Conservar los contratos y funciones recogidos en el inventario.
5. Añadir o adaptar pruebas de comportamiento y ejecutar las comprobaciones
   aplicables en un entorno compatible, según las guías del repositorio.
6. Revisar el diff final, documentar origen, adaptaciones y validación, y entregar
   un resultado concreto que se pueda revisar y revertir.

Si aparece una dependencia no prevista que amplía el producto, exige una nueva
integración externa, cambia una decisión funcional o altera materialmente el
riesgo o el coste, presentar esa ampliación al usuario antes de incorporarla.
Las correcciones técnicas dentro del alcance aprobado se resuelven durante el
trabajo y se explican en la entrega.

Aprobar una funcionalidad no autoriza automáticamente un despliegue, una migración
en una instalación ni operaciones destructivas sobre datos. Commits, publicación
y PRs se realizan según la petición del usuario y las reglas del repositorio.

## 4. Historial, trazabilidad y posibilidad de revertir

No se harán merges completos de `upstream/main` como procedimiento habitual.
Una integración completa sería una excepción que requiere su propio análisis y
aprobación expresa. Tampoco se marcarán como integrados commits descartados solo
para silenciar futuros conflictos.

Conservar por cada revisión un registro duradero con:

| Campo | Contenido |
| --- | --- |
| Referencias | Fecha, HEAD del fork y rango upstream revisado |
| Propuestas | Funcionalidades agrupadas y commits fuente relacionados |
| Decisiones | Aprobada, aplazada, descartada o ya disponible; motivo y decisión del usuario |
| Resultado | Implementada, parcialmente preparada, pendiente de validación o bloqueada |
| Trazabilidad | Commits locales, SHA upstream y adaptaciones realizadas |
| Validación | Comprobaciones ejecutadas, resultado y pendientes |
| Reversión | Unidad que se puede revertir y efectos sobre datos o configuración |

La última referencia **revisada** y los commits **incorporados** son conceptos
distintos. Avanzar el punto de revisión no significa haber integrado todo el
intervalo. Las propuestas aplazadas siguen visibles para una revisión posterior.

Los commits locales deben ser pequeños y cohesivos por funcionalidad. Se puede
reunir una secuencia upstream en un commit propio cuando facilite revisión y
reversión, conservando los SHA fuente en su descripción o en el registro. Cuando
sea adecuado un cherry-pick directo, conservar su referencia de origen.

Las integraciones históricas por squash hacen que el merge-base de Git sea una
referencia insuficiente para medir qué contenido ya existe. Comprobar el registro
y el código antes de interpretar un triple-dot como novedades del producto.

Revertir un commit de código no revierte automáticamente migraciones ni datos.
Toda incorporación con cambios persistentes debe explicar ese límite. No borrar
migraciones históricas ni eliminar tablas por haber decidido dejar de usar un
subsistema.

## 5. Conservación y validación del fork

Usar [FORK_CUSTOMIZATIONS.md](FORK_CUSTOMIZATIONS.md) como mapa de preservación y
actualizarlo si una incorporación aprobada cambia la implementación o contratos
de una funcionalidad propia. Verificar las regresiones relevantes para el área:

- Agenda: generación, confirmación, rechazo, transferencias y enlaces a movimientos.
- Cuentas incluidas, de seguimiento y fuera de finanzas; archivo independiente.
- Informes, previsiones, saldos, transferencias y cálculos en varias divisas.
- Meses familiares, períodos independientes, filtros y preferencias de interfaz.
- Logos, exportaciones, Google Drive, permisos y aislamiento por familia.
- Frontera de Bills/Plan/Goals y puerta global de IA cuando haya puntos de contacto.

Una revisión estática no demuestra por sí sola que una integración funciona.
Mientras persista la limitación del bundle descrita en el inventario, dejar las
pruebas escritas y pendientes de ejecución en CI o en un entorno compatible.
No declarar validación completa ni publicar una PR sin cumplir las comprobaciones
requeridas. Esta guía no inicia trabajos de configuración del entorno.

La entrega se resume por funcionalidades aprobadas: comportamiento resultante,
adaptaciones propias, pruebas realizadas, limitaciones y forma de revertir.

## 6. Punto de partida y revisiones futuras

Referencias verificadas al adoptar esta política:

| Referencia | SHA |
| --- | --- |
| HEAD del fork tras la última integración squash | `3ff4986dc0c0912fa256aab72c394cc7261a41c0` |
| Upstream incluido como referencia de esa integración | `ec4282e0eba808e443b6c15a11d567c1c4c4f3fb` |

Estas referencias describen el contenido de partida; no certifican que las
pruebas funcionales pendientes hayan pasado. Las revisiones siguientes examinan
la evolución posterior a la referencia upstream indicada, consultando también
las propuestas aplazadas y comprobando lo que realmente existe en el fork.

Una revisión periódica puede generar el análisis y la presentación de la fase 1.
Su periodicidad se acuerda con el usuario; esta guía no crea una automatización.
Toda incorporación sigue esperando la selección expresa de funcionalidades.

La dirección del producto se decide aquí. Las novedades upstream se incorporan
cuando aportan una mejora clara para nuestro fork y el usuario elige adoptarlas.
