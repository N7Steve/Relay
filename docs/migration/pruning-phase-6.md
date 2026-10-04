# Poda fase 6 — IA integrada y control de Brandfetch

Seleccionada por Steve el 4 de octubre de 2026. Base `ecc901083`, árbol limpio,
`main` sincronizado con `origin/main` mediante fetch y fast-forward. Trabajo
directo en `main`, sin ramas, worktrees, PR ni commit/push.

## Resultado

- Retirados chat, herramientas del asistente, OpenAI, Anthropic, Jev, extracción
  PDF por modelos, embeddings/vector stores, prompts y diagnósticos IA.
- Retirados endpoints web/API de chat, activación IA, configuración de prompts,
  uso de modelos, enriquecimiento de comercios y sugerencias IA de Bills.
  OAuth, API keys, scopes y autenticación nativa siguen disponibles.
- Insights utiliza plantillas localizadas con los hechos calculados por sus
  generadores deterministas. Se mantienen reglas explícitas y los imports
  CSV/QIF/OFX/backup. Bills y Agenda conservan sus operaciones locales.
- Eliminados SDK y dependencias exclusivas: `ruby-openai`, `anthropic`,
  `pdf-reader`, sus dependencias transitivas y Poppler. Se auditó `pdf-reader`:
  sus únicos consumidores eran extracción IA y embeddings retirados.
- Retirado Compose IA de ejemplo; el proxy genérico y sus controles se conservan.
  No se eliminan servicios ni volúmenes
  reales. La configuración histórica continúa recuperable en Git.
- Flutter muestra el panel financiero y elimina transporte/pantallas de chat.
  Swift elimina el tab y las peticiones de chat, incluido el fetch automático
  durante el refresh del panel. Web/PWA y escritorio usan la UI financiera.

## Brandfetch

Configuración de instancia → General → Brandfetch incluye **Usar Brandfetch**,
mediante `DS::Toggle`, con envío automático y acceso de escritura solo para admin.
Persiste `Setting.external_logos_enabled`, apagado por defecto. Los logos se
controlan desde la instancia; `RELAY_EXTERNAL_LOGOS_ENABLED` deja de decidir esta
capacidad. Los overrides de las otras capacidades externas siguen funcionando.
El Client ID y la preferencia de resolución permanecen independientes.

Apagarlo impide generar y renderizar URLs externas, incluidas las almacenadas.
Conserva las URLs históricas y las credenciales, sin borrar logos personalizados.
Activarlo permite logos si hay Client ID; no activa bancos, mercados, Drive o IA.

## Datos y trabajos anteriores

No hay cambios de esquema, migraciones nuevas, eliminación de filas, tablas,
adjuntos, GlobalIDs o nombres STI. Las conversaciones y tool results permanecen
como lectores locales sin callbacks, broadcasts ni solicitudes a proveedores.
Los backups conservan su contrato y los originales de FamilyDocument y
AccountStatement; un original que el origen nunca guardó sigue identificado
como no disponible. El ledger de uso IA es histórico de instancia y conserva
la exclusión ya existente del backup familiar.

PdfImport conserva originales, resúmenes y datos ya extraídos, revisión,
reconciliación y publicación de filas existentes. Se rechazan nuevas peticiones
de extracción/importación documental IA. Statement Vault sigue admitiendo
documentos por su recorrido local. Las reglas históricas con acciones IA se
pueden leer y ejecutan cero modificaciones; no se ofrecen como acciones nuevas.

Jobs serializados antiguos mantienen consumidores mínimos:

- AssistantResponseJob marca failed la respuesta pendiente sin alterar texto.
- ProcessPdfJob detiene una extracción pendiente sin filas, conserva el original
  y registra el motivo local. No cancela una publicación con filas existentes.
- AutoCategorizeJob/AutoDetectMerchantsJob completan el contador de RuleRun con
  cero cambios; enriquecimiento, limpieza de caché y probes no envían ni borran.

No se purgan colas compartidas ni se revocan tokens. Preferencias IA históricas y
credenciales/variables antiguas no reactivan el producto. El predicado inmutable
`ai_features_enabled? == false` solo mantiene la declaración de indisponibilidad
para preferencias y clientes retenidos.

## Validación

Las ejecuciones iniciales detectaron referencias a rutas/partials
retirados y expectativas de IA en pruebas mixtas; se repararon conservando las
comprobaciones financieras, permisos, recuperación y adjuntos. No se añaden
omisiones para ocultar errores. La primera ejecución Flutter carecía de sus
dependencias; la segunda no montaba los tokens compartidos. Se repitió desde la
raíz del repositorio con las dependencias resueltas.

- Rails: ejecución final de 9.581 pruebas y 40.927 assertions sin fallos ni
  errores, con 45 omisiones preexistentes. Incluye la cobertura de rutas API
  retiradas con claves de ambos scopes.
- Ruby: 2.683 archivos sin infracciones. ERB: 739 archivos sin errores.
  Biome: 140 archivos sin infracciones. Brakeman: cero errores/advertencias
  activas, ocho exclusiones existentes. Los archivos añadidos después también
  pasan lint focalizado.
- Flutter: análisis sin incidencias y 170 pruebas correctas sobre copia limpia.
  Se descartan como evidencia los intentos sin caché/dependencias completas.
- Navegador: suite completa, 160 pruebas y 818 assertions sin fallos, errores ni
  omisiones. Además se conserva y valida la prueba de notificaciones push de
  salud del sistema: una prueba y 14 assertions, también correcta. Las 12 pruebas
  focalizadas previas verifican guardado del toggle, navegación de configuración,
  Bills responsive y wallets.
- Se corrigió el formulario anidado del aviso de precios de wallets mediante
  `DS::Link` POST/Turbo; guardar la selección de activos vuelve a funcionar.
- Rswag documental: 414 ejemplos, cero fallos, 89 pending documentales; OpenAPI
  regenerado sin chat, mensajes ni activación IA. Checklist API verificado y
  cobertura explícita de rutas retiradas con scopes read/read_write.
- Snapshot sintético de fase 0 → restore → export → restore: ambas recuperaciones
  verifican 21 registros, un adjunto, relaciones, referencia financiera y bytes
  originales. Rollback de base comprobado. La suite conserva recuperación de
  conversaciones/STI/tool results históricos.
- `db:migrate` ejecutado únicamente en `relay_test` de Docker, sin pendientes ni
  cambio de esquema. Esta fase no añade migraciones SQL.
- Compose estándar/source/TrueNAS válido; Helm lint/render correcto con
  dependencias en copia aislada. Imagen de producción y eager loading offline
  correctos con credenciales IA antiguas; OAuth y lectores históricos conservados.

Estado: implementada y validada localmente en Rails/web/Flutter; sin publicar.
El cierre de compilación del cliente Swift sigue pendiente del entorno nativo.
La validación de instalación TrueNAS y el backup privado no se ejecutan aquí.
La recuperación se ensaya con datos sintéticos y backups de la fase anterior.
Swift no dispone de compilador/Xcode en este entorno Windows; su build nativo
queda pendiente. No se publican aplicaciones móviles ni imágenes.

Evidencia local no versionada en `tmp`: `phase6-rails-green.log`,
`phase6-system-verified.log`, `phase6-system-push.log`, `phase6-system-repaired.log`,
`docker-test-results/phase6-hosting.png`, `phase6-checks-clean.log`,
`phase6-final-format.log`, `phase6-preserved-lint.log`, `phase6-wallet-lint.log`,
`phase6-flutter-verified2.log`, `phase6-openapi.log`, `phase6-last-lint.log`,
`phase6-recovery.log`, `docker-test-results/phase6-recovery.json`,
`phase6-helm.log`, `phase6-helm-render.yml`, `phase6-production-verified.log` y
`phase6-boot-verified.log`.

## Despliegue y reversión

Preparar backup de instalación y actualizar web/worker juntos. No se necesita
una migración SQL nueva para esta fase ni para el toggle: Settings utiliza la
tabla existente. Retirar variables y servicios IA de la configuración operativa
al desplegar; no borrar sus volúmenes como parte de esta entrega.

Reversión de código/configuración con esquema compatible. Los datos históricos
siguen disponibles. Volver al código anterior con credenciales podría reactivar
IA; no restaurar jobs ni variables automáticamente. Para revertir la política
de logos, revisar también el antiguo override del entorno.

La fase 7 no está incluida. Commit/push requiere confirmación del resultado.
