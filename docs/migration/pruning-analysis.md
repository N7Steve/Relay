# Estado de la migración y propuesta de poda de Relay

Análisis del 4 de octubre de 2026. Referencia examinada:
`1e279bd8f6fe05d295c074180efccbcd59195ad5` en `main`.

Este informe responde a la petición de análisis. Las propuestas no son
decisiones aprobadas ni autorizan eliminar funciones, datos o clientes.
No se ha cambiado código de producto ni operado la instalación TrueNAS.

Actualización tras [fase 0](pruning-phase-0.md), 4 de octubre de 2026: Steve
confirma importación completa y estable; web/worker ejecutan la revisión de este
análisis. Confirma uso de Google Drive y Brandfetch: ambas se conservan en el
plan, sustituyendo la recomendación inicial de retirada de logos remotos.
El resto de propuestas siguen requiriendo selección por fase.

## 1. Diagnóstico

Relay ya es un proyecto técnicamente independiente y, según Steve, está
desplegado y funciona. La separación de marca, repositorio, configuración y
distribución está suficientemente resuelta para utilizarlo como Relay.
La reducción funcional del producto todavía no está hecha: permanece gran parte
de la plataforma de Sure, incluso detrás de pantallas ocultas y puertas de IA.

Conviene cerrar la migración de identidad con sus excepciones documentadas y
abrir un trabajo distinto de simplificación del producto. No hace falta eliminar
cada aparición de «Sure» para considerar independiente la aplicación.

La dirección propuesta es: **núcleo financiero local, entrada de datos controlada
y conexiones opcionales solo cuando tengan un uso concreto**. Self-hosting no
implica necesariamente funcionamiento sin red; hay que decidir si cotizaciones,
divisas y exportaciones elegidas por el usuario siguen siendo útiles.

## 2. Qué está terminado y qué falta comprobar

| Área | Evidencia y estado |
| --- | --- |
| Repositorio e identidad | `origin` es Relay; namespace Rails, web/PWA, diseño, tareas y versión 0.1.0 propios. Completado en código. |
| Datos e importaciones | Escritores `RelayImport`, lectores históricos y defaults/constraints preparados. Backups completos posteriores ya incorporados. |
| Ensayo de transferencia | `docs/llm-guides/backups.md` registra 42.244 registros y 6 originales restaurados desde un ZIP Sure; reexportación y segunda restauración coincidentes. Ensayo aislado, no certificación de la instalación actual. |
| Distribución | Docker y TrueNAS preparados. La guía vigente añade instalación en carpeta y actualización con backup desde una revisión resuelta de `main`; el YAML inicial con SHA fijo no es toda la historia. |
| Despliegue | Confirmado por Steve. No se ha inspeccionado aquí la revisión realmente ejecutada, los volúmenes ni las migraciones aplicadas. |
| Telemetría | PostHog, Sentry, Skylight y Logtail no se inicializan según la entrega de separación. Sus gems siguen presentes. Langfuse todavía tiene configuración y trazas condicionadas por claves. |
| Clientes nativos | Marca adaptada; identificadores, esquemas URL y contratos conservados deliberadamente. La decisión documentada fue conservarlos. |
| Poda funcional | Pendiente: proveedores, IA, MCP, SaaS, recurrencias Bills y otros módulos siguen en el árbol activo. |
| Documentación de cierre | Pendiente de consolidar. Los estados intermedios de `RELAY_MIGRATION.md` y el formulario describen pendientes que entregas posteriores ya resolvieron. |

Las validaciones anteriores son evidencia documentada, no pruebas ejecutadas de
nuevo en este análisis. La entrega de backups registra 10.853 tests Rails sin
fallos ni errores; ello no certifica los commits posteriores de dependencias ni
la versión actualmente desplegada.

Para cerrar operativamente la migración bastaría recoger: SHA web/worker,
estado de migraciones, correspondencia de cuentas/saldos/Agenda/adjuntos con el
origen si hubo importación, accesos de usuarios y backup restaurable del destino.
No hace falta mantener abierta indefinidamente la migración por los namespaces
externos o por clases que leen datos históricos.

## 3. Hallazgos que afectan a la poda

### Sincronización local y conexión externa están mezcladas

`Account::Syncer#perform_sync` importa precios/divisas y materializa saldos.
Su postprocesamiento empareja transferencias. `Family::Syncer` programa items de
proveedores **y cuentas manuales**, además de aplicar reglas y matching.
`Entry` puede pedir un recálculo mediante el mecanismo de sync.

Por tanto, retirar `Syncable`, `SyncJob`, Sidekiq o toda la lógica de sync rompería
funciones locales. Hay que separar el refresco financiero local de la adquisición
remota de datos, conservando los recorridos que necesitan cálculos asíncronos.

### Apagar el autosync global no crea un modo sin conexiones

- `Setting.auto_sync_enabled` tiene default verdadero; al arrancar Sidekiq,
  `AutoSyncScheduler` registra su trabajo según ese ajuste.
- `families.auto_sync_on_login` también tiene default verdadero y el concern
  `AutoSync` puede pedir un refresco Plaid y una sincronización familiar.
- `config/schedule.yml` registra independientemente trabajos de mercado,
  sincronización horaria, valoración inmobiliaria y FinanceKit, entre otros.
- `ExchangeRate::Provided#find_or_fetch_rate` puede consultar un proveedor cuando
  faltan tipos guardados; no depende del cron de autosync.
- Los logos pueden proceder de URLs Brandfetch o de proveedores y cargarse en el
  navegador. No todo acceso externo ocurre desde Rails o un worker.

Esto describe posibilidades del código y defaults. No demuestra que la instancia
actual tenga conexiones configuradas ni que esté realizando esas solicitudes.

### Bills oculto conserva coste interno

La puerta `bills_frontend_enabled` es falsa en producción, pero su alcance es el
frontend. `GenerateRecurringOccurrencesJob` consulta el ajuste familiar
`recurring_transactions_disabled`, cuyo default es falso. Insights dependientes
de Bills pueden seguir generándose y almacenándose, aunque el fork los filtra
para no mostrarlos. La puerta actual no equivale a un subsistema suspendido.

Agenda y Bills son dominios distintos. Hay que conservar `ScheduledPayment` y
`ScheduledPaymentEntry`; cualquier idea útil de recurrencias se puede adaptar
selectivamente a Agenda sin conservar toda la segunda plataforma.

### La telemetría todavía no está retirada como dependencia

El Gemfile mantiene Sentry, PostHog, Skylight y Logtail. Además,
`config/initializers/langfuse.rb` configura Langfuse si hay claves; OpenAI y
Anthropic tienen trazas condicionadas por ellas y existe infraestructura de
evaluaciones en `app/models/eval/`. La puerta IA protege recorridos de proveedores,
pero Langfuse no tiene en su inicializador el cierre incondicional de Sentry.

No se ha observado tráfico real. La conclusión es que la política de ausencia de
telemetría todavía no se refleja completamente en la retirada de SDK y código.
Las llamadas existentes a Sentry requieren sustitución coherente por logs locales
al quitar sus gems; borrar solo las dependencias introduciría errores.

### Los backups son una dependencia crítica de casi cualquier eliminación

`Family::Backup::MODEL_NAMES` contiene proveedores, Bills, chats, goals,
FinanceKit y Google Drive. `Family::Backup.models` hace `constantize` de todo ese
inventario. Borrar una clase sin adaptar ese contrato puede romper incluso un
backup de una familia que no usa la funcionalidad retirada.

El restorer rechaza modelos no admitidos y atributos desconocidos. Quitar nombres
del inventario tampoco basta: puede impedir restaurar un backup anterior.
La transición necesita una decisión explícita por tipo de dato: mantener lector,
convertir a datos del núcleo o conservarlo en un archivo recuperable. No omitir
registros silenciosamente ni declarar restauración completa tras descartarlos.

### El coste de conservar lo inactivo ya es visible

En esta revisión hay 117 archivos bajo `app/models/provider/`, incluidos 27
adapters, y el inventario del backup enumera 25 familias de conectores, además de
FinanceKit. Estos recuentos no representan todo el código relacionado: faltan
modelos de payloads, controladores, vistas, tests, locales y configuración.

La factoría descubre y carga adapters; `Family` incluye numerosos concerns de
conexión. No son carpetas completamente aisladas. El historial reciente actualiza
`ruby-openai`, Stripe y Sentry Sidekiq: mantener funciones desactivadas sigue
generando trabajo de dependencias. No se ha medido ahorro de RAM, imagen o tiempo
de arranque; no sería riguroso prometer porcentajes de reducción.

## 4. Eliminar, suspender o conservar

Una puerta reduce actividad y exposición, pero mantiene código, dependencias,
pruebas y combinaciones que soportar. Usarla tiene sentido cuando existe un uso
futuro identificado o como paso breve para retirar una función con datos.

Para algo que solo «quizás sea útil», Git ya conserva la implementación. No hace
falta copiarla a otra carpeta dentro de `app/`, crear un sistema de plugins o
mantener una rama activa. Registrar el último commit que la contiene, contratos,
dependencias y motivo facilita recuperarla y adaptarla en el futuro.

La conservación de un lector de datos históricos es una cuestión distinta:
puede ser necesaria aunque se elimine el producto que creó esos datos.

| Bloque | Recomendación | Dependencia o límite principal | Esfuerzo orientativo |
| --- | --- | --- | --- |
| SaaS: modo managed, cobro Stripe, trials y limpieza de familias por suscripción | Eliminar comportamiento comercial; hacer self-hosted la configuración propia del producto. | `Family::Subscribeable`, onboarding, guards, correo, webhooks y callbacks de borrado. No quitar familias, roles ni permisos. La limpieza destructiva hoy está protegida por managed. | Medio |
| Telemetría remota y evaluaciones IA | Eliminar SDK, trazas, evals y configuración; preservar diagnóstico local. | Muchas referencias Sentry y código Langfuse; revisar web y clientes mantenidos. | Bajo/medio |
| MCP y asistente externo | Eliminar endpoints, herramientas y configuración específicos. | Comparten Doorkeeper con clientes/API; no retirar OAuth completo por quitar MCP. Datos de conversaciones/documentos y backups. | Medio |
| IA integrada, categorización y extracción por modelos | Recomiendo retirar si no se identifica un uso local concreto. Mantener puerta actual durante la transición. | Distinguir chat/PDF asistido de importaciones CSV/QIF/OFX y de reglas deterministas. Preservar originales adjuntos. | Medio/alto |
| Conectores bancarios, brokers, exchanges y on-chain sin uso | Eliminar conectores por lotes funcionales. | Cuentas enlazadas, estrategia reverse/forward, holdings y payloads históricos. Adaptar backups y registros de adapters. | Alto en conjunto |
| Autosync de conexiones externas | Apagar por defecto y separar de cálculos locales; retirarlo donde ya no queden conectores. | Cron persistido en Redis, login, webhooks, solicitudes manuales y trabajos ya encolados. | Medio |
| Valoración inmobiliaria remota RentCast/Realie | Eliminar si se usan valoraciones manuales. | Conservar cuentas Property, direcciones e historial de valoración. | Bajo/medio |
| Bills y recurrencias detectadas | Recomiendo retirar el subsistema tras inventariar datos y contactos. | Agenda, transacciones, transferencias, presupuestos, insights y snapshots de backup. | Medio/alto |
| Presupuestos, Plan y Goals | Suspender completamente y decidir por separado. Tienen posible valor para finanzas curadas. | Preview solo regula algunos accesos; sus trabajos y referencias financieras requieren auditoría. No dependen conceptualmente de IA. | Medio |
| Insights | Conservar únicamente señales locales útiles; retirar narración IA y generadores dependientes de módulos eliminados. | No confundir análisis determinista con IA; mantener comparaciones e indicadores propios. | Medio |
| Cotizaciones y divisas | Conservar datos y cálculo; elegir después entre entrada manual y un proveedor pequeño a demanda. | Exactitud de inversiones/roboadvisor y multimoneda. Sin tipos disponibles hay recorridos que usan 1 como fallback. | Medio/alto |
| Brandfetch y logos externos | Recomiendo retirar resolución remota y usar logos locales/iniciales. | Logos persistidos en cuentas/comercios/securities; conservar adjuntos y no descargarlos en masa automáticamente. | Bajo/medio |
| Google Drive | Opcional solo si sigue siendo un destino utilizado; si no, retirar conexión y programación conservando exportación local. | Es funcionalidad propia, con OAuth por usuario, no solo residuo Sure. Backups contienen su configuración. | Medio |
| SSO OIDC/Google/GitHub/SAML | Retirar protocolos no usados después de comprobar cómo acceden los usuarios. | Acceso local, MFA/passkeys y OAuth/API son piezas distintas. Drive puede compartir infraestructura de autenticación externa. | Medio |
| Clientes Flutter/Tauri/Apple y FinanceKit | Conservar por ahora según decisión previa; reevaluar con uso real. | Reducirlos podría dar gran ahorro de mantenimiento, pero no está aprobado abandonar clientes. FinanceKit no es equivalente a un proveedor bancario remoto. | Alto |
| Helm y hosting no elegido | Sacar del soporte activo y archivar guía/configuración que merezca conservarse. | Docker/TrueNAS y sus backups/actualización siguen siendo soporte principal. Revisar referencias Pipelock y ejemplos. | Bajo |
| S3/GCS y otros backends de almacenamiento | Retirar los no usados; distinguir S3 local de servicio cloud. | Adjuntos actuales, Active Storage y recuperación de backups. No borrar archivos por retirar un driver. | Bajo/medio |
| Nombres Sure históricos, licencia, migrations y lectores STI | Conservar cuando expliquen procedencia o permitan leer datos. | Ahorro insignificante; renombrado puede romper contratos sin simplificar el producto. | Sin prioridad |

## 5. Qué debe quedar como núcleo protegido

- Cuentas manuales, tratamientos included/tracking/outside_finances y archivo.
- Movimientos, transferencias, matching revisable, splits, categorías, comercios,
  etiquetas y reglas deterministas.
- Agenda, confirmación/rechazo, vínculos a movimientos y previsiones.
- Balances, inversiones y roboadvisor, precios históricos y cálculo multimoneda.
- Informes, patrimonio, comparaciones y períodos familiares propios.
- Usuarios, permisos de cuentas, aislamiento familiar y autenticación local.
- Importaciones controladas, backups completos, exportaciones locales y adjuntos.
- Interfaz web/PWA, tokens, componentes DS y preferencias de navegación.
- Trabajos de cálculo, generación de Agenda, recuperación de trabajos atascados
  y diagnóstico local necesarios para operar el núcleo.

Ni la automatización local de Agenda ni las reglas propias contradicen el control
curado. Automatizar una instrucción explícita del usuario es distinto de obtener
o modificar información desde un sistema externo sin una decisión puntual.

## 6. Secuencia recomendada

1. **Cerrar la foto de migración.** Consolidar los estados documentales, registrar
   la revisión desplegada y confirmar backups/importación. Obtener conteos por
   módulo y conexiones activas, sin revelar credenciales. Es lectura e inventario.
2. **Establecer el comportamiento local.** Self-hosted como configuración propia;
   conexiones externas desactivadas por defecto. Separar materialización/matching
   de adquisición remota. Si se conservan capacidades opcionales, usar pocas
   políticas centralizadas y cubrir controller/API/job/webhook/proveedor,
   navegación y configuración. No añadir un interruptor para cada archivo.
3. **Retirar lo sin encaje claro.** Telemetría/evals y SaaS; después MCP/asistente
   externo y conectores sin uso. Cada bloque incluye dependencias, tests, locales,
   jobs, OpenAPI si cambia API, configuración y documentación.
4. **Retirar la duplicación funcional.** Bills manteniendo Agenda. Decidir aparte
   presupuestos/Goals e insights locales, sin perder funcionalidades propias.
5. **Elegir las pocas extensiones mantenidas.** Cotizaciones/divisas, Drive y
   clientes nativos según uso real. Toda extensión retenida tiene finalidad y
   política de activación documentadas.
6. **Reducir esquema en otra entrega.** Tras inventario, backup recuperable y
   conversión/archivo comprobados, preparar migraciones nuevas para retirar
   tablas/columnas obsoletas. No borrar migraciones históricas ni mezclar
   eliminación de datos con el primer corte de código.

Al cambiar el schedule no basta con quitar YAML: retirar también los cron
anteriores persistidos y definir qué ocurre con jobs encolados. Al quitar un
connector no ejecutar automáticamente sus callbacks destroy: podrían borrar
payloads o modificar relaciones. La conversión de una cuenta a manual requiere
verificar su saldo de partida y toda su historia.

## 7. Validación y criterio de finalización de la poda

Por bloque, una funcionalidad retirada deja de tener accesos HTML/API/webhooks,
jobs programados, callbacks activos, ajustes visibles y dependencias exclusivas.
Una función suspendida no debe crear datos ni enviar solicitudes y debe rechazar
invocaciones directas y trabajos antiguos. Un enlace oculto por sí solo no cumple.

Ensayar el núcleo con conexiones salientes bloqueadas y comparar saldos, holdings,
transferencias, informes, Agenda y previsiones con una referencia anterior. El
modo local debe señalar información financiera ausente; no presentar como exacta
una conversión que usa un fallback de tipo 1 o cotizaciones insuficientes.

Probar backups anteriores a la poda, exportar un backup nuevo y restaurarlo en una
base aislada. Comparar registros relevantes, relaciones, valores y bytes de
adjuntos. Una eliminación que rompe recuperación no es una simplificación válida.

Ejecutar tests focalizados y suite Rails en Docker Linux, con lint y verificaciones
API/clientes que correspondan. Repetir pruebas con la política de producción:
las puertas Bills/IA tienen defaults diferentes en test. Para cualquier subida
se aplica la verificación exigida por el repositorio.

Medir archivos y líneas activas, dependencias directas/transitivas, rutas,
trabajos periódicos, duración de CI, tamaño de imagen y solicitudes externas.
La meta principal es menos contratos y menos comportamiento que mantener;
reducir solamente el número de carpetas no demuestra esa mejora.

## 8. Alcance de esta revisión

Se revisaron las guías de dirección/preservación/migración, la evolución posterior
de backups y TrueNAS, routes, Gemfile, settings, schedule y arranque Sidekiq,
syncers, registry/factory, gates Bills/IA/MCP, configuración de telemetría,
contratos de backup y puntos de autenticación/almacenamiento/clientes.
Es un análisis estático por subsistemas, no un grafo exhaustivo de dependencias.

El árbol estaba limpio. Se actualizó la referencia origin y se avanzó `main`
por fast-forward; solo llegaron cambios ya publicados de `Gemfile.lock`.
No se ejecutaron Rails, migraciones, servidores, despliegues ni llamadas a los
proveedores. El único archivo nuevo de este trabajo es este informe.

La petición actual reabre la limpieza que el formulario anterior aplazaba.
No se toma ese aplazamiento como prohibición de analizar. Las reglas previas de
preservar clientes/Drive/inversiones sirven para identificar cambios de producto
que deben decidirse, no para obligar a mantener código sin propósito para siempre.
