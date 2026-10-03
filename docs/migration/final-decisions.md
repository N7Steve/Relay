# Formulario de decisiones para la fase final de Relay

Preparado el 3 de octubre de 2026. Estado: pendiente de respuestas.
Puedes responder aquí o enviar los números y tus elecciones en el chat.
No incluyas contraseñas, tokens ni claves privadas.

La instancia será única y adaptable. No se propone compatibilidad con versiones
antiguas. Los lectores históricos de datos evitan perder los backups existentes.
Las recomendaciones siguientes no son decisiones tomadas ni autorización de
publicación, borrado de clientes o migración de una instalación.

| Nº | Decisión | Opciones y recomendación | Respuesta |
| --- | --- | --- | --- |
| 1 | Instalación de origen | Indica dónde está Sure: servidor/TrueNAS/local, nombre del proyecto Compose y rutas de configuración/almacenamiento. Si no hay instalación, indica «ninguna». | Pendiente |
| 2 | Datos de Relay | **Recomendado si hay datos:** restaurar una copia completa de Sure en un ensayo aislado. Alternativa: empezar sin datos. | Pendiente |
| 3 | Destino | Indica servidor y ruta para Relay. **Recomendado:** mismo entorno de operación, con ensayo y volúmenes separados antes del corte. | Pendiente |
| 4 | Acceso web | Mantener URL actual, URL nueva o solo red local. Indica URL exacta y proxy/TLS actual. **Recomendado:** conservar acceso mientras se valida la aplicación. | Pendiente |
| 5 | Distribución de la imagen | **Recomendado para una instancia:** build local en el destino. Alternativa: registro privado; indicar repositorio de imagen exacto. No hay imagen pública Relay seleccionada. | Pendiente |
| 6 | Versionado | **Recomendado:** comenzar serie propia `0.1.0` para uso privado. Alternativa: conservar temporalmente el número heredado `0.7.6-alpha.1`. No se publicará ninguna etiqueta automáticamente. | Pendiente |
| 7 | Clientes mantenidos | **Recomendado:** web y PWA. Alternativas: añadir Flutter, escritorio Tauri, FinanceKit/Apple, o mantener todos. Seleccionar esto delimita después la retirada o adaptación de código nativo. | Pendiente |
| 8 | Kubernetes/Helm | **Recomendado:** solo Docker Compose para la instancia única. Alternativa: mantener y migrar también el chart Helm. | Pendiente |
| 9 | Telemetría y encuestas | **Recomendado:** desactivadas. Alternativa: proyecto PostHog propio con encuestas opcionales. La configuración heredada de Sure ya no viene incorporada. | Pendiente |
| 10 | Integraciones realmente utilizadas | Enumera proveedores bancarios/inversiones, OAuth/OIDC, Google Drive y clientes externos activos. Especialmente Sophtron y FinanceKit si se usan: sus identificadores externos requieren revisión antes de renombrarlos. | Pendiente |
| 11 | Publicación del repositorio | Mantener cambios locales o preparar commits y publicar `main` en origin. **Recomendado:** consolidar una vez elegidos alcance y versión. No publicar etiquetas históricas ni imágenes sin decidir su destino. | Pendiente |
| 12 | Operación final | **Recomendado:** ensayo primero, revisar resultados y acordar después una ventana de corte. Indica cuándo puedes revisar el ensayo y cuánto tiempo de parada es aceptable. | Pendiente |

Con estas respuestas se concretan configuración, callbacks, imagen y plan de
corte. La aprobación del corte se pide sobre ese resultado verificable, con
backup restaurado y plan de recuperación; rellenar el formulario no ejecuta el
cambio en producción.

## Elementos resueltos sin una decisión adicional

- Marca web/PWA, namespace Rails, tokens y tareas Relay sin aliases `sure:*` ni fallbacks `SURE_*`.
- Nuevos backups/importaciones escritos como `RelayImport`; datos históricos legibles.
- Changelog y contacto dirigidos al repositorio Relay; sin presentar releases Sure como propias.
- Feedback sin destino externo heredado; configuración explícita si se desea usarlo.
- Etiqueta de altas MFA «Relay», sin modificar secretos ni códigos ya existentes.
- Identidad informativa de proveedores y asistente actualizada a Relay; métricas `relay_version` sin campos duales.
- Plantillas Docker con imagen Relay explícita; guía de instalación y runbook propios.

## Referencias pendientes con motivo concreto

- `sure_production`, usuarios/redes/volúmenes heredados: identificar datos existentes
  antes de renombrar o cambiar el proyecto Compose.
- STI, tipos `SureImport`, GlobalIDs y claves de sesiones de importación históricas:
  identidad persistida, no soporte de clientes antiguos.
- `sure://`, `sureapp://`, aplicaciones OAuth, cabeceras FinanceKit y paquetes móviles:
  depende del alcance de clientes y registros externos elegidos.
- Sophtron `source: "Sure"` y `sure-family-*`, y usuario externo del asistente:
  namespaces de clientes externos; comprobar asociaciones
  antes de cambiarlo.
- Chart Helm y distribución nativa: a resolver según las respuestas 7 y 8.
- Historia, licencias, archivos archivados y grabaciones VCR: conservar procedencia;
  no son configuración activa de Relay.
