# Relay para Android

Cliente nativo en Kotlin, Jetpack Compose y Material 3 para Android 8.0 (API 26)
o posterior, con la paleta oscura «Relay» de la web. No usa WebView. Sustituye
progresivamente al cliente Flutter de [`mobile/`](../mobile/README.md), que se
conserva durante la transición; ambas apps pueden convivir (`app.relay.android`
y `am.sure.mobile`).

## Funciones de la primera versión

- **Acceso** con email y contraseña, código de verificación si la cuenta tiene
  MFA y Service Token opcional de Cloudflare Access.
- **Resumen:** patrimonio neto, activos y pasivos, cuentas agrupadas por tipo y
  últimos movimientos. Se puede actualizar deslizando hacia abajo.
- **Movimientos:** lista agrupada por día con búsqueda y paginación continua, y
  detalle de cada movimiento.
- **Cuenta:** saldo y movimientos de una cuenta.
- **Ajustes:** servidor, versión, búsqueda de actualizaciones, cierre de sesión
  (revoca los tokens en el servidor) y olvido local.

Por ahora es de solo lectura; la edición se hace en Relay web.

## Conexión y seguridad

Introduce el **origen HTTPS** del servidor, por ejemplo `https://relay.ejemplo.com`,
sin `/api` ni rutas. HTTP se rechaza: no hay excepciones TLS.

La app usa la API móvil de Relay: `POST /api/v1/auth/login` (registra el
dispositivo, con `otp_code` si hay MFA), `/auth/refresh` y `/auth/logout`.
Los tokens OAuth duran 30 días y se renuevan solos; si el servidor rechaza la
renovación, la sesión caduca y se vuelve al acceso.

Con Cloudflare Access, crea un Service Token y una política **Service Auth** para
la aplicación de Relay. La app envía `CF-Access-Client-Id` y
`CF-Access-Client-Secret` en todas las peticiones, incluida la descarga de
actualizaciones, y solo al servidor configurado. Nunca sigue redirecciones: si
Access pide iniciar sesión, la app muestra el error en lugar de mandar
credenciales a otra página.

Los tokens, el Service Token y el último resumen se guardan juntos, cifrados con
AES-GCM y una clave no exportable de Android Keystore, fuera de las copias de
seguridad. Cerrar sesión los borra. Si la sesión caduca, se conservan el servidor
y el Service Token para volver a entrar. La contraseña nunca se guarda.

## Actualizaciones

La [publicación local](../docs/hosting/local-releases.md) incluye la APK firmada
dentro de la imagen del servidor. Cuando TrueNAS actualiza Relay, la app la
detecta al abrirse y cada 15 minutos en primer plano
(`GET /api/v1/android/updates/latest`). Tras confirmar, descarga
`/api/v1/android/updates/<versionCode>/apk` con la sesión. Comprueba el tamaño,
el SHA-256, el paquete, que la versión sea mayor y que la firma coincida con la
instalada. Después abre el instalador de Android, que pide confirmación. La
primera vez Android también pide permiso para instalar apps desde Relay.

Para la primera instalación, inicia sesión en Relay web desde el navegador del
móvil y abre `https://<tu-servidor>/android/relay.apk`. Solo la descargan
usuarios con sesión. También se puede instalar con `adb install` desde la
carpeta de publicación (`tmp/releases/<commit>/image-context/relay-android/relay.apk`).

## Compilar

Requisitos: JDK 17 y Android SDK (platform 36, build-tools 35). Desde `android/`:

```powershell
./gradlew.bat assembleDebug testDebugUnitTest lintDebug
```

`local.properties` (no versionado) indica `sdk.dir`. La versión de desarrollo es
`0.1.0-dev` (1); el script de publicación asigna `RELAY_ANDROID_VERSION_CODE` y
`RELAY_ANDROID_VERSION_NAME`. Sin las variables `RELAY_ANDROID_KEYSTORE`,
`RELAY_ANDROID_STORE_PASSWORD`, `RELAY_ANDROID_KEY_ALIAS` y
`RELAY_ANDROID_KEY_PASSWORD`, `assembleRelease` produce una APK sin firmar. Nunca
se firma con la clave debug.

## Estructura

```text
auth/     Almacenamiento cifrado con Android Keystore
data/     Modelos de la API, transporte HTTPS y repositorio de sesión
ui/       Tema, componentes y pantallas Compose
updates/  Consulta, descarga verificada e instalación asistida
```

Las pruebas JVM (`RelayRepositoryTest`, `AndroidReleaseTest`) usan un servidor
HTTPS de prueba. Cubren login, MFA, Service Token, renovación, caducidad,
redirecciones, paginación, cierre de sesión y validación del manifiesto.
