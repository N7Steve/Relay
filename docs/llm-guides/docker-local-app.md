# Aplicación local en Windows con Docker

Con Docker Desktop arrancado, hacer doble clic en `iniciar-app.bat`, en la raíz
del repositorio. Construye el código actual, prepara la base local, compila los
assets y arranca Rails y Sidekiq. Cuando está listo, abre Chrome en
**http://localhost:3002**. La primera ejecución tarda más por las dependencias.

En una instalación vacía, crear el usuario desde la pantalla inicial. Son datos
locales: no se importa información de TrueNAS ni se cargan credenciales de los
archivos `.env` del repositorio. No conectar bancos reales para probar cambios.

`detener-app.bat` detiene los contenedores sin borrar usuarios, movimientos ni
archivos subidos. Cerrar Chrome o la ventana del `.bat` no detiene la aplicación.
Después de cambiar código, ejecutar de nuevo `iniciar-app.bat`: reconstruye la
imagen y recrea los procesos que necesitan la versión nueva.

También se puede usar PowerShell:

```powershell
.\bin\app-docker.ps1 start
.\bin\app-docker.ps1 start -NoBrowser
.\bin\app-docker.ps1 logs
.\bin\app-docker.ps1 stop
```

El proyecto Compose se llama `relay-local`, con base `relay_local` y volúmenes
propios para PostgreSQL, Redis y archivos. Solo publica el puerto 3002 en
`127.0.0.1`; no expone el servidor a la red doméstica. Si otra aplicación ocupa
ese puerto, detenerla antes de arrancar este entorno.

Las pruebas usan el proyecto y base separados `relay-tests` / `relay_test`.
Ejecutar pruebas no borra los datos de la aplicación local. Ambos entornos usan
contenedores Linux y copian el código a la imagen para evitar el coste de montar
el árbol de Windows en Linux. No requieren Ruby, Node ni PostgreSQL en Windows.

El arranque ejecuta `db:prepare` exclusivamente en esta base de desarrollo:
crea el esquema inicial y aplica las migraciones nuevas al actualizar el código.
El entrypoint comprueba entorno, host y nombre de base antes de hacerlo. No
ejecutar `down --volumes` si se quieren conservar los datos locales.

Este entorno es de desarrollo; la compilación de assets no certifica la imagen
de producción. Los correos se previsualizan con Letter Opener y no se configuran
proveedores reales, IA ni exportaciones a servicios externos automáticamente.

## Importaciones grandes

Las importaciones de backups NDJSON admiten hasta 500 MB por defecto. Para
archivos mayores, añadir `RELAY_IMPORT_MAX_NDJSON_SIZE_MB` con el límite deseado
en MB al bloque `local-environment` de `compose.local.yml` y volver a ejecutar
`iniciar-app.bat`. `RELAY_IMPORT_MAX_ROWS` controla por separado el límite de
registros, que sigue siendo 100.000 por importación. Estos ajustes se aplican
también al worker. No es necesario modificar el archivo NDJSON ni copiarlo
manualmente al contenedor.

Los nombres `SURE_IMPORT_MAX_*` siguen funcionando cuando el equivalente
`RELAY_IMPORT_MAX_*` no está definido. Relay tiene prioridad incluso si su valor
es vacío o no positivo: se usa entonces el valor predeterminado, sin recuperar
el legacy. Consultar [la transición de configuración](relay-compatibility.md).

## Verificación histórica del entorno Sure

El 2 de octubre de 2026 se ejecutó `iniciar-app.bat` desde Windows, usando
Windows PowerShell y Docker Desktop. Rails, Sidekiq, PostgreSQL y Redis arrancaron
correctamente; `/up` devolvió 200 y la entrada inicial llevó a `/registration/new`
con respuesta 200. El arranque abrió Chrome y se comprobó la reconstrucción
y recreación de la app manteniendo los volúmenes locales.

Relay usa ahora su propio proyecto, base y puerto 3002. Esta verificación
histórica no certifica el arranque de Relay ni una migración de datos.
