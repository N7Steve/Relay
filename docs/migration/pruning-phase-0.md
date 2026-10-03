# Fase 0 — Referencia inicial de Relay

Fecha: 4 de octubre de 2026. Alcance autorizado: fase 0 del
[plan de poda](pruning-plan.md). No se elimina ni suspende funcionalidad.
Estado: **completada como referencia de código, uso declarado y recuperación
aislada**. Sin certificación adicional de la base ni del backup privado del NAS.

## Referencias y despliegue

| Referencia | Estado/evidencia |
| --- | --- |
| `main` local y `origin/main` | `1e279bd8f6fe05d295c074180efccbcd59195ad5`, sincronizados al comenzar |
| TrueNAS web | Mismo SHA; salida de lectura facilitada por Steve |
| TrueNAS worker | Mismo SHA; salida de lectura facilitada por Steve |
| Instalación | `/mnt/AppsPool/relay`, proyecto `ix-relay`; check del updater correcto según salida facilitada |
| Datos Sure | Steve confirma importación completa, correcta y estable |
| Recuperación real | Steve confirma backup local; no se ha leído ese archivo ni ensayado su restauración en esta fase |

El `--check` del updater valida instalación y calcula un destino; no compara el
SHA ejecutado. Se obtuvo por separado `BUILD_COMMIT_SHA` de web y worker mediante
lectura, y ambos coinciden con esta base. No se ejecutó actualización ni se accedió
directamente al NAS desde este trabajo.

## Inventario confirmado por el usuario

| Área | Uso/decisión de referencia | Consecuencia para la poda |
| --- | --- | --- |
| Google Drive | Utilizado; implementación propia | Conservar OAuth por usuario, exports, programación, destinos y reintentos |
| Brandfetch | Utilizado | Conservar resolución de logos; no aplicar la recomendación inicial de retirarlo |
| Web | Superficie actual | Núcleo soportado y protegido |
| APK experimental | Posible uso futuro, aún poco desarrollada | Conservar por ahora; su abandono requiere selección posterior |
| Otros clientes | No utilizados actualmente | Candidatos a selección posterior, sin eliminación aprobada |
| Bancos, brokers y otros conectores | No utilizados según respuesta sobre el resto de áreas | Inventariar datos históricos antes de retirarlos; no convertir cuentas por suposición |
| Cotizaciones/divisas externas | No utilizadas según respuesta | Mantener datos históricos y cálculo de inversiones/multimoneda |
| IA y MCP | No utilizados | Candidatos a retirada en sus fases |
| Bills, presupuestos y Goals | No utilizados | Bills duplicado candidato; presupuestos/Goals requieren decisión propia |
| Login externo | No utilizado | Candidato a retirada conservando acceso local y OAuth de clientes/Drive |
| Almacenamiento configurado | No inventariado directamente | No retirar drivers ni cambiar originales sin comprobarlo |

«No utilizado» no equivale a ausencia de registros ni a aprobación del borrado.
La conservación de Drive/Brandfetch no implica permitir todas las conexiones
externas. Ambas tendrán capacidades explícitas al separar autosync bancario y
cálculos locales en fase 2.

## Referencia financiera y de recuperación

Hay dos referencias distintas:

1. **Instalación real:** estado estable confirmado por Steve y su backup local.
   Antes de convertir cuentas o retirar modelos con datos, extraer del backup en
   un entorno privado las cuentas/tratamientos, saldos por fecha, holdings,
   transferencias, Agenda, originales y parámetros de informes. No se han
   inventado aquí conteos de esa instalación. Para la primera retirada se dispone
   del inventario de uso; el inventario de datos es requisito por módulo afectado.
2. **Ensayo reproducible:** dataset sintético creado por
   `script/pruning/phase_zero_rehearsal.rb`, con valores y fechas fijos. Incluye
   cuentas included/tracking, balances, inversión/holding, transferencia,
   Agenda confirmada/rechazada y un original PDF de fixture.

El ensayo exporta → restaura → reexporta → restaura y exige igualdad de valores
financieros, vínculos comprobados por el restorer y bytes del adjunto. Cada
restauración verifica **21 registros y 1 original**, con estado `matched`.
Las filas de ensayo vuelven al estado anterior mediante rollback comprobado;
Active Storage es efímero en el runner. No se arrancan workers ni se llaman
proveedores. Es evidencia de recuperación del código actual, no una certificación
del backup real o del servidor completo.

Los snapshots y referencia quedan fuera de Git:

- `tmp/docker-test-results/pruning-source.ndjson`.
- `tmp/docker-test-results/pruning-reexport.ndjson`.
- `tmp/docker-test-results/pruning-rehearsal.json`.
- Copia inicial conservada en `tmp/pruning-phase-0/reference/`, junto a hash
  SHA-256 de los snapshots; futuras ejecuciones no escriben en esa carpeta.
- Logs de esta fase en `tmp/pruning-phase-0/`.

Para futuras comparaciones, copiar los snapshots iniciales a un directorio
privado conservado antes de repetir el ensayo, que sobrescribe esos nombres.
La referencia financiera real debe conservarse junto al backup del usuario;
los archivos sintéticos no sustituyen esa referencia.

## Métricas iniciales

Medidas con `script/pruning/measure.ps1`; JSON fuera de Git en
`tmp/pruning-phase-0/source-metrics.json`.

| Área | Archivos versionados | Líneas de texto seleccionadas |
| --- | ---: | ---: |
| `app/` | 2.338 | 244.490 |
| Proveedores dentro de `app/models/provider/` | 117 | 24.061 |
| Controllers | 219 | 33.147 |
| Jobs | 63 | 2.793 |
| `test/` | 1.135 | 201.513 |
| Flutter `mobile/` | 235 | 28.011 |
| Tauri `desktop/` | 55 | 2.402 |
| Apple `bitrig/` | 22 | 1.557 |

Los grupos se solapan. Las líneas incluyen comentarios/blancos y solo extensiones
declaradas; no representan líneas de lógica ni código exclusivo de una función.
Las cassettes y ciertos recursos no entran en el conteo de líneas.

- Gemfile: **99 declaraciones**, incluidas condiciones y grupos development/test.
- Gemfile.lock: **323 specs**, incluidas dependencias transitivas.
- npm raíz: **0 dependencias runtime y 1 de desarrollo**.
- **27 adapters** de proveedores y **6 archivos de workflow activos**.
- Schedule estático: **16 entradas**, además del autosync dinámico posible.
  No se ha leído el registro cron real de Redis en TrueNAS.
- Routes cargadas en test: **1.029**. No es el conteo de rutas habilitadas en
  producción: incluye condiciones del entorno y puertas de test.
- Imagen del runner de ensayo: **2.205.915.655 bytes**, ID
  `sha256:59abdd0bbcabfec64159c37394d6086267b6d5e13d9389586ea38786210be245`.
  Es imagen de pruebas, no tamaño de la imagen productiva del NAS.
- Duración de CI remoto y tamaño de imagen instalada: no medidos en esta fase.
  No se usan datos de una imagen antigua como métrica de la revisión actual.

## Validación y límites

- Suite de backup/importación: **229 tests, 1.290 aserciones**, sin fallos,
  errores ni omisiones; 19,93 segundos de ejecución de tests, sin build/arranque.
- Doble restauración sintética y comparación financiera/bytes: correcta.
- Núcleo financiero focalizado: **238 tests, 721 aserciones**, sin fallos,
  errores ni omisiones; 8,60 segundos de tests. Cubre cuentas, holdings,
  transferencias/matching, IncomeStatement, BalanceSheet, Agenda y wealth forecast.
- RuboCop del script de ensayo: 1 archivo, sin infracciones.
- PowerShell de métricas ejecutado; conteos y JSON inspeccionados.
- El arranque del entorno estándar `relay-tests` falló por autenticación de su
  volumen PostgreSQL preexistente. No se modificaron contraseña ni volumen.
  El ensayo se ejecutó en **`relay-pruning-phase0`**, con DB/Redis independientes.
- Las tareas de tests cargan el schema actual y compilan assets en su base aislada.
  No ejecutan migraciones históricas ni acceden a la instalación desplegada.
- Antes de publicar, por petición de Steve, suite completa Rails sobre esta base:
  **10.871 tests, 46.256 aserciones, 0 fallos, 0 errores y 46 omisiones**,
  627,79 segundos. Ejecución aislada en `relay-pruning-validation`.
  No se añaden skips ni se cambia producto para esta publicación.
  Navegador completo, build productivo de fase 0 y CI remoto no se ejecutan aquí.

Total de esta fase: **467 tests, 2.011 aserciones**, sin fallos, errores ni
omisiones, más las dos restauraciones sintéticas. Se detienen únicamente los
servicios de `relay-pruning-phase0`, conservando el volumen de pruebas.
Una futura retirada deberá usar pruebas propias del área, además de esta referencia.

## Resultado y continuación

Esta fase mantiene idéntico el comportamiento de Relay. Consolida los estados
históricos de migración, protege el uso declarado de Drive/Brandfetch, fija SHA
local/desplegado y prepara evidencia repetible de recuperación.

La fase 1 puede diseñarse sobre esta base sin operar TrueNAS. Antes de eliminar
un modelo concreto debe comprobarse su presencia en backups/datos reales;
antes de alterar almacenamiento, obtener su configuración efectiva.
No son requisitos para volver a preguntar por permisos generales ni para
repetir la validación de despliegue ya facilitada.

Cambios de esta entrega: documentos de migración/preservación y herramientas de
referencia bajo `script/pruning/`. Sin cambios de app, API, esquema, dependencias
o configuración productiva. Reversión: retirar esta entrega documental y sus
herramientas; los datos reales no necesitan reversión.
