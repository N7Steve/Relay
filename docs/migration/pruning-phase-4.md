# Poda fase 4 — Retirada de la plataforma comercial SaaS

Seleccionada por Steve el 4 de octubre de 2026. Base: `feccab08c`, presente en
`main` y `origin/main` al empezar. Árbol inicialmente limpio, fetch y fast-forward
sin cambios entrantes. Sin ramas, worktrees, PR, commit/push ni operaciones TrueNAS.

Publicación comprobada al iniciar fase 5: estos cambios están incluidos en
`92ee241a1`, presente en `origin/main`. Las notas de preparación sin commit/push
de este registro describen su estado al cerrar aquella implementación.

## Resultado

Relay funciona exclusivamente como instalación self-hosted. No existe selector
`app_mode`; `SELF_HOSTED` y `SELF_HOSTING_ENABLED`, incluso con valor `false`, ya
no permiten activar un modo comercial. El helper `self_hosted?` se conserva como
compatibilidad de las vistas de instalación y devuelve siempre `true`.

- Retirados SDK Stripe, proveedor/registro, procesadores de eventos, tareas Rake,
  checkout, portal, webhooks, upgrade, trials y pantallas/traducciones comerciales.
- Retirado `Family::Subscribeable`: sin bloqueo por suscripción, actualización de
  trial durante sync, cancelación remota al borrar ni selección de familias por
  caducidad. Onboarding termina en Inicio y conserva sus tres pasos locales.
- Administración conserva usuarios, roles, invitaciones, familias, cuentas y
  controles de eliminación; desaparecen estados, filtros y resumen de trials.
- La instalación mantiene controles de altas abiertas/cerradas/invite-only,
  asignación segura del primer super admin, invitación por enlace, confirmación
  de correo configurable y recuperación de contraseña. La variable comercial
  `REQUIRE_INVITE_CODE` no sustituye esas preferencias de instalación.
- Salud de Sidekiq, cifrado y límites API usan el comportamiento self-hosted.
  Retirados los tiers/cuotas comerciales por API key y sus contadores Redis;
  se conservan los límites generales y de credenciales de Rack::Attack.
  Se conserva la selección de proveedores SSO; en producción el default YAML
  sigue evitando consultas a tablas antes de preparar el esquema.
- Demo continúa desactivada por defecto; cualquier refresco exige familia
  explícitamente seleccionada y mantiene las protecciones de acceso de fase 2.
  No genera ni modifica suscripciones sintéticas.

IA, MCP, conectores, inversiones, informes, Agenda, permisos, Drive y Brandfetch
siguen conservados. IA requiere la puerta global, consentimiento y un proveedor
configurado: ya no existe la disponibilidad implícita del antiguo modo managed.
Las pruebas que ejercitan IA simulan explícitamente ese proveedor; las pruebas
de puerta cerrada y aislamiento siguen activas.

## Persistencia, backups y trabajos antiguos

No hay migraciones ni eliminación de tablas, columnas o datos existentes.
`subscriptions` y `families.stripe_customer_id` permanecen. `Subscription` es
persistencia histórica con estados legibles y pertenencia familiar; carece de
lógica de contratación, trial o pagos. La relación familiar elimina esa fila
únicamente como parte de una destrucción explícita autorizada de la familia.

Los contratos de backup no cambian: facturación de instancia sigue excluida y
`stripe_customer_id` no se traslada a la familia destino. No se necesita ejecutar
Stripe para exportar, restaurar o destruir explícitamente una familia de prueba.
Las exportaciones archivadas anteriores conservan sus lectores y descargas.

El worker retira únicamente el cron persistido `clean_inactive_families` al
reconciliar su agenda. `InactiveFamilyCleanerJob` y `StripeEventHandlerJob`
permanecen como clases de compatibilidad sin efectos para trabajos ya encolados
o en reintentos. No se purgan colas compartidas ni otros cron. Estas clases no
seleccionan familias, exportan, destruyen, actualizan facturación ni llaman a red.

APNs ya estaba deshabilitado en self-hosted: continúa así con cualquier variable
heredada o credencial Apple. Se mantienen los tokens históricos y el transporte
para la posterior decisión de clientes; no hay interruptor de activación.
Las rutas existentes devuelven el rechazo previsto y OpenAPI documenta ese
estado. Autenticación API/OAuth y clientes permanecen disponibles.

## Validación

Estado: fase implementada y validada en `main`, sin commit/push ni despliegue.
La suite completa ejecuta el código final en Docker Linux aislado.

- Rails completo: 10.772 pruebas, 45.979 aserciones, cero fallos y errores,
  46 omisiones preexistentes; 1162,65 segundos. No se añadieron omisiones.
- RuboCop, ERB lint y Biome correctos; Brakeman sin avisos activos ni nuevas
  exclusiones. Correcciones de formato limitadas a los archivos afectados.
- Pruebas focalizadas: 541 pruebas y 4119 aserciones, sin fallos, errores u omisiones.
- Navegador final: 28 pruebas y 167 aserciones, sin fallos, errores u omisiones.
- IA/autenticación y contratos: 62 pruebas y 313 aserciones, sin fallos, errores
  u omisiones; historia/invitaciones: 21 pruebas y 65 aserciones, también correctas.
- API self-hosted y protección Rack::Attack: 46 pruebas y 263 aserciones, sin
  fallos ni errores, una omisión preexistente. Uso API: 6 pruebas y 131 aserciones,
  sin fallos, errores u omisiones.
- Tanda IA/contratos retenidos: 178 pruebas y 872 aserciones, sin fallos ni errores;
  una omisión preexistente. Sin cambiar los controles de autorización para pasar.
- Recuperación previa: snapshot sintético de fase 0 → restore → export → restore.
  Recuperación nueva: export actual → restore → export → restore. Las cuatro
  restauraciones verifican 21 registros y un original cada una; valores
  financieros, relaciones y bytes coinciden y el rollback de datos está comprobado.
- Imagen de producción construida; arranque/eager loading offline comprobado con
  variables comerciales y credenciales de prueba. Sin Stripe, tareas/rutas
  comerciales ni reactivación APNs. Repetición final tras la revisión correcta.
- OpenAPI regenerado: 434 ejemplos documentales, sin fallos, 89 pendientes de
  documentación existentes. Diff limitado a los dos contratos APNs desactivados.

La primera tanda encontró expectativas heredadas del modo managed en invitaciones,
demo y disponibilidad IA. Se adaptaron a las preferencias locales y a proveedores
simulados explícitos. La primera suite completa se interrumpió tras identificar
las mismas dependencias en pruebas IA. Una ejecución posterior detectó las
expectativas de cuotas comerciales API; se sustituyeron por cobertura del contrato
self-hosted, manteniendo autenticación, scopes y Rack::Attack. Las ejecuciones
con esos fallos no constituyen evidencia de cierre. No se añadieron omisiones para ocultar fallos. La instalación real y su
backup privado no se han inspeccionado: la recuperación ensayada es sintética.

Evidencia local conservada en `tmp/` (no versionada):

- `pruning-phase-4-suite-closure.log`: suite completa de cierre.
- `pruning-phase-4-focused-validated.log`, `pruning-phase-4-ai-tests.log`,
  `pruning-phase-4-ai-contracts.log`, `pruning-phase-4-history-tests.log`,
  `pruning-phase-4-quota-tests.log` y `pruning-phase-4-usage-tests.log`.
- `pruning-phase-4-system-final.log` y
  `docker-test-results/phase4-admin-users.png`: navegador y captura administrativa.
- `pruning-phase-4-checks-complete.log`, `pruning-phase-4-final-lint.log`,
  `pruning-phase-4-quota-lint-final.log` y `pruning-phase-4-openapi.log`.
- `pruning-phase-4-prior-recovery.log`, `pruning-phase-4-current-recovery.log`,
  `pruning-phase-4-image-closure.log` y `pruning-phase-4-boot-closure.log`.

Los contenedores y redes de esta fase se detuvieron al finalizar, conservando
los volúmenes de prueba, imágenes y evidencia local. `git diff --check` correcto;
`main` y `origin/main` siguen en la base `feccab08c`, sin commits nuevos.

## Despliegue, reversión y continuación

Antes de desplegar, conservar backup de instalación y las mismas claves de
cifrado/`SECRET_KEY_BASE`; actualizar web y worker a la misma revisión. Drive y
logos requieren las activaciones explícitas de fase 2. Las variables Stripe
pueden retirarse del entorno; ya no tienen consumidor. No se cancelan contratos
ni cobros existentes en una cuenta externa Stripe desde esta entrega.

La reversión es de código/lockfile, con esquema compatible. Antes de volver a una
versión comercial anterior, retirar sus credenciales Stripe y su cron de limpieza
para evitar reactivar cobros o borrado por caducidad. No restaurar automáticamente
esas operaciones ni asumir que revertir Git revierte un estado externo.

Tras publicación autorizada se puede detener aquí con Relay
utilizable. La siguiente selección es fase 5, retirada de MCP/asistente externo;
no se implementa como parte de esta entrega.
