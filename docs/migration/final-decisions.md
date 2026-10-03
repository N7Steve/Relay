# Formulario de decisiones para la fase final de Relay

Preparado el 3 de octubre de 2026. Estado: respondido por Steve el 3 de octubre de 2026.
Las respuestas de la última columna prevalecen sobre las opciones iniciales.
No incluyas contraseñas, tokens ni claves privadas en el inventario pendiente.

**Estado posterior, 4 de octubre de 2026:** Relay ya está desplegado y los datos
están importados y estables según Steve. La limpieza aplazada se inicia ahora con
la fase 0 del [plan de poda](pruning-plan.md). Google Drive y Brandfetch se usan;
la APK experimental se contempla como posible uso futuro. Las respuestas iniciales
de esta tabla son históricas: las decisiones y comprobaciones actuales se registran
en [fase 0](pruning-phase-0.md), sin ampliar autorización para despliegues o borrados.

La instancia será única y adaptable. No se propone compatibilidad con versiones
antiguas. Los lectores históricos de datos evitan perder los backups existentes.
Las respuestas autorizan publicar commits en main y preparar la versión de prueba.
La limpieza funcional se pospone hasta que Relay esté estable. No se ha autorizado
modificar la instalación Sure ni importar los datos ahora.

| Nº | Decisión | Opciones y recomendación | Respuesta |
| --- | --- | --- | --- |
| 1 | Instalación de origen | Indica dónde está Sure: servidor/TrueNAS/local, nombre del proyecto Compose y rutas de configuración/almacenamiento. Si no hay instalación, indica «ninguna». | TrueNAS SCALE 25.10.4; contenedor `sure-web-test`, imagen local `sure-staging-web-test`, puerto host 3001 → contenedor 3000. |
| 2 | Datos de Relay | **Recomendado si hay datos:** restaurar una copia completa de Sure en un ensayo aislado. Alternativa: empezar sin datos. | Exportación desde Sure e importación inicial en Relay cuando la versión de pruebas sea estable. Verificar previamente cobertura de exportación y adjuntos. |
| 3 | Destino | Indica servidor y ruta para Relay. **Recomendado:** mismo entorno de operación, con ensayo y volúmenes separados antes del corte. | TrueNAS; rutas y despliegue se concretan más adelante. |
| 4 | Acceso web | Mantener URL actual, URL nueva o solo red local. Indica URL exacta y proxy/TLS actual. **Recomendado:** conservar acceso mientras se valida la aplicación. | Puertos administrados desde TrueNAS; mantener separada la instancia Sure. |
| 5 | Distribución de la imagen | **Recomendado para una instancia:** build local en el destino. Alternativa: registro privado; indicar repositorio de imagen exacto. No hay imagen pública Relay seleccionada. | Mismo mecanismo que Sure mediante el repositorio Git; confirmado nombre de imagen local. Comandos de inventario pendientes para concretar el build. |
| 6 | Versionado | **Recomendado:** comenzar serie propia `0.1.0` para uso privado. Alternativa: conservar temporalmente el número heredado `0.7.6-alpha.1`. No se publicará ninguna etiqueta automáticamente. | Serie propia `0.1.0`. |
| 7 | Clientes mantenidos | **Recomendado:** web y PWA. Alternativas: añadir Flutter, escritorio Tauri, FinanceKit/Apple, o mantener todos. Seleccionar esto delimita después la retirada o adaptación de código nativo. | Conservar los clientes y funciones actuales de Sure; futura tecnología frontend se evaluará después. |
| 8 | Kubernetes/Helm | **Recomendado:** solo Docker Compose para la instancia única. Alternativa: mantener y migrar también el chart Helm. | Docker; sin publicación Helm en esta fase. |
| 9 | Telemetría y encuestas | **Recomendado:** desactivadas. Alternativa: proyecto PostHog propio con encuestas opcionales. La configuración heredada de Sure ya no viene incorporada. | Desactivar toda telemetría, encuestas y conexiones relacionadas heredadas de Sure. |
| 10 | Integraciones realmente utilizadas | Enumera proveedores bancarios/inversiones, OAuth/OIDC, Google Drive y clientes externos activos. Especialmente Sophtron y FinanceKit si se usan: sus identificadores externos requieren revisión antes de renombrarlos. | Conservar integración y configuración predeterminadas; limpieza posterior a estabilizar la instalación. |
| 11 | Publicación del repositorio | Mantener cambios locales o preparar commits y publicar `main` en origin. **Recomendado:** consolidar una vez elegidos alcance y versión. No publicar etiquetas históricas ni imágenes sin decidir su destino. | Preparar commits y subir cambios a `main`. |
| 12 | Operación final | **Recomendado:** ensayo primero, revisar resultados y acordar después una ventana de corte. Indica cuándo puedes revisar el ensayo y cuánto tiempo de parada es aceptable. | Publicar primero una versión para pruebas; importar datos cuando esté estable. |

Con estas respuestas se concretan configuración, callbacks, imagen y plan de
corte. La aprobación del corte se pide sobre ese resultado verificable, con
backup restaurado y plan de recuperación; rellenar el formulario no ejecuta el
cambio en producción.

## Elementos resueltos sin una decisión adicional

- Marca web/PWA, namespace Rails, tokens y tareas Relay sin aliases `sure:*` ni fallbacks `SURE_*`.
- Nuevos backups/importaciones escritos como `RelayImport`; datos históricos legibles.
- Changelog y contacto dirigidos al repositorio Relay; sin presentar releases Sure como propias.
- Telemetría y encuestas desactivadas, incluso con variables heredadas configuradas.
- Etiqueta de altas MFA «Relay», sin modificar secretos ni códigos ya existentes.
- Identidad informativa de proveedores y asistente actualizada a Relay; métricas `relay_version` sin campos duales.
- Versión 0.1.0 y marca Relay en web/PWA y clientes nativos, conservando sus contratos externos.
- Plantillas Docker con imagen, contraseña y clave explícitas; build desde Git disponible.
- Nuevas instalaciones con `relay_production`, `relay_user` y red Relay; no se renombra el origen.

## Referencias pendientes con motivo concreto

- Base, usuarios y volúmenes de Sure: inventariar el origen para la exportación;
  las plantillas Relay crean una instalación independiente.
- STI, tipos `SureImport`, GlobalIDs y claves de sesiones de importación históricas:
  identidad persistida, no soporte de clientes antiguos.
- `sure://`, `sureapp://`, aplicaciones OAuth, cabeceras FinanceKit y paquetes móviles:
  contratos externos conservados para los clientes actuales, sin capas de versiones antiguas.
- Sophtron `source: "Sure"` y `sure-family-*`, y usuario externo del asistente:
  namespaces de clientes externos; comprobar asociaciones
  antes de cambiarlo.
- Chart Helm archivado como referencia; distribución Docker elegida. Los clientes
  nativos se conservan; sus publicaciones en tiendas no se ejecutan en este bloque.
- Historia, licencias, archivos archivados y grabaciones VCR: conservar procedencia;
  no son configuración activa de Relay.
