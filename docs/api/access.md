# Identidad y permisos efectivos de la API

La API v1 admite `X-Api-Key` y OAuth Bearer. Sus credenciales identifican una
persona activa de Relay y limitan su acceso mediante scopes `read` o
`read_write`. No sustituyen la propiedad, compartición, autoridad familiar ni
gates de funcionalidad. No se admiten sesiones del navegador como credencial API.
Si se envía un Bearer inválido junto con una API key, la petición se rechaza;
no se cambia silenciosamente de identidad.

## Consultar capacidades

`GET /api/v1/context` devuelve actor, familia, zona horaria, método de
autenticación, scopes y capacidades generales. No devuelve claves ni secretos.
`capabilities.mcp` es false: las fases 0–1 preparan la base, el transporte
pertenece a la fase 2. Las respuestas API llevan `Cache-Control: private, no-store`.

Los objetos de cuenta añaden:

```json
"capabilities": { "read": true, "annotate": true, "write": false }
```

Ese ejemplo corresponde a una cuenta compartida con permiso de anotación y una
credencial de escritura. La misma cuenta, con una clave `read`, devuelve false
en annotate y write. Las capacidades reflejan autoridad, no garantizan que una
operación futura ya tenga endpoint. Siempre hay que manejar una denegación:
el permiso puede revocarse entre dos peticiones.

## Lectura, anotación y escritura financiera

| Permiso de cuenta | Con clave read | Con clave read_write |
| --- | --- | --- |
| Propietario o full_control | Leer | Leer, anotar y modificar finanzas |
| read_write | Leer | Solo anotar categoría, comercio, etiquetas y notas |
| read_only | Leer | Leer |
| Sin acceso | Sin acceso | Sin acceso |

El rol admin no concede por sí solo lectura ni escritura directa de una cuenta
privada de otro miembro. Un recurso inaccesible devuelve 404; intentar una
operación prohibida sobre uno visible devuelve 403. Cambiar datos financieros de
una transferencia o borrar una pata exige escritura en ambas cuentas. Su detalle
de contrapartida se omite cuando la segunda cuenta no es visible.

## Operaciones familiares y datos agregados

Importaciones (incluidos preflight, filas, sesiones y chunks), inicio de sync
familiar y estado de conexiones requieren administrador familiar, además del
scope correspondiente. Estos flujos actuales pueden operar sobre múltiples
cuentas o contienen archivos familiares: no están acotados a las cuentas
compartidas de un cliente. Es una restricción deliberada añadida en fase 1.

Los backups y reset familiares conservan su requisito de administrador. El
historial de sync de otros miembros solo incluye cuentas visibles y no expone
parent IDs familiares ni hijos privados. Los insights requieren preview y acceso
a todas las cuentas de la familia porque sus textos son resúmenes familiares
precalculados. Se excluyen los tipos Bills retirados.

Los presupuestos personales se leen con propiedad o BudgetShare; esa compartición
autoriza sus cifras resumidas, no sus cuentas. El presupuesto doméstico mantiene
asignaciones/carry compartidos; sus cálculos por viewer usan el contexto del
solicitante. Consultar categorías puede materializar rollover, como en la web.

## Datos y errores

- Fechas nuevas/revisadas: ISO `YYYY-MM-DD`. Importes: decimales finitos; no se
  aceptan NaN, Infinity ni cadenas parcialmente numéricas. Se conservan los
  campos monetarios formateados y unidades menores existentes de v1.
- En el ledger, positivo significa salida y negativo entrada. Una valoración es
  un valor absoluto. No reconstruir informes ignorando estas distinciones.
- Categorías y etiquetas deben pertenecer a la familia; el comercio debe estar
  disponible para la identidad. Referencias inválidas no producen escrituras
  parciales. Validación: 422; parámetros obligatorios ausentes: 400.
- FX/precio ausente conserva el mensaje heredado `error` y añade `code`
  (`missing_conversion` o `missing_price`) y `message`; nunca se fabrica 1:1.
- La idempotencia de transacciones por cuenta/source/external_id conserva el
  registro original. Esta fase no cambia las reglas históricas de replay ni el
  upsert de conciliación; el contrato ampliado está planificado en F3/F7.

Las formas exactas de respuesta están en [OpenAPI](openapi.yaml). El
[inventario de capacidades](../research/relay-api-capability-matrix.md) registra
los flujos pendientes, sus permisos, efectos y fases.
