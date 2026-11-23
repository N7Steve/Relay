#!/usr/bin/env bash
# Update the existing TrueNAS YAML app named relay to the published image.
# Run on the TrueNAS host, by hand or from a TrueNAS cron job with --cron.
set -Eeuo pipefail
umask 077

usage() {
  echo "Uso: sudo bash /mnt/AppsPool/relay/update-relay.sh [--check|--cron]"
  echo "Actualiza la app relay a la imagen publicada 127.0.0.1:30008/n7steve/relay:stable."
  echo "--check descarga la referencia y valida la instalación sin parar ni actualizar."
  echo "--cron  igual que sin argumentos, pero no conserva registro si no hay cambios."
}
die() { echo "ERROR: $*" >&2; exit 1; }
MODE=apply
case "$#:${1:-}" in
  0:) ;;
  1:--check) MODE=check ;;
  1:--cron) MODE=cron ;;
  *) usage; exit 1 ;;
esac
[[ $EUID == 0 ]] || die "Ejecuta con sudo en TrueNAS."
for tool in docker midclt python3 gzip tar sha256sum flock mountpoint; do
  command -v "$tool" >/dev/null || die "Falta $tool."
done
ROOT=/mnt/AppsPool/relay
APP=relay
PROJECT=ix-relay
REGISTRY_IMAGE=127.0.0.1:30008/n7steve/relay
LEGACY_REGISTRY_IMAGE=ghcr.io/n7steve/relay
CHANNEL=stable
mountpoint -q /mnt/AppsPool || die "El pool AppsPool no está montado."
[[ -d $ROOT/config && -d $ROOT/postgres && -d $ROOT/storage && -d $ROOT/redis ]] || die "Instala primero compose.truenas.folder.yml con nombre relay."
mkdir -p "$ROOT/backups" "$ROOT/logs" "$ROOT/deployment" "$ROOT/.work"
# Optional credentials for a private package, kept with the app instead of /root.
if [[ -f $ROOT/registry/config.json ]]; then
  export DOCKER_CONFIG=$ROOT/registry
fi
BACKUP_ROOT="$ROOT/backups"
ATTEMPT="$ROOT/deployment/update-attempted-image"
exec 9>"$ROOT/.update.lock"
if ! flock -n 9; then
  [[ $MODE == cron ]] && exit 0
  die "Ya hay otra actualización de Relay en curso."
fi
LOG="$ROOT/logs/update-$(date -u +%Y%m%dT%H%M%SZ)-$$.log"
exec > >(tee -a "$LOG") 2>&1
WORK=$(mktemp -d "$ROOT/.work/update-XXXXXXXX")
BACKUP=
UPDATE_STARTED=false
KEEP_LOG=true
STOPPED=()
cleanup() {
  local status=$?
  trap - EXIT
  if (( status != 0 )); then
    echo "Actualización interrumpida. Backup: ${BACKUP:-todavía no creado}." >&2
    if [[ $UPDATE_STARTED == false && ${#STOPPED[@]} -gt 0 ]]; then
      echo "Reanudando los contenedores anteriores; no se ha aplicado el cambio." >&2
      docker start "${STOPPED[@]}" >/dev/null || echo "No se pudieron reanudar todos los servicios; revisa Relay en TrueNAS." >&2
    elif [[ $UPDATE_STARTED == true ]]; then
      echo "Revisa Relay y el trabajo de actualización en TrueNAS. No se revierte automáticamente una base de datos migrada." >&2
    fi
  fi
  rm -rf -- "$WORK"
  [[ $KEEP_LOG == true ]] || rm -f -- "$LOG"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Consultando $REGISTRY_IMAGE:$CHANNEL..."
docker pull --quiet "$REGISTRY_IMAGE:$CHANNEL" >/dev/null ||
  die "No se pudo descargar $REGISTRY_IMAGE:$CHANNEL. Revisa Gitea o las credenciales de 127.0.0.1:30008."
docker image inspect "$REGISTRY_IMAGE:$CHANNEL" > "$WORK/image.json"
read -r IMAGE_ID IMAGE SHA < <(python3 -I - "$WORK/image.json" "$REGISTRY_IMAGE" <<'PY'
import json
import re
import sys

(image,) = json.load(open(sys.argv[1]))
repository = sys.argv[2]
digests = [d for d in image.get("RepoDigests") or [] if re.fullmatch(re.escape(repository) + r"@sha256:[0-9a-f]{64}", d)]
env = dict(item.split("=", 1) for item in image.get("Config", {}).get("Env") or [] if "=" in item)
sha = env.get("BUILD_COMMIT_SHA", "")
if not re.fullmatch(r"sha256:[0-9a-f]{64}", image.get("Id", "")) or len(digests) != 1:
    sys.exit("La imagen publicada no tiene un digest único del registro")
if image.get("Os") != "linux" or image.get("Architecture") != "amd64":
    sys.exit("La imagen publicada no es linux/amd64")
if not re.fullmatch(r"[0-9a-f]{40}", sha):
    sys.exit("La imagen publicada no identifica su commit")
print(image["Id"], digests[0], sha)
PY
)
[[ -n ${SHA:-} ]] || die "No se pudo identificar la imagen publicada."
if [[ $MODE == cron && -f $ATTEMPT && $(<"$ATTEMPT") == "$IMAGE" ]]; then
  echo "Ya se intentó desplegar esta imagen. Revisa el registro anterior y usa el actualizador manual para reintentar."
  KEEP_LOG=false
  exit 0
fi
echo "Leyendo la configuración guardada de la app Relay..."
midclt call app.get_instance "$APP" > "$WORK/app.json"
midclt call app.config "$APP" > "$WORK/before.json"
python3 -I - "$WORK" "$IMAGE" "$ROOT" "$REGISTRY_IMAGE" "$LEGACY_REGISTRY_IMAGE" <<'PY'
import copy
import json
import pathlib
import sys

work, image, root, repository, legacy_repository = sys.argv[1:]
work = pathlib.Path(work)
app = json.loads((work / "app.json").read_text())

def require(condition, message):
    if not condition:
        sys.exit(message)

require(app.get("custom_app") and app.get("state") == "RUNNING", "Relay debe ser una app personalizada en estado RUNNING")
original = json.loads((work / "before.json").read_text())
config = copy.deepcopy(original)
services = config.get("services", {})
require(set(services) == {"init", "db", "redis", "web", "worker"}, "Los servicios no coinciden con compose.truenas.folder.yml")
require(not config.get("volumes"), "La app usa volúmenes Docker; instala el YAML nuevo, no se migran datos automáticamente")
expected_mounts = {
    "init": {"/relay": (root, False)},
    "db": {"/var/lib/postgresql/data": (root + "/postgres", False), "/config": (root + "/config", True)},
    "redis": {"/data": (root + "/redis", False)},
    "web": {"/config": (root + "/config", True), "/rails/storage": (root + "/storage", False)},
    "worker": {"/config": (root + "/config", True), "/rails/storage": (root + "/storage", False)},
}
for name, expected in expected_mounts.items():
    mounts = {}
    entries = services[name].get("volumes", [])
    for item in entries:
        if isinstance(item, str):
            parts = item.split(":")
            require(len(parts) in (2, 3), f"{name}: montaje inesperado")
            source, target = parts[:2]
            readonly = len(parts) == 3 and "ro" in parts[2].split(",")
        else:
            require(item.get("type") == "bind", f"{name}: se esperaba un bind mount")
            source, target = item.get("source"), item.get("target")
            readonly = item.get("read_only", False)
        mounts[target] = (source, readonly)
    require(len(entries) == len(expected) and mounts == expected, f"{name}: los datos deben estar en {root}; no se migran otras instalaciones")
for name in ("init", "web", "worker"):
    service = services[name]
    current = service.get("image", "")
    published = any(
        current.startswith(repo + ":") or current.startswith(repo + "@sha256:")
        for repo in (repository, legacy_repository)
    )
    # Installations from the earlier updater build the GitHub source locally.
    legacy = current.startswith("relay-local:") and isinstance(service.get("build"), dict) and \
        service["build"].get("context", "").startswith("https://github.com/N7Steve/Relay.git#")
    require(published or legacy, f"{name}: la imagen no es de N7Steve/Relay")
    service.pop("build", None)
    service["image"] = image
    # The updater pulls before downtime; the middleware reuses that exact image.
    service["pull_policy"] = "missing"
require(services["db"].get("environment", {}).get("POSTGRES_DB") == "relay_production", "Base de datos inesperada")
require(services["db"].get("environment", {}).get("POSTGRES_USER") == "relay_user", "Usuario PostgreSQL inesperado")
if "x-relay-image" in config:
    config["x-relay-image"] = {"image": image, "pull_policy": "missing"}
(work / "after.json").write_text(json.dumps(config))
(work / "payload.json").write_text(json.dumps({"custom_compose_config": config}))
PY
echo "Imagen publicada: $IMAGE"
echo "Commit: $SHA"

container() {
  local service=$1 ids
  ids=$(docker ps --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.service=$service" --format '{{.ID}}')
  [[ -n $ids && $ids != *$'\n'* ]] || die "Se esperaba un contenedor activo para $PROJECT/$service."
  printf '%s' "$ids"
}
DB=$(container db)
REDIS=$(container redis)
WEB=$(container web)
WORKER=$(container worker)
docker exec "$WEB" test -s /config/relay.env
docker exec "$DB" sh -ec 'test "$POSTGRES_DB" = relay_production; test "$POSTGRES_USER" = relay_user; pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null
docker exec "$REDIS" redis-cli ping | grep -qx PONG
if [[ $MODE == check ]]; then
  echo "Validación correcta. No se ha cambiado ni detenido la app."
  exit 0
fi

if [[ $(docker inspect --format '{{.Image}}' "$WEB") == "$IMAGE_ID" && $(docker inspect --format '{{.Image}}' "$WORKER") == "$IMAGE_ID" ]] &&
   [[ $(docker inspect --format '{{.State.Health.Status}}' "$WEB") == healthy ]]; then
  echo "Relay ya ejecuta la imagen publicada: $SHA."
  [[ $MODE == cron ]] && KEEP_LOG=false
  exit 0
fi
PREVIOUS_IMAGE_ID=$(docker inspect --format '{{.Image}}' "$WEB")

active_updates() {
  midclt call core.get_jobs '[["method","=","app.update"],["state","in",["RUNNING","WAITING"]]]' '{"count":true}'
}
running=$(active_updates) && [[ $running == 0 ]] ||
  die "TrueNAS tiene una actualización activa o no se pudo comprobar su estado."
printf '%s\n' "$IMAGE" > "$ATTEMPT"

mkdir -p -- "$BACKUP_ROOT"
BACKUP=$(mktemp -d "$BACKUP_ROOT/relay-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXXXX")
cp "$WORK/before.json" "$BACKUP/app-before.json"
cp "$WORK/after.json" "$BACKUP/app-after.json"
cp "$WORK/app.json" "$BACKUP/app-metadata.json"
echo "Deteniendo web y worker para obtener una copia consistente..."
for id in "$WEB" "$WORKER"; do
  STOPPED=("$id" "${STOPPED[@]}")
  docker stop --time 120 "$id" >/dev/null
  [[ $(docker inspect --format '{{.State.ExitCode}}' "$id") != 137 ]] || die "Un servicio no se detuvo limpiamente; no se actualizará."
done
echo "Guardando PostgreSQL, claves, adjuntos y cola Redis en $BACKUP..."
docker exec "$DB" sh -ec 'pg_dump -Fc -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$BACKUP/database.dump"
[[ -s $BACKUP/database.dump ]] || die "El dump está vacío."
docker exec -i "$DB" pg_restore --list < "$BACKUP/database.dump" > "$BACKUP/database-contents.txt"
docker cp "$WEB:/config/." - | gzip > "$BACKUP/config.tar.gz"
docker cp "$WEB:/rails/storage/." - | gzip > "$BACKUP/storage.tar.gz"
docker exec "$REDIS" redis-cli SAVE | grep -qx OK
STOPPED=("$REDIS" "${STOPPED[@]}")
docker stop --time 60 "$REDIS" >/dev/null
docker cp "$REDIS:/data/." - | gzip > "$BACKUP/redis.tar.gz"
for archive in config storage redis; do
  gzip -t "$BACKUP/$archive.tar.gz"
  tar -tzf "$BACKUP/$archive.tar.gz" >/dev/null
done
(cd "$BACKUP" && sha256sum -- app-*.json database.dump database-contents.txt ./*.tar.gz > SHA256SUMS)
touch "$BACKUP/BACKUP_COMPLETE"

# Do not overwrite a configuration edited in the UI while the backup was running.
midclt call app.config "$APP" > "$WORK/current.json"
python3 -I - "$WORK/before.json" "$WORK/current.json" <<'PY'
import json
import sys
with open(sys.argv[1]) as before, open(sys.argv[2]) as current:
    if json.load(before) != json.load(current):
        sys.exit("La configuración cambió durante la preparación; no se actualizará.")
PY

echo "Aplicando el cambio a través de TrueNAS; web preparará la base de datos al arrancar..."
UPDATE_STARTED=true
submit_update() {
  # The configuration goes over the middleware socket, never on a command line:
  # TrueNAS audits commands run through sudo (its cron jobs included), and sudo
  # kills a process whose long arguments it cannot verify ("argv mismatch").
  python3 -I - "$APP" "$WORK/payload.json" <<'PY'
import json
import sys

try:
    from truenas_api_client import Client
except ImportError:
    from middlewared.client import Client

app, path = sys.argv[1:]
with open(path) as source:
    payload = json.load(source)
# Without waiting, a job method returns its id; the caller polls the state.
with Client() as client:
    print(client.call("app.update", app, payload))
PY
}
update_job_succeeded() {
  local job_id state deadline
  # Submit the job without streaming progress or downloading the job's full result.
  submit_update > "$BACKUP/update-result.json" 2> "$BACKUP/update-error.txt" || return 1
  job_id=$(<"$BACKUP/update-result.json")
  [[ $job_id =~ ^[0-9]+$ ]] || return 1
  echo "Trabajo TrueNAS: $job_id"
  deadline=$((SECONDS + 600))
  while (( SECONDS < deadline )); do
    state=$(midclt call core.get_jobs "[[\"id\",\"=\",$job_id]]" '{"select":["state"]}' 2>> "$BACKUP/update-error.txt" |
      python3 -I -c 'import json,sys; jobs=json.load(sys.stdin); print(jobs[0]["state"] if jobs else "")') || return 1
    case "$state" in
      SUCCESS) return 0 ;;
      RUNNING|WAITING) sleep 5 ;;
      *) printf 'Trabajo %s: %s\n' "$job_id" "${state:-no encontrado}" >> "$BACKUP/update-error.txt"; return 1 ;;
    esac
  done
  echo "Trabajo $job_id: tiempo de espera agotado" >> "$BACKUP/update-error.txt"
  return 1
}
if ! update_job_succeeded; then
  echo "TrueNAS no ha confirmado app.update. Diagnóstico privado en $BACKUP/update-error.txt." >&2
  running=$(active_updates 2>/dev/null || echo unknown)
  midclt call app.config "$APP" > "$WORK/after-failure.json" 2>/dev/null || true
  if [[ $running == 0 ]] && python3 -I - "$WORK/before.json" "$WORK/after-failure.json" <<'PY'
import json
import sys
with open(sys.argv[1]) as before, open(sys.argv[2]) as current:
    sys.exit(0 if json.load(before) == json.load(current) else 1)
PY
  then
    # The stored configuration is unchanged and no job is running: nothing was
    # applied, so the previous code and the unmigrated database can resume.
    UPDATE_STARTED=false
    die "TrueNAS rechazó el cambio y no modificó la app. Se reanuda la versión anterior; no se ha perdido nada."
  fi
  die "No está claro si TrueNAS aplicó el cambio (trabajos activos: $running). Revisa la app y logs/; no se reanuda nada automáticamente."
fi
echo "Esperando a web y worker (hasta 5 minutos)..."
deadline=$((SECONDS + 300))
ready=false
while (( SECONDS < deadline )); do
  web=$(docker ps --filter "label=com.docker.compose.project=$PROJECT" --filter label=com.docker.compose.service=web --format '{{.ID}}')
  worker=$(docker ps --filter "label=com.docker.compose.project=$PROJECT" --filter label=com.docker.compose.service=worker --format '{{.ID}}')
  if [[ -n $web && $web != *$'\n'* && -n $worker && $worker != *$'\n'* ]] &&
     [[ $(docker inspect --format '{{.State.Health.Status}}' "$web") == healthy ]] &&
     [[ $(docker inspect --format '{{.State.Running}}' "$worker") == true ]]; then
    ready=true
    break
  fi
  sleep 5
done
[[ $ready == true ]] || die "Relay no ha arrancado correctamente. Revisa los logs en TrueNAS."
for id in "$web" "$worker"; do
  [[ $(docker inspect --format '{{.Image}}' "$id") == "$IMAGE_ID" ]] || die "Un servicio no está ejecutando la imagen publicada."
  actual=$(docker exec "$id" ruby -e 'puts ENV.fetch("BUILD_COMMIT_SHA", "unset")')
  [[ $actual == "$SHA" ]] || die "Un servicio no está ejecutando el commit solicitado."
done
docker exec "$web" /bin/bash -ec 'set -a; . /config/relay.env; set +a; exec bin/rails db:abort_if_pending_migrations'
docker exec "$web" ruby -v
docker ps --filter "label=com.docker.compose.project=$PROJECT" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
cp "$WORK/after.json" "$ROOT/deployment/app-current.json"
printf '%s\n' "$SHA" > "$ROOT/deployment/deployed-sha"
printf '%s\n' "$IMAGE" > "$ROOT/deployment/deployed-image"
# init installs the updater shipped with the new image on every successful startup.
touch "$BACKUP/UPDATE_COMPLETE"
rm -f -- "$ATTEMPT"
# Keep the running and previous images for a manual rollback; Docker refuses to
# remove an image that a container still uses.
docker image ls --no-trunc --format '{{.Repository}} {{.ID}}' | sort -u | while read -r repository old; do
  [[ ( $repository == "$REGISTRY_IMAGE" || $repository == "$LEGACY_REGISTRY_IMAGE" ) && $old != "$IMAGE_ID" && $old != "$PREVIOUS_IMAGE_ID" ]] || continue
  docker image rm "$old" >/dev/null 2>&1 || true
done
echo "Actualización terminada correctamente. Commit: $SHA"
echo "Backup privado conservado en: $BACKUP"
echo "Registro: $LOG"
