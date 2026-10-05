# Alcance del producto Relay

Estado al cierre de la poda (fase 12, 5 de octubre de 2026). Este documento
resume qué mantiene Relay, qué se retiró y qué compatibilidad queda. El detalle,
las pruebas y las decisiones de cada paso están en el
[plan de poda](migration/pruning-plan.md) y los registros de cada fase.

## Producto mantenido

Relay es un gestor de finanzas personales **self-hosted de instancia única**,
basado en Sure. No existe modo SaaS, suscripción, telemetría ni servicio alojado.

| Área | Se conserva |
| --- | --- |
| Núcleo financiero | Cuentas de todos los tipos, movimientos, divisiones, transferencias y matching, saldos, conciliaciones, valoraciones, multimoneda con tipos manuales y guardados |
| Planificación | Agenda (pagos programados, único motor de pagos previstos), presupuestos, Goals y compromisos, insights deterministas |
| Informes | Dashboard, cash flow/Sankey, informes, gastos compartidos, indicadores propios, roboadvisor e inversiones en informes |
| Inversiones | Posiciones, operaciones, precios introducidos o importados, coste base; posiciones importadas autoritativas de cuentas antes conectadas |
| Organización | Categorías, etiquetas, comercios con logo propio, reglas y ejecuciones |
| Familia y permisos | Usuarios, roles, invitaciones, propiedad y compartición de cuentas, impersonación de administración |
| Acceso | Contraseña, MFA, passkeys/WebAuthn, OIDC/SAML/SSO, OAuth (Doorkeeper) y API keys |
| Importación | CSV de transacciones, operaciones, cuentas, categorías, reglas y comercios; Mint, Actual, YNAB, QIF; documentos PDF almacenados sin extracción automática |
| Recuperación | Exportación/importación ZIP completa (versión 3) con originales, informe de omisiones y readback |
| Integraciones externas | Enable Banking (sincronización bancaria), Brandfetch (logos), Google Drive (exportación CSV programada). Todas desactivadas hasta que un administrador las habilita |
| Clientes | Web/PWA, app Flutter para Android y API v1 documentada en [OpenAPI](api/openapi.yaml) para clientes propios futuros. Ver [clientes](clients.md) |
| Almacenamiento | Active Storage local (`/rails/storage`) |

## Instalación, actualización y operación

- **Instalación soportada:** TrueNAS con `compose.truenas.folder.yml` y el
  actualizador `update-relay.sh`, que hace backup completo de servidor antes de
  cada actualización. Ver [TrueNAS](hosting/truenas.md).
- **Docker genérico:** `compose.example.yml` (+ `compose.source.yml` para build
  desde Git). Ver [Docker](hosting/docker.md).
- **Sin canales de distribución:** no hay imagen pública, chart Helm, releases de
  clientes ni publicación en tiendas. Los workflows heredados están archivados en
  [docs/archive/sure/workflows](archive/sure/workflows/).
- **Desarrollo y pruebas:** Docker local en Windows; ver
  [guías de desarrollo](llm-guides/README.md).
- **CI activo:** Relay CI en `main` (Brakeman, auditoría JS, RuboCop, Biome,
  tests unitarios y de sistema), el mismo CI en PR, escaneo de secretos Pipelock
  en PR y Mobile CI para cambios en `mobile/`. Dependabot revisa gems y acciones.

## Retirado

| Fase | Retirada | Datos |
| --- | --- | --- |
| 3 | Telemetría y monitorización remotas (PostHog, Sentry, Skylight, Logtail, Langfuse) y evaluaciones LLM | Sin datos financieros |
| 4 | Plataforma comercial SaaS: Stripe, suscripciones, trials, modo gestionado | Tablas de suscripción eliminadas en fase 10 |
| 5 | Endpoint MCP, registro dinámico OAuth y asistente externo | — |
| 6 | IA integrada: chat, categorización/enriquecimiento por modelos, extracción PDF, embeddings | Conversaciones y uso eliminados en fase 10 |
| 7 | Los 25 conectores de cuentas salvo Enable Banking (Plaid, SimpleFIN, SnapTrade, Indexa, IBKR, Lunchflow, etc.) | Cuentas conservadas como manuales con su historial; conexiones eliminadas en fase 10 |
| 8 | Bills y detección de recurrencias (Agenda queda como único motor) | Tablas Bills eliminadas sin conversión a Agenda |
| 9 | Proveedores de cotizaciones y tipos de cambio, almacenamiento remoto S3, FinanceKit | Precios/tipos ya guardados conservados |
| 10 | 72 tablas y columnas, settings y vínculos exclusivos de lo anterior | Irreversible sin backup de servidor previo |
| 11 | Chart Helm, proxy Pipelock, plantilla TrueNAS de volúmenes nombrados, guías de funciones retiradas | — |
| 12 | Familia demo, RentCast/Realie, escritorio macOS, apps iOS (SwiftUI y destino iOS/web de Flutter), notificaciones push, gems de profiling y restos sin uso (controladores, imágenes, 7.150 traducciones) | Suscripciones push, contadores de peticiones AVM, columnas AVM de inmuebles, ajustes y clave API demo eliminados; las valoraciones ya guardadas se conservan |

Reintroducir cualquiera de estos módulos requiere una decisión de producto
explícita; su código sigue recuperable en Git.

## Pérdidas deliberadas y compatibilidad

- **Datos descartados en fase 10:** historial de conexiones retiradas, Bills,
  conversaciones IA, suscripciones y evaluaciones. Solo un backup de servidor
  anterior (PostgreSQL + originales) con código compatible lo recupera.
- **Backups familiares antiguos** (incluidos los de Sure): se validan íntegros y
  se importa el producto soportado; los módulos retirados se omiten con un
  informe `retired_data_discarded` y `scope: supported_product`. Referencias
  financieras ausentes, campos desconocidos o bytes corruptos siguen siendo error.
  Ver [backups](llm-guides/backups.md).
- **Cuentas antes conectadas** funcionan como manuales, conservando estrategia de
  saldo, posiciones autoritativas, observaciones de saldo y rendimiento de Indexa.
- **Identificadores externos heredados** (`sureapp://` de la app Android, ID de
  paquete, tipo `SureImport`, GlobalIDs históricos) se mantienen como contratos, no
  como marca. El esquema `sure://` del escritorio desapareció con él en fase 12.
- **Inmuebles:** se crean y valoran manualmente; las valoraciones importadas antes
  por RentCast/Realie siguen como valoraciones normales.
- **Jobs y cron retirados:** sus clases de compatibilidad se eliminaron en fase 11
  tras comprobar en TrueNAS que no quedaban jobs ni cron pendientes. Un job
  serializado de un módulo retirado ya no se puede ejecutar; ver
  [fase 11](migration/pruning-phase-11.md).
