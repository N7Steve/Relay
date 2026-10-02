# Pruebas locales en Docker desde Windows

Este entorno ejecuta Ruby, PostgreSQL, Redis, Node y, opcionalmente, Chromium
dentro de contenedores Linux. Windows solo necesita Docker Desktop y PowerShell.
No usa el bundle Ruby, PostgreSQL ni los servicios instalados en Windows.

## Instalación inicial

Instalar y arrancar [Docker Desktop para Windows](https://docs.docker.com/desktop/setup/install/windows-install/)
con contenedores Linux. La instalación por usuario permite usar el backend WSL 2
sin una instalación global con permisos de administrador, siempre que WSL y la
virtualización ya estén disponibles.

Docker administra su entorno Linux. No es necesario instalar Ruby o PostgreSQL
en Ubuntu ni trabajar desde una terminal Linux. En esta máquina se ha comprobado
Windows 11 Pro, aproximadamente 64 GB de RAM y WSL 2.6.3.

Después de instalarlo, abrir Docker Desktop y esperar a que el motor esté listo.
Seleccionar contenedores Linux. No activar la integración con Ubuntu para usar
estos comandos desde PowerShell. La primera comprobación puede hacerse con:

```powershell
docker version
docker compose version
```

Si la terminal no encuentra `docker`, abrir una nueva ventana de PowerShell.
El script también busca el ejecutable en las rutas habituales de instalación.

## Uso

Desde PowerShell, en la raíz del repositorio:

```powershell
# Suite de modelos, controladores e integración
.\bin\test-docker.ps1

# Un archivo concreto
.\bin\test-docker.ps1 unit test/models/account_test.rb

# RuboCop, ERB lint, Brakeman y lint JavaScript, sin autocorrecciones
.\bin\test-docker.ps1 checks

# Compilación de assets en el entorno de pruebas
.\bin\test-docker.ps1 build

# Pruebas de interfaz con Chromium dentro de Docker
.\bin\test-docker.ps1 system

# Un archivo concreto de interfaz
.\bin\test-docker.ps1 system test/system/confirm_dialog_test.rb

# Detener exclusivamente este entorno, conservando su volumen de pruebas
.\bin\test-docker.ps1 stop
```

La primera ejecución descarga imágenes e instala dependencias. Las siguientes
reutilizan las capas de dependencias; cambiar Gemfile.lock o package-lock.json
reconstruye la capa correspondiente. El comando comprueba siempre el código
actual mediante un build incremental antes de ejecutar la tarea.

Las capturas de errores de interfaz se guardan en `tmp/docker-test-results/`.
Los fallos de pruebas o comprobaciones devuelven un resultado de error; disponer
del entorno no significa que la suite actual esté verde.

## Rendimiento y aislamiento

El código se copia a la imagen con `COPY`; no se monta el repositorio de Windows
como carpeta de trabajo Linux. Ruby, las gems, node_modules y la base de datos
trabajan en el almacenamiento Linux de Docker. Solo las capturas se escriben en
una carpeta compartida, con un volumen de operaciones pequeño.

Esto evita que cada carga de Ruby cruce la frontera entre los sistemas de
archivos Windows y Linux. Docker explica esa diferencia de rendimiento en sus
[recomendaciones para WSL 2](https://docs.docker.com/desktop/features/wsl/best-practices/).

El proyecto Compose se llama `sure-tests`. PostgreSQL y Redis no publican puertos
en Windows. No interfieren con el PostgreSQL local ni acceden a TrueNAS. El
script rechaza motores Docker remotos y ejecuta únicamente contra sus servicios
`db` y `redis`. Los valores de acceso incluidos son exclusivos de este entorno.

Compose usa un archivo de variables vacío explícito. La imagen excluye `.env*`,
claves de Rails, almacenamiento y otros datos locales mediante `.dockerignore`.
No añadir credenciales reales ni montar volúmenes de producción.

Las tareas de pruebas cargan `db/schema.rb` sobre su base `sure_test` antes de
ejecutar; reemplazan los datos de esa base de pruebas. No ejecutan migraciones
históricas, despliegues, el servidor de desarrollo ni workers programados.
Las pruebas de interfaz arrancan su servidor temporal mediante Capybara.

La tarea `build` valida assets en test. Para comprobar la construcción de la
imagen de producción se mantiene el Dockerfile y workflow de publicación
existentes; esta tarea no certifica ese build de producción.

## Mantenimiento y límites

- Mantener Ruby alineado con `.ruby-version`; Node usa la misma versión mayor que CI.
- PostgreSQL 16 sigue el devcontainer existente; Redis 7.4 se ejecuta sin persistencia.
- Chromium se descarga solo para la tarea `system`. Su imagen sigue `latest`,
  como el devcontainer; se puede fijar una versión si se necesita reproducibilidad.
- Las pruebas locales se ejecutan sin paralelización para facilitar diagnóstico.
- No reutilizar este Compose como instalación de producción.
- Este entorno permite ejecutar en Linux las comprobaciones antes bloqueadas por
  el bundle de Windows. La restricción del inventario sigue aplicando al bundle
  nativo local; no impide ejecutar las tareas en este entorno Docker aislado.

## Estado de verificación

El 2 de octubre de 2026 se comprobaron Docker Compose, la construcción de la
imagen, los entrypoints y su aislamiento respecto a la app local y a TrueNAS.
Las fuentes copiadas a la imagen normalizan CRLF a LF para reproducir un checkout
Linux y evitar errores de las herramientas al leer archivos de Windows.
Cada ejecución de pruebas compila los assets, también sobre una imagen limpia.

Después de corregir las regresiones funcionales y adaptar las expectativas a
las funcionalidades preservadas del fork, terminaron correctamente:

- Suite completa Rails: **10.777 pruebas, 45.639 aserciones, 0 fallos, 0 errores**.
  Mantiene 33 omisiones existentes o condicionadas por la configuración del
  entorno; no se añadieron omisiones para ocultar fallos.
- Suite completa de navegador: **189 pruebas, 968 aserciones, 0 fallos,
  0 errores y 0 omisiones**, con Chromium remoto.
- RuboCop: 2.915 archivos sin infracciones.
- ERB lint: 779 plantillas sin errores.
- Biome: 142 archivos sin errores de lint; el JavaScript modificado también pasó
  la comprobación de formato.
- Brakeman: 0 errores y 0 avisos activos. Conserva las 8 exclusiones anteriores;
  no se añadieron exclusiones para estas correcciones.
- Compilación de assets y `git diff --check` correctos.

La aplicación local y su arranque desde `.bat` se documentan y verifican en
[la guía de aplicación local](docker-local-app.md). Estas comprobaciones no
sustituyen el workflow de construcción de la imagen de producción.
