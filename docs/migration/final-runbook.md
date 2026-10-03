# Procedimiento de la fase final

Este documento prepara el traslado de una instancia única. No ejecuta comandos
sobre la instalación existente ni autoriza un despliegue. Las decisiones de Steve constan en el [formulario](final-decisions.md): publicar
Relay 0.1.0 para pruebas en TrueNAS, conservar clientes/funciones, desactivar
telemetría e importar los datos después de estabilizar la instalación. La
configuración y rutas del despliegue se concretan más adelante.

**Actualización del 4 de octubre de 2026:** Steve confirma que Relay ya está
desplegado, con los datos Sure importados y funcionamiento estable. La instalación
vigente está descrita en [TrueNAS](../hosting/truenas.md); el inventario y evidencia
de inicio de la poda están en [fase 0](pruning-phase-0.md). Los pasos siguientes
siguen sirviendo como procedimiento de ensayo/recuperación, no como estado pendiente
del traslado ya confirmado.

## 1. Inventario y punto de recuperación

Registrar revisión de Sure, imagen/digest, Compose y nombre de proyecto, motor y
versión PostgreSQL, nombre de base/usuario, volúmenes reales de base y adjuntos,
servicio ActiveStorage, Redis/colas y configuraciones de proveedores/callbacks.
Guardar configuración y claves en almacenamiento privado: `SECRET_KEY_BASE`,
claves de cifrado ActiveRecord y cualquier master key/credencial utilizada.
No rotarlas durante el traslado ni imprimirlas en logs.

Para cumplir «todos los datos necesarios», preparar una exportación completa de
la instalación: dump PostgreSQL y copia consistente del almacenamiento
binario (o snapshot del bucket). El ZIP de `Family::DataExporter` versión 3
incluye el snapshot relacional y los bytes originales de adjuntos disponibles;
los exports anteriores no recuperan archivos que el origen nunca incluyó.
Este backup familiar no sustituye un backup completo de instalación: configuración,
claves, autenticación y colas tienen alcance distinto. Ver
[backups completos](../llm-guides/backups.md). Registrar fecha, tamaño y checksum de los backups.
Planificar quiescencia de escrituras/worker para el snapshot final. Las tareas
Redis pendientes necesitan un tratamiento concreto según el inventario; no
conectar el ensayo al Redis de producción ni ejecutar sus jobs accidentalmente.

## 2. Ensayo aislado

Restaurar los backups en una base y almacenamiento independientes, sin acceso de
escritura a los originales. Desactivar workers, correos salientes, sincronización
bancaria, exportaciones programadas y cualquier automatismo externo hasta revisar
su configuración. Usar un Redis dedicado y URL/proxy de ensayo.

Construir/pinar una imagen de la revisión elegida. El build no arranca Rails.
Remapear variables `SURE_*` a `RELAY_*` y tareas `sure:*` a `relay:*`; ya no hay
aliases/fallbacks. Revisar Compose sin iniciarlo y hacer explícitos base, usuario, secretos, imagen,
montajes, onboarding y acceso de red. El entrypoint del Dockerfile puede ejecutar
preparación/migraciones al iniciar web: esa operación pertenece al ensayo
controlado sobre la copia y requiere conocer previamente su destino.

Registrar las migraciones aplicadas y resultados. Las migraciones Relay de
`import_sessions` permiten el tipo nuevo y cambian el valor por defecto; no
reescriben las filas históricas. No cambiar bases antiguas con un renombrado global.

## 3. Validación del ensayo

Comparar contra un inventario anterior a la restauración:

- Usuarios, familias, roles, cuentas, entradas, balances, holdings y adjuntos.
- Saldos y patrimonio para fechas fijas, divisas y tipos de cambio de la instalación.
- Agenda, previsiones, exclusiones de cálculos, transferencias, splits, préstamos,
  roboadvisor/inversiones, preferencias y períodos de widgets propios del fork.
- Inicio de sesión, autorización por familia/cuenta y MFA ya enrolado: los códigos
  existentes siguen usando el mismo secreto; solo el issuer de nuevas altas cambia.
- Descarga de adjuntos y descifrado de credenciales, sin mostrar sus valores.
- Exportación y reimportación Relay en datos de ensayo; consulta de backups históricos.
- APIs y callbacks de los clientes/proveedores elegidos; ninguna llamada real de
  escritura hasta habilitar explícitamente cada integración en su entorno previsto.
- PWA, assets, navegación y ausencia de destinos Sure en changelog/contacto/feedback.

Registrar resultados, discrepancias y tiempo real del procedimiento. No considerar
la suite automatizada sobre fixtures como prueba de restauración de datos reales.

## 4. Corte y recuperación

Con ensayo aprobado, preparar configuración final exacta, imagen/digest, ventana,
backup final consistente y responsables de revisión. Solicitar aprobación del
corte sobre este plan concreto. Detener las escrituras de Sure, restaurar el punto
final en Relay y validar antes de reactivar workers y automatismos.

Conservar el origen y backup anteriores. Si falla antes de admitir escrituras en
Relay, recuperar imagen/configuración/base/almacenamiento originales como un
conjunto. Si Relay ya recibió escrituras, reconciliar esos datos antes de volver;
no basta con cambiar la imagen ni se garantiza que Sure pueda leer el nuevo estado.
No se implementa compatibilidad entre releases para esta instancia única.

## 5. Cierre

Guardar revisión, digest, decisiones, comprobaciones y fecha del corte en
`RELAY_MIGRATION.md`. Retirar artefactos/clientes descartados solo tras delimitar
su alcance. Publicación Git/registro, limpieza de volúmenes y revocación/rotación de
credenciales son operaciones separadas: no derivarlas automáticamente del traslado.
