# API/MCP: integraciones y administración (fase 8)

El [contrato MCP](mcp.md) y OpenAPI describen transporte, esquemas y rutas fijas
`POST /api/v1/actions/<nombre>`. La credencial limita al actor; nunca sustituye
permisos sobre cuentas, propiedad, rol familiar o presencia humana. Las nuevas
operaciones conservan los motores existentes y no añaden migraciones.

## Autoridad y cambios de acceso

| Ámbito | Operaciones y autoridad |
| --- | --- |
| Actor | Perfil, idioma, preferencias y preview propios; sesiones, claves y grants propios; conexión y programaciones Drive propias |
| Propietario | Consultar/cambiar compartición de su cuenta; compartición de su presupuesto personal |
| Cuenta compartida | Cada usuario cambia su propia participación financiera; no puede conceder permisos a otros |
| Administración familiar | Ajustes familiares e invitaciones pendientes; los procesos bancarios exigen además visibilidad y escritura financiera en todas las cuentas |
| Administración de instancia | Ajustes no secretos enumerados, diagnóstico depurado y recuperación de trabajos; el rol no concede permiso financiero sobre cuentas privadas |

`get_capabilities` enumera herramientas según el scope y explica las restricciones;
la presencia en el catálogo no promete autoridad sobre un registro concreto.
Cada ejecución, incluido un replay, vuelve a comprobar permisos. Las escrituras
usan `idempotency_key` y no guardan tokens existentes o contraseñas como resultado.

`preview_access_change` recibe una operación concreta y sus campos. Enumera el
impacto y firma actor, payload y versiones durante diez minutos. Las operaciones
de ejecución son `update_account_share`, `update_budget_share`,
`update_member_role`, `delete_account`, `unlink_account` y `disconnect_bank`.
Cambiar permiso, destino o datos invalida la previsualización. La firma representa
el plan delegado del servidor; no simula una confirmación humana.

Los destinos de compartición pertenecen a la misma familia y están activos.
Un owner de cuenta puede conceder full_control/read_write/read_only; null revoca.
Un owner de presupuesto solo concede read_write/read_only o revoca con null.
Compartir presupuesto no comparte sus cuentas. Solo un super_admin cambia roles
por esta API, dentro de su familia y sin cambiarse a sí mismo ni a otro super_admin.
La gestión restante de identidades conserva su consola nativa.

Desvincular una cuenta conserva movimientos e identifica posiciones como locales.
El borrado es asíncrono, exige cuenta sin proveedor y **autoridad financiera sobre
toda la familia**, porque el cleanup nativo también toca transferencias, Agenda y
vínculos de Goals. El owner sin esa autoridad puede usar el ciclo nativo de su cuenta
en el navegador. No se presenta esa limitación como permiso otorgado por ser admin.

## Perfil, familia y seguridad

`get_profile`, `update_profile`, `get_preferences`, `update_preferences`,
`get_family_settings`, `update_family_settings` y `list_members` usan campos
enumerados. Preferencias booleanas permanecen booleanas; monedas, zonas, idiomas,
calendario y presupuestos se validan mediante los modelos. Cambiar email conserva
la verificación nativa en el navegador. La lista de miembros no devuelve emails,
contraseñas ni configuración de seguridad.

`list_invitations`, `create_invitation` y `revoke_invitation` gestionan preparaciones
pendientes. Crear no envía correo, no expone el token y no traslada automáticamente
una identidad existente a otra familia. La entrega/aceptación y las invitaciones
administrativas se revisan en la página autenticada de perfil.

`list_sessions`/`revoke_session`, `list_api_keys`/`revoke_api_key` y
`list_oauth_grants`/`revoke_oauth_grant` siempre se limitan al actor. Revocar un grant
revoca sus tokens y códigos de autorización para esa aplicación. Se muestran
identificadores, scopes y tiempos, sin claves, tokens, hashes ni secretos MFA.
`get_security_status` devuelve únicamente estado y conteos. Revocar la credencial
usada puede hacer que la siguiente petición falle con 401.

`get_human_flow` devuelve una ruta GET relativa y `human_required: true` para:

- Contraseña, email, MFA, passkeys y enlace SSO.
- Emisión de API keys y registro de clientes OAuth.
- Borrado de miembros, cambio de familia, reset y administración de identidades/SSO.
- Configuración bancaria, selección de banco, reautorización y SCA.
- Configuración de Drive y consentimiento OAuth.
- Ciclo nativo de una cuenta para su owner.

Hay comprobaciones de rol antes de dar rutas administrativas y comprobaciones de
cuenta/conexión para rutas concretas. Abrir una ruta no completa la operación:
el navegador exige su identidad y los desafíos/consentimientos nativos. El cliente
debe presentar el enlace a la persona, no fabricar la prueba de presencia. La
emisión de secretos se conserva fuera del registro de resultados idempotentes.

## Enable Banking, sincronización y recálculo

`list_bank_connections`, `get_bank_connection` y `list_bank_accounts` muestran
estado, caducidad y cuentas guardadas; omiten certificado, application ID, session ID,
PSU IP y payloads crudos. `setup_bank_account` usa
`Account.create_from_enable_banking_account` y asigna el owner al actor desde el
inicio. `link_bank_account` vincula explícitamente una cuenta manual y un registro
bancario sin vínculos previos; trasladar historial exige desvincular antes.
`update_bank_connection` solo cambia nombre y fecha inicial. `disconnect_bank`
requiere previsualización, conserva el historial financiero y usa el unlink nativo.

La configuración de credenciales, selección de banco, consentimiento y callback
usan el navegador autenticado. No se recuperan secretos desde la API ni se
sustituye SCA. Con acceso externo suspendido se puede consultar el estado local;
la sincronización bancaria queda bloqueada tanto al solicitarla como al ejecutarla.
Desconectar localmente no promete revocación remota si la red está suspendida.

`sync_family`, `sync_bank` y `recalculate_account` devuelven un Sync consultable
con `get_sync`/`list_syncs`. Recálculo por cuenta exige W y es **local**; no obtiene
precios, FX o datos bancarios. La sincronización familiar conserva el comportamiento
nativo de ExternalAccess y exige administración/visibilidad/W familiar completa.
Los nuevos trabajos vuelven a comprobar usuario, credencial y autoridad antes de
ejecutarse. Una sincronización pendiente existente se reutiliza sin encolarla otra vez.

`cancel_sync` usa `Sync#request_cancel!`: un pendiente pasa a stale; uno en curso
recibe la solicitud cooperativa y cancela descendientes pendientes. No se afirma
que una cancelación pueda deshacer escrituras ya confirmadas. El detalle devuelve
estado y timestamps; los errores crudos quedan en la consola autorizada.

## Drive y acceso externo

`get_drive_connection`, `disconnect_drive`, `list_drive_schedules`,
`get_drive_schedule`, `create_drive_schedule`, `update_drive_schedule`,
`delete_drive_schedule`, `run_drive_export` y `list_drive_runs` se limitan a la
conexión/programaciones del actor. Las cuentas y filtros pertenecen al ámbito
autorizado. Crear una programación establece una recurrencia nativa explícita;
ejecutarla inmediatamente es una operación separada. Los trabajos programados
conservan las validaciones de acceso del modelo y la suspensión en el transporte.
La ejecución manual delegada vuelve a validar credencial, owner y cuentas.

No se devuelven refresh/access tokens, IDs de archivos o enlaces de descarga
externos a través del catálogo. Un fallo al revocar remotamente Drive se registra
sin secretos y la desconexión local conserva el comportamiento nativo.

`get_external_access` distingue valor guardado, override de entorno y estado
efectivo. Habilitar MCP no habilita banco, Drive o logos. Los cambios de esas
preferencias están enumerados en `preview_instance_settings` /
`update_instance_settings`, reservados a super_admin y con previsualización.
Un override puede mantener una capacidad apagada aunque se cambie su preferencia.

`set_local_image` usa el canal de subida de la fase 7 para avatar, icono de cuenta
y logo personalizado de comercio. Solo JPEG/PNG/WebP hasta 5 MiB; null elimina
la selección. Cuenta exige W; comercio exige autoridad familiar completa y usa
su personalización familiar, sin modificar un logo global de proveedor.

## Instancia, trabajos e insights

`get_instance_status` no expone valores secretos. Solo son escribibles los flags
de acceso externo, inclusión de pendientes, confirmación de email y horario/zona
de autosync enumerados. No hay un setter genérico. Se valida todo antes de guardar
y se usa un bloqueo de instancia para cambios delegados concurrentes.

`list_diagnostics` omite mensajes y metadata arbitraria; entrega categoría, nivel,
origen, proveedor y ruta de consola. `get_background_status` da conteos de runtime;
`list_background_operations` limita los registros a la familia y declara el límite
del modelo. `cancel_background_operation` solo recupera import/session/backup
presuntamente perdido: falla cerrado si Redis es desconocido, el escaneo está
incompleto o el job está en cola/ejecutándose. Comprueba edad/estado bajo bloqueo,
conserva datos/bloques comprometidos y registra auditoría. Sync tiene su cancelación
cooperativa separada. La consola global de otras familias sigue siendo humana.

`list_insights`, `set_insight_status` y `refresh_insights` conservan preview,
visibilidad familiar completa, estados y generadores deterministas; no reactivan
Bills o IA. La actualización de estado solicita un valor deseado, no un toggle.

La acción histórica de “limpiar caché” elimina precios/FX locales globales y
posiciones, que no son meramente datos regenerables con proveedores retirados.
**No se delega como una limpieza inocua**. La configuración de credenciales,
políticas SSO, lockdown de instancia y operaciones de host también quedan fuera
de las mutaciones delegadas. El [manifiesto de cobertura](../research/relay-api-mcp-coverage.yml)
registra estos límites y su razón, sin ocultarlos como paridad automática.
