# Herramientas de referencia para la poda

Estas herramientas no cambian el producto ni operan TrueNAS. Los resultados se
guardan bajo `tmp/`, fuera de Git. No compartir backups o referencias financieras
reales en el repositorio.

## Métricas de fuentes

Desde PowerShell, en la raíz:

```powershell
.\script\pruning\measure.ps1
```

Mide archivos versionados y líneas físicas de extensiones declaradas, incluyendo
comentarios y blancos. Los grupos se solapan y no se suman. No cuenta archivos
nuevos sin seguimiento; comparar revisiones consolidadas con el mismo método.
Las declaraciones Gemfile incluyen herramientas de desarrollo/test y condiciones;
los specs del lock incluyen dependencias transitivas.

## Ensayo de recuperación sintético

Ejecutar en el Docker local Linux, siguiendo las restricciones y aislamiento de
[Docker tests](../../docs/llm-guides/docker-tests.md). El proyecto dedicado evita
alterar `relay-local`, `relay-tests`, Sure y TrueNAS. La base de pruebas de este
proyecto se vuelve a cargar mediante el entrypoint; no usarla para otros datos.

```powershell
docker compose --project-name relay-pruning-phase0 --env-file docker/test.env --file compose.test.yml build runner
docker compose --project-name relay-pruning-phase0 --env-file docker/test.env --file compose.test.yml up --detach --wait db redis
docker compose --project-name relay-pruning-phase0 --env-file docker/test.env --file compose.test.yml run --rm runner unit test/models/family/backup_test.rb test/models/family/data_exporter_test.rb test/models/family/data_importer_test.rb test/models/sure_import_test.rb test/models/import_session_test.rb
docker compose --project-name relay-pruning-phase0 --env-file docker/test.env --file compose.test.yml run --rm --entrypoint ruby runner bin/rails runner script/pruning/phase_zero_rehearsal.rb /rails/tmp/screenshots/pruning-rehearsal.json
docker compose --project-name relay-pruning-phase0 --env-file docker/test.env --file compose.test.yml down
```

No ejecutar dos tareas que recargan esa base simultáneamente. El script se niega
a trabajar salvo en `RAILS_ENV=test`, base `relay_test`, host `db` y Redis de prueba.
Usa jobs capturados por el adapter test, sin worker ni proveedor externo.

Construye tres cuentas sintéticas, balances, una posición, transferencia,
Agenda con ocurrencias y un PDF de fixture. Exporta, restaura, reexporta y vuelve
a restaurar. Comprueba referencia financiera, verificación del restorer y bytes;
las filas se revierten mediante transacciones. Los archivos de Active Storage
quedan solo dentro del contenedor efímero del runner.

Resultados en el host:

- `tmp/docker-test-results/pruning-rehearsal.json`: referencia y verificaciones.
- `tmp/docker-test-results/pruning-source.ndjson`: snapshot anterior a la poda.
- `tmp/docker-test-results/pruning-reexport.ndjson`: snapshot reexportado.

Conservar los snapshots iniciales antes de repetir el comando: se sobrescriben,
y sus IDs/ticker sintéticos aleatorios cambian. El hash identifica un archivo
concreto; para comparar estados usar valores y relaciones remapeadas, no UUID
o hash completo. Los backups reales tienen otro inventario y requieren ensayo
privado aparte cuando una retirada afecte a sus modelos.
