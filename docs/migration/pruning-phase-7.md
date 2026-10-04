# Poda fase 7 — Retirada de conectores externos de cuentas

## Selección confirmada por Steve

Selección del 4 de octubre de 2026, después de desplegar la fase 6 y confirmar
que Relay funciona correctamente. Relay mantiene su orientación self-hosted first.

- No utiliza conectores de bancos, brokers, exchanges ni wallets.
- **Conservar Enable Banking**, aunque no se utilice actualmente, como opción
  futura. Conservar su recorrido funcional completo; no solo clases o una opción
  de configuración sin implementación.
- **Retirar todos los demás conectores externos de cuentas**, con alcance
  completo, incluidos sus consumidores y dependencias exclusivas.
- Steve confirma que no tiene cuentas sincronizadas ni datos de esos conectores
  que necesite conservar. No se prevé convertir cuentas enlazadas a manuales.

Esta es una decisión de producto ya tomada; el agente que continúe no necesita
repetir el cuestionario ni pedir otra selección de conectores. La ausencia de
datos es información aportada por Steve, no una inspección de su base privada.

## Estado y autorización

**Implementación completada y validada localmente en `main`.** Ejecutada por petición
de Steve con el alcance aprobado. El registro inferior recoge los resultados
reales; no implica commit/push ni despliegue en TrueNAS.

Trabajar directamente en `main`, inspeccionar el árbol y sincronizar mediante
fast-forward, preservando cambios existentes. No crear ramas, worktrees ni PR.
Commit/push requiere confirmación conforme a [AGENTS.md](../../AGENTS.md).
No operar sobre TrueNAS ni sobre bases/colas/servicios reales por inferencia.

## Límites que deben preservarse

- Enable Banking sigue disponible, con autorización, callbacks, cuentas,
  sincronización, configuración, UI, API y pruebas que necesite.
- No retirar infraestructura compartida que siga usando Enable Banking o el
  núcleo financiero: tenancy, permisos, autenticación, API keys/OAuth, importaciones,
  backups, cuentas manuales, movimientos, transferencias e inversiones.
- Brandfetch y Google Drive se conservan y quedan fuera de esta fase.
- Cotizaciones y divisas no son conectores de cuentas: su selección corresponde
  a la fase 9A. No eliminar sus proveedores por compartir nombre o dependencia
  con un conector de cuentas que se retire.
- El plan mantiene FinanceKit mientras se conserve el cliente Apple que lo usa.
  Auditar esa dependencia y respetar la decisión previa sobre clientes nativos;
  no retirar el cliente, FinanceKit ni contratos compartidos por inferencia.
- Bills/recurrencias pertenecen a la fase 8; no ampliar esta entrega a ese dominio.
- No borrar tablas, filas, adjuntos ni migraciones históricas: la disposición
  persistente del esquema corresponde a la fase 10. Mantener lectores de backups
  y nombres STI/GlobalID necesarios aunque el conector deje de estar en runtime.

Si la auditoría encuentra referencias o datos inesperados, registrarlos y resolver
su compatibilidad antes de eliminar código. La declaración de que no hay datos
no autoriza una purga ni sustituye las comprobaciones de recuperación.

## Arranque para el siguiente agente

1. Leer arquitectura, guías relevantes de proveedores/testing/desarrollo,
   [mapa de preservación](../../FORK_CUSTOMIZATIONS.md),
   [contratos de backup](pruning-backup-contracts.md) y
   [registro de fase 6](pruning-phase-6.md). Confirmar HEAD y estado reales:
   Steve informa de despliegue funcional, pero no se ha inspeccionado la instalación.
   La compilación Swift pendiente en fase 6 no debe darse por verificada.
2. Inventariar conectores y consumidores reales antes de borrar: clientes/adapters,
   concerns, items/accounts, processors, jobs/cron, webhooks, rutas, UI/locales,
   configuración/entorno, dependencias, factorías/reflexión y backups. Identificar
   explícitamente qué es exclusivo y qué comparte Enable Banking u otro módulo
   conservado. Registrar aquí la lista concreta y los lotes de ejecución.
3. Ejecutar la retirada completa en lotes autocontenidos por dependencia técnica.
   Retirar altas, sync, callbacks, configuración y consumidores del lote;
   resolver trabajos serializados antiguos sin purgar colas compartidas ni lanzar
   callbacks `destroy` como forma genérica de desconexión.
4. Mantener las cuentas/manuales e importaciones soportadas y los lectores
   históricos necesarios. No cambiar cálculos financieros como efecto secundario.
5. Validar cada lote antes de avanzar: arranque/eager loading, assets/imagen,
   pruebas focalizadas y suite Rails completa, sistemas/clientes afectados,
   Ruby/ERB/Biome/Brakeman y recuperación de un backup anterior con comparación
   financiera y originales. Si cambia API v1, cubrir comportamiento con Minitest,
   mantener rswag documental y regenerar OpenAPI.
6. Actualizar este registro, el plan y el mapa de preservación con resultados,
   evidencia, límites y reversión. Presentar el resultado concreto antes de
   commit/push; no avanzar automáticamente a la fase 8.

## Criterio de cierre

Enable Banking sigue siendo una opción completa. Los otros conectores externos
de cuentas ya no pueden activarse, sincronizar ni enviar datos desde rutas,
webhooks, jobs o callbacks. Relay sigue siendo utilizable con cuentas manuales,
importaciones y el núcleo financiero exacto. Los backups anteriores soportados
siguen restaurándose sin referencias rotas ni pérdida de originales.

La validación del despliegue real se registra aparte cuando se realice. No
presentar una reversión de código como reconexión automática de cuentas o
recuperación de datos eliminados.

## Inventario de implementación

HEAD inicial: `b6ad2de31f81224cd054c59105d3790c45a5f325`; `main` sincronizado con `origin/main`.

Conectores retirados: akahu, binance, brex, coinbase, coinspot, coinstats, fio, ibkr, indexa_capital, kraken, lunchflow, mercury, monobank, onchain_wallet, plaid, questrade, redbark, simplefin, snaptrade, sophtron, trade_republic, trading212, up, wise. Plaid EU comparte la retirada de Plaid.

Lotes técnicos: (1) lectores Item/Account y consumidores de jobs antiguos; (2) retirada de transportes/adapters/importers, rutas y callbacks; (3) consumidores compartidos de cuentas/configuración/UI y clientes; (4) pruebas, recuperación, imagen/assets y documentación.

Los 48 nombres Item/Account se conservan como persistencia histórica con relaciones, cifrado y adjuntos originales; sin Syncable, clientes, callbacks remotos ni registro de adapters. No se modifica el esquema. Enable Banking/FinanceKit, BinancePublic y demás mercado/FX, Brandfetch, Drive y Bills se conservan.

## Resultado concreto

- Retirados clientes, adapters, importers/processors, concerns de conexión,
  controladores/rutas/webhooks, scripts de conexión, paneles, opciones, locales
  exclusivos, configuración de entorno y tareas exclusivas de los conectores
  enumerados. Plaid y la dependencia directa de websocket-driver salen de Gemfile;
  websocket-driver permanece como dependencia de Action Cable. HTTParty se
  conserva porque Enable Banking lo utiliza.
- Los 18 jobs serializados específicos y el antiguo job horario cancelan sin
  llamadas externas. Se retira únicamente su cron `sync_hourly`; no se purgan
  colas compartidas. Los Sync antiguos de conectores quedan stale y cancelan
  descendientes pendientes; DestroyJob preserva sus filas.
- Se mantienen cifrado, relaciones, adjuntos originales y nombres históricos
  Item/Account, sin callbacks remotos. El reset financiero explícitamente
  confirmado sigue contemplando esas asociaciones y su historial, con tenancy.
- Las cuentas históricas permanecen visibles sin convertirlas a manuales.
  Se preservan lectores locales de balances IBKR y rentabilidad Indexa,
  metadata pending/FX, reglas sobre nombres y traducciones requeridas por
  migraciones históricas. Enable Banking conserva la preferencia de pendientes;
  las antiguas variables de SimpleFIN/Plaid no controlan esa preferencia.
- La API de estado expone Enable Banking/FinanceKit, con pruebas de ambos
  scopes de lectura, aislamiento de familia y secretos excluidos. OpenAPI
  regenerado; no cambia el contrato de autenticación de clientes nativos.

## Evidencia local verificada

- Ruby: 2.018 archivos, sin infracciones. ERB: sin errores. Biome: 135 archivos,
  sin infracciones. Brakeman: sin advertencias nuevas; se conserva el archivo
  de exclusiones existente.
- Rails completo: 6.692 pruebas, 30.248 aserciones, 0 fallos, 0 errores y
  38 skips. Ejecución definitiva independiente, tras resolver los resultados
  intermedios; `tmp/phase7-rails-verified.log`.
- Navegador completo: 154 pruebas, 814 aserciones, 0 fallos, 0 errores y
  0 skips; `tmp/phase7-browser-verified.log`. Incluye catálogo, conexión
  Enable Banking, Wallet y recorridos compartidos.
- Imagen `relay-pruning-phase7:production` construida con assets. Eager loading
  de producción sin red correcto, incluso con variables antiguas de conectores;
  EB/FinanceKit, mercado y lectores históricos presentes, transportes y adapters
  retirados ausentes.
- Compose example/source/TrueNAS/folder validado con valores ficticios y
  `config --quiet`, sin arrancar servicios de instalación. Helm lint y render
  correctos en copia aislada con las dependencias previamente disponibles.
- OpenAPI: 414 ejemplos documentales, 0 fallos, 89 pendientes documentales.
  Comprobador de consistencia API correcto. El comportamiento se verifica con
  Minitest, no con aserciones de rswag.
- Recuperación usando la imagen de fase 6 `e74eaa68702e`: snapshot anterior →
  importación en fase 7 → exportación ZIP → segunda importación. Ambas lecturas
  verifican 146 registros, relaciones, 10 cuentas y un original binario, con
  comparación de balances, movimientos, holdings y bytes. Ambas dan `matched`.
  Es un conjunto sintético: se reponen sus originales dentro del ensayo y se
  normalizan dos etiquetas obsoletas de fixtures antes de generar el snapshot.
  El ensayo conserva las advertencias de documentos sin original en la fuente y
  una referencia de importación histórica ausente; no inventa archivos ni cuentas.
  Las operaciones SQL se revierten; no se usa el backup privado de Steve.

Los logs intermedios que fallaron o se solaparon no cuentan como evidencia verde.
Las pruebas de navegador se ejecutan en otro proyecto Docker, con PostgreSQL y
Redis propios, sin compartir base/colas con la suite Rails. Los servicios de
ese proyecto se detienen al finalizar; sus volúmenes de prueba se conservan.

Logs adicionales: `tmp/phase7-quality.log`, `tmp/phase7-final-ruby.log`,
`tmp/phase7-production-verified.log`, `tmp/phase7-production-ready.log`,
`tmp/phase7-openapi.log`, `tmp/phase7-api-consistency.log`,
`tmp/phase7-helm.log`, `tmp/phase7-prior-export.log` y `tmp/phase7-restore.log`.
Comparación recuperada: `tmp/docker-test-results/phase7-recovery.json`.
Captura del catálogo: `tmp/docker-test-results/phase7-provider-catalog.png`.
Estos artefactos locales de `tmp/` no forman parte del commit.

## Publicación, límites y reversión

No se han creado ramas/worktrees/PR, ni commit/push. No se opera sobre TrueNAS,
colas, cuentas ni datos reales. No hay migraciones nuevas ni cambios de esquema;
su disposición sigue pendiente de la fase 10. No se avanza a la fase 8.

Los clientes móviles permanecen y no incorporan opciones/código específico de
los conectores retirados. La compilación Swift sigue pendiente de un entorno
con Xcode, igual que en fase 6; no se publica ninguna aplicación nativa.

El despliegue deberá actualizar web y worker juntos, conservar claves de cifrado,
originales y backup, y retirar variables operativas obsoletas. La reversión de
código sigue siendo posible con el esquema conservado, pero no reconecta cuentas
ni recupera originales que ya faltaban en el backup fuente. No restaurar jobs,
colas ni credenciales retiradas automáticamente al revertir.
