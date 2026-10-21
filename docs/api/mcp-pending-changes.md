# Propuestas MCP y aprobación humana

Las escrituras del MCP de Relay son **propuestas pendientes**. No se ejecuta el
dominio, no se modifica el registro de idempotencia de ejecución y no se lanzan
jobs financieros o externos hasta que la persona aprueba desde **Ajustes →
Cambios pendientes**. No existe una opción de entorno para omitir esta aprobación.
Las lecturas siguen consultando los datos canónicos. La subida de bytes al canal
MCP es staging: no adjunta ni importa esos archivos antes de aprobar la operación.

## Uso desde el asistente

El catálogo conserva los nombres de las operaciones de dominio; las escrituras
anuncian un resultado de propuesta en lugar de un resultado de ejecución. Se añade
la consulta `get_pending_changes`, que muestra estados, recuentos y fallos propios,
sin exponer argumentos o resultados financieros almacenados de otras operaciones.
Hay 244 herramientas de dominio más esta herramienta de seguimiento; una clave
read solo recibe herramientas de lectura. El asistente no puede aprobar o rechazar.

Cada usuario y credencial tiene una propuesta abierta. Las nuevas operaciones se
añaden en orden hasta 100 operaciones y 2 MiB por propuesta. Cada llamada conserva
su `idempotency_key`: repetirla devuelve la misma propuesta, incluso si ya se
aplicó o descartó; cambiar argumentos o credencial con la misma clave se rechaza.
Una propuesta ya aprobada no admite añadidos: las llamadas nuevas abren otra.
Los límites de las operaciones de dominio siguen vigentes al ejecutarlas.

```json
{
  "status": "pending_approval",
  "change_set_id": "uuid-de-la-propuesta",
  "change_id": "uuid-de-la-operacion",
  "approval_path": "/settings/pending_changes/uuid-de-la-propuesta",
  "result_reference": "pending:uuid-de-la-operacion:id"
}
```

Para crear y después editar un movimiento en la misma propuesta, usar como
`transaction_id` el valor `pending:<change_id-de-la-creacion>:transaction_id`.
La referencia se resuelve después de ejecutar aquella operación aprobada.
Admite campos anidados e índices, por ejemplo `pending:<change_id>:children.0.id`.
Solo se permiten referencias a operaciones anteriores de la misma propuesta;
no se interpretan expresiones, métodos ni referencias a propuestas ajenas.
Los esquemas MCP anuncian estas referencias. Los esquemas REST no cambian.

Una lectura que usa una referencia pendiente también se añade como paso de la
propuesta, con scope read_write obligatorio; así puede consultar o previsualizar
un registro que se creará al aprobar. Las herramientas `preview_*` admiten
`defer_until_approval: true` e `idempotency_key` para preparar su resultado solo
al aplicar. Por ejemplo, encolar `preview_bulk_delete_transactions` con esa opción
y pasar `pending:<change_id-de-la-preview>:preview_token` al borrado posterior.
Esto evita preparar hoy un token que habría caducado antes de la revisión.
Las lecturas diferidas no cambian datos financieros por sí mismas, pero cuentan
como pasos y pueden detener una propuesta si su validación falla.

Las propuestas validan estructura, límites, scope de escritura y referencias.
La validación completa de dominio y permisos se hace al aplicar: proponer no
garantiza que el estado actual permita ejecutar la operación. No es una simulación
de una base de datos privada ni permite leer registros todavía no aprobados.

## Revisión y aplicación

La web muestra el origen, fecha, estado y un resumen agrupado por tipo y acción:
gastos, ingresos, transferencias, categorías, etiquetas y otras áreas. Distingue
las cuentas y el origen/destino de una transferencia, y muestra nombres de los
elementos de organización propuestos. Los nombres de cuentas y movimientos
existentes se consultan con los permisos actuales del usuario; una cuenta sin
acceso aparece como no disponible. El listado también resume los tipos de cambio.

Los importes explícitos de nuevas operaciones se suman por tipo, cuenta y moneda,
sin netear gastos e ingresos ni sumar los dos extremos de una transferencia.
No incluyen comisiones ni representan una variación neta de saldo; las ediciones,
borrados o referencias pendientes no se presentan como importes conocidos.
Cada grupo distingue las operaciones aplicadas, fallidas, descartadas o sin aplicar.
Los recuentos son de operaciones: un borrado masivo puede afectar a varios
registros y una transferencia a ambas cuentas. No se presenta cada campo individual.

Solo el usuario propietario, con su familia actual y una sesión web autenticada,
puede aprobar o descartar. Los formularios conservan CSRF. El token de revisión
firma el contenido exacto y caduca en una hora: si el asistente añade operaciones
mientras se revisa, hay que recargar antes de aprobar. Una API key o token MCP
no autentica la aprobación web. La decisión no está expuesta en MCP ni REST.

La aprobación pone en cola un job persistente. Cada operación y su estado de
finalización se guardan juntos; los reintentos reanudan sin duplicar cambios.
Se vuelve a comprobar actividad del usuario, credencial, scope, configuración MCP,
familia, permisos y validaciones nativas. Se usa un contexto nuevo del actor sin
suplantación. Las ejecuciones aprobadas tienen un namespace de idempotencia propio,
separado de las llamadas REST anteriores.

Un deadlock de PostgreSQL revierte la operación en curso y permite hasta cinco
intentos del job, separados por la espera de Active Job. Cada intento continúa
desde la primera operación pendiente y vuelve a comprobar la autoridad; no
repite las operaciones completadas. Si se agotan los intentos, la propuesta
se marca como fallida con el resto sin aplicar.

**La propuesta no es una transacción global.** Se aplica en orden; ante un fallo,
se detiene. Las operaciones ya completadas quedan canónicas y se muestra cuántas
se aplicaron, el fallo y las restantes. Un job de importación/sync aprobado puede
seguir ejecutándose tras completar su operación de lanzamiento: consultar su estado
nativo. No hay rollback de llamadas remotas ni de trabajos ya comprometidos.
Descartar una propuesta fallida solo descarta lo que no se completó.

Las previsualizaciones inmediatas firmadas y subidas conservan su caducidad nativa. Si
caducan mientras se espera aprobación, la operación falla cerrada; hay que preparar
una nueva propuesta con referencias vigentes. No se regeneran aprobaciones ni
previsualizaciones destructivas automáticamente. Una edición posterior del usuario
puede invalidar una operación o ser sustituida por una edición explícitamente
aprobada; no se añade versionado de registros en esta entrega.

## Alcance y despliegue

La API REST y la interfaz web conservan sus escrituras nativas inmediatas. La
bandeja protege las herramientas MCP, no transforma una API key reutilizable en
una credencial restringida exclusivamente a propuestas para otros transportes.

La migración `20261021160000` añade la tabla de propuestas. Se prepara y valida
en el entorno aislado; no se ejecuta contra la instalación del usuario. Desplegar
web y worker juntos. No se incluye papelera, versiones ni deshacer; los exports
y backups siguen siendo la recuperación externa. Los datos pendientes no se
mezclan con los informes ni con las exportaciones financieras canónicas.
