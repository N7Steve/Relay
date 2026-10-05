# Fase 11 — cierre de soporte, documentación y métricas

5 de octubre de 2026. Base: `eaf35e3ff` (fase 10), `main` sincronizado con
`origin/main`. Selección ya confirmada en el [plan](pruning-plan.md#fase-11--cerrar-el-soporte-y-medir-la-reducción).
Steve pidió ejecutarla tras indicar que la fase 10 parecía funcionar.

## Estado de la instalación observado

Steve ejecutó en TrueNAS una auditoría de solo lectura de Sidekiq (colas,
scheduled, retry, dead, procesos y cron). Resultado:

- Revisión en ejecución: `d2e790ed6` (**fase 9**). La fase 10 está publicada
  pero **no desplegada**: su migración irreversible se aplicará en la próxima
  ejecución de `update-relay.sh`, que antes guarda el backup completo de servidor.
- Un proceso Sidekiq, ningún job en curso y **ningún job** en colas, scheduled,
  retry ni dead.
- Cron persistido: solo las 8 entradas vigentes cuyo capability está activo.
  No queda ninguna definición retirada (`sync_hourly`, Bills, FinanceKit,
  mercado, comercial).

El código desplegado (fase 9) no encola ninguna de las clases retiradas aquí;
solo las nombraba en `ExternalAccess::JobPolicy`. Por tanto no pueden aparecer
jobs nuevos de esas clases entre la auditoría y la actualización.

## Alcance aplicado

### Compatibilidad de jobs

- Retiradas 31 clases que solo consumían jobs serializados antes de la poda:
  conectores retirados (Plaid, SimpleFIN, SnapTrade, Sophtron, Indexa, Questrade,
  Redbark, Trade Republic, sincronización horaria), comercial (Stripe, limpieza
  de familias inactivas), Bills, FinanceKit, mercado (importación, salud de
  valores y Yahoo), IA (`AssistantResponseJob`, `WorkerAiHealthCheckJob`) y
  extracción PDF (`ProcessPdfJob`).
- `ExternalSchedule` ya no borra definiciones cron retiradas: la auditoría
  confirmó que no quedan en Redis. Sigue desactivando el cron de capacidades
  externas deshabilitadas.
- `ExternalAccess::JobPolicy` solo enumera los jobs de sincronización vigentes.
- Se conservan las adaptaciones del núcleo: tipo `SureImport`, política de
  descarte de backups antiguos y `discard_on ActiveJob::DeserializationError`.
- Pruebas: se eliminan las de sinks; las de sincronización y retirada comprueban
  que las clases ya no existen y que la sincronización programada sigue funcionando.

### Hosting y canales

- Retirados el chart Helm `charts/sure/` (37 archivos), `pipelock.example.yaml`
  (proxy de salida usado por la IA/MCP retirados) y `compose.truenas.yml`
  (plantilla de volúmenes nombrados, incompatible con el actualizador).
  `compose.truenas.folder.yml`, `compose.example.yml`, `compose.source.yml`,
  `compose.local.yml` y `compose.test.yml` se mantienen.
- Retiradas 13 guías de `docs/hosting/` de funciones retiradas o hosting no
  elegido, `docs/api/chats.md` y el roadmap público de Sure. Sus copias
  históricas útiles ya estaban en `docs/archive/sure/`; el resto queda en Git.

### CI y Dependabot

- `pipelock.yml` mantiene el escaneo de secretos de PR y valida el Compose
  de ejemplo; deja de instalar Helm y de validar el proxy.
- `pr.yml` deja de ignorar `charts/**`.
- `ci.yml`, `relay-ci.yml`, `mobile-ci.yml` y `flutter-build.yml` no dependían de
  plataformas retiradas: sin cambios. Dependabot (bundler y GitHub Actions)
  tampoco: sin cambios.

### Documentación consolidada

- Nuevo [alcance del producto](../product-scope.md): producto conservado,
  retiradas por fase, pérdidas deliberadas, compatibilidad de backups y contratos.
- Reescritas [Docker](../hosting/docker.md), [clientes](../clients.md) y
  [logos](../hosting/logos.md); onboarding solo ofrece Enable Banking.
- Marca Relay en guías OIDC, WebAuthn, Drive, API, `CONTRIBUTING` y README de
  escritorio, Flutter e iOS. Se conservan los contratos externos `sure://`,
  `sureapp://`, identificadores de paquetes y `SureImport`.
- `README`, índice de guías, archivo Sure, `FORK_CUSTOMIZATIONS` y
  `RELAY_MIGRATION` apuntan al cierre. Registro de fase 10 corregido con el
  estado real de despliegue.
- OpenAPI no cambia: esta fase no toca endpoints.

## Métricas iniciales y finales

Medidas con `script/pruning/measure.ps1` (JSON fuera de Git en
`tmp/pruning-phase-11/final-metrics.json`) sobre el árbol final de esta fase,
frente a la [fase 0](pruning-phase-0.md#métricas-iniciales) en `1e279bd8f`.
Las áreas se solapan; las líneas incluyen comentarios y blancos.

| Métrica | Fase 0 | Final | Cambio |
| --- | ---: | ---: | ---: |
| Archivos versionados | 7.189 | 5.161 | −28 % |
| `app/`: archivos / líneas | 2.338 / 244.490 | 1.403 / 119.034 | −51 % líneas |
| Proveedores `app/models/provider/`: líneas | 24.061 | 1.430 | −94 % |
| Controllers: líneas | 33.147 | 18.105 | −45 % |
| Jobs: archivos / líneas | 63 / 2.793 | 32 / 1.193 | −57 % líneas |
| `test/`: archivos / líneas | 1.135 / 201.513 | 646 / 104.045 | −48 % líneas |
| Flutter `mobile/`: líneas | 28.011 | 24.502 | −13 % |
| Tauri `desktop/`: líneas | 2.402 | 2.402 | = |
| Apple `bitrig/`: líneas | 1.557 | 1.157 | −26 % |
| Declaraciones Gemfile | 99 | 84 | −15 |
| Specs Gemfile.lock | 323 | 276 | −47 |
| Adapters de proveedores | 27 | 1 | −26 |
| Entradas cron estáticas | 16 | 10 | −6 |
| Workflows activos | 6 | 6 | = (contenido reducido) |
| Tablas del esquema | 158 | 86 | −72 |
| Archivos de locales | 2.463 | 1.946 | −517 |

No se han medido rendimiento, memoria, tamaño de imagen productiva ni duración
de CI en la instalación; no se declara ningún ahorro en esos aspectos.

## Extensiones retenidas y motivo

| Extensión | Motivo |
| --- | --- |
| Enable Banking | Opción futura de sincronización bancaria (fase 7) |
| Brandfetch | En uso (fases 0 y 9B) |
| Google Drive | En uso (fases 0 y 9D) |
| RentCast/Realie | Valoración inmobiliaria opcional, sin decisión de retirada |
| Presupuestos, Goals, insights | Conservados por decisión de Steve (9C) |
| Acceso completo (OIDC/SAML, MFA, passkeys, OAuth, API keys) | Conservado por decisión de Steve (9E) |
| Clientes Tauri, Flutter y SwiftUI | Conservados; posible uso de la APK (9F) |
| Contrato push iOS | Necesario para los clientes conservados; entrega desactivada |
| Backup programado con rclone en Compose de ejemplo | Copia de base de datos genérica, independiente de Active Storage S3 |
| Pipelock como escáner de secretos | Comprobación de seguridad aplicable a PR |

## Contratos

- API, clientes, backups (ZIP 3, snapshot 1) y configuración: sin cambios.
- Jobs: un job serializado de una clase retirada fallaría ahora por
  `NameError` y acabaría en retry/dead. La auditoría muestra que no existe
  ninguno y el código desplegado no los genera.

## Validación

- Suite completa en Docker (`relay-tests`, carga de esquema y assets incluidas):
  5.554 pruebas, 24.197 assertions, sin fallos ni errores, 38 skips
  (fase 10: 5.562; la diferencia son las pruebas de sinks retiradas).
- RuboCop (1.775 archivos, sin infracciones), ERB lint, Brakeman (0 avisos) y
  Biome (134 archivos) pasan.
- `docker compose config` válido para `compose.example.yml` solo y combinado con
  `compose.source.yml`; los seis workflows se parsean como YAML válido.
- Enlaces relativos de la documentación activa comprobados; quedan rotos solo
  en registros históricos (mapa de preservación de instrucciones y archivo Sure).
- Auditoría Sidekiq de solo lectura en TrueNAS, descrita arriba.
- No se han ejecutado system tests: la fase no toca vistas ni JavaScript.
  No se ha ejecutado el workflow Pipelock modificado; se validará en el próximo PR.

## Reversión

Unidades independientes: documentación, workflows/plantillas y compatibilidad
de jobs. Revertir esta fase con Git restaura las clases de compatibilidad, el
chart y las guías sin tocar datos; ninguna parte modifica esquema ni datos.
Tras revertir, una instalación nueva del chart requeriría revisar de nuevo su
configuración, ya que no se mantiene desde la fase 9.

## Cierre

Con esta fase la poda queda completa: producto y documentación coinciden.
Instalación nueva (schema load), actualización (migración de fase 10 ensayada)
y recuperación de datos (ZIP v3 y backups antiguos con descarte) están cubiertas
por las pruebas. Queda una operación pendiente fuera del repositorio: **actualizar
TrueNAS**, que aplicará en una sola ejecución las fases 10 y 11 con backup previo.
