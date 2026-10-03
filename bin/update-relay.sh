#!/usr/bin/env bash
# Update the existing TrueNAS YAML app named relay. Run on the TrueNAS host.
set -Eeuo pipefail
umask 077

usage() {
  echo "Uso: sudo bash /mnt/AppsPool/relay/update-relay.sh [--check]"
  echo "Actualiza la app relay al último commit publicado en main."
  echo "--check consulta main y valida la instalación sin construir, parar ni actualizar."
}
die() { echo "ERROR: $*" >&2; exit 1; }
[[ $# == 0 || ( $# == 1 && $1 == --check ) ]] || { usage; exit 1; }
[[ $EUID == 0 ]] || die "Ejecuta con sudo en TrueNAS."
for tool in docker midclt python3 curl gzip tar sha256sum flock mountpoint; do
  command -v "$tool" >/dev/null || die "Falta $tool."
done
ROOT=/mnt/AppsPool/relay
APP=relay
PROJECT=ix-relay
REPO=https://github.com/N7Steve/Relay
mountpoint -q /mnt/AppsPool || die "El pool AppsPool no está montado."
[[ -d $ROOT/config && -d $ROOT/postgres && -d $ROOT/storage && -d $ROOT/redis ]] || die "Instala primero compose.truenas.folder.yml con nombre relay."
mkdir -p "$ROOT/backups" "$ROOT/logs" "$ROOT/releases" "$ROOT/deployment" "$ROOT/.work"
BACKUP_ROOT="$ROOT/backups"
exec 9>"$ROOT/.update.lock"
flock -n 9 || die "Ya hay otra actualización de Relay en curso."
LOG="$ROOT/logs/update-$(date -u +%Y%m%dT%H%M%SZ)-$$.log"
exec > >(tee -a "$LOG") 2>&1
WORK=$(mktemp -d "$ROOT/.work/update-XXXXXXXX")
BACKUP=
UPDATE_STARTED=false
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
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Consultando el último commit de main..."
curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 60 \
  https://api.github.com/repos/N7Steve/Relay/commits/main > "$WORK/main.json"
SHA=$(python3 -I -c 'import json,sys; print(json.load(sys.stdin)["sha"])' < "$WORK/main.json")
[[ $SHA =~ ^[0-9a-f]{40}$ ]] || die "GitHub no devolvió un SHA válido."
IMAGE="relay-local:sha-$SHA"
CONTEXT="$REPO.git#$SHA"
echo "Leyendo la configuración guardada de la app Relay..."
midclt call app.get_instance "$APP" > "$WORK/app.json"
midclt call app.config "$APP" > "$WORK/before.json"
python3 -I - "$WORK" "$SHA" "$IMAGE" "$CONTEXT" "$ROOT" <<'PY'
import copy
import json
import pathlib
import sys

work, sha, image, context, root = sys.argv[1:]
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
    build = service.get("build", {})
    require(isinstance(build, dict), f"{name}: falta el build de Relay")
    old_context = build.get("context", "")
    require(old_context.startswith("https://github.com/N7Steve/Relay.git#"), f"{name}: el origen no es N7Steve/Relay")
    require(service.get("image", "").startswith("relay-local:"), f"{name}: la imagen no es local")
    build["context"] = context
    build.setdefault("args", {})["BUILD_COMMIT_SHA"] = sha
    service["image"] = image
    # Build once before downtime; the middleware must reuse that exact image.
    service["pull_policy"] = "never"
require(services["db"].get("environment", {}).get("POSTGRES_DB") == "relay_production", "Base de datos inesperada")
require(services["db"].get("environment", {}).get("POSTGRES_USER") == "relay_user", "Usuario PostgreSQL inesperado")
if "x-relay-image" in config:
    config["x-relay-image"].update(copy.deepcopy({k: services["web"][k] for k in ("image", "build", "pull_policy")}))
(work / "after.json").write_text(json.dumps(config))
(work / "payload.json").write_text(json.dumps({"custom_compose_config": config}))
print(f"Commit destino: {sha}")
print(f"Imagen destino: {image}")
PY

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
if [[ ${1:-} == --check ]]; then
  echo "Validación correcta. No se ha cambiado ni detenido la app."
  exit 0
fi

CURRENT_WEB=$(docker exec "$WEB" ruby -e 'puts ENV.fetch("BUILD_COMMIT_SHA", "unset")')
CURRENT_WORKER=$(docker exec "$WORKER" ruby -e 'puts ENV.fetch("BUILD_COMMIT_SHA", "unset")')
if [[ $CURRENT_WEB == "$SHA" && $CURRENT_WORKER == "$SHA" ]] &&
   [[ $(docker inspect --format '{{.State.Health.Status}}' "$WEB") == healthy ]]; then
  echo "Relay ya está actualizado al último commit de main: $SHA."
  exit 0
fi

echo "Descargando el código de $SHA en $ROOT/releases..."
SOURCE="$ROOT/releases/$SHA"
if [[ ! -f $SOURCE/.relay-source-sha ]] || [[ $(cat "$SOURCE/.relay-source-sha") != "$SHA" ]]; then
  [[ ! -e $SOURCE ]] || die "La carpeta de la versión existe pero está incompleta: $SOURCE. Consérvala y revisa su contenido."
  mkdir "$WORK/source"
  curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 300 \
    "https://api.github.com/repos/N7Steve/Relay/tarball/$SHA" > "$WORK/source.tar.gz"
  tar -xzf "$WORK/source.tar.gz" --strip-components=1 -C "$WORK/source"
  [[ -f $WORK/source/Dockerfile ]] || die "El commit no incluye el Dockerfile de Relay."
  printf '%s\n' "$SHA" > "$WORK/source/.relay-source-sha"
  mv "$WORK/source" "$SOURCE"
fi
echo "Construyendo el commit antes de detener Relay (puede tardar varios minutos)..."
docker build --pull --build-arg "BUILD_COMMIT_SHA=$SHA" --tag "$IMAGE" "$SOURCE"
BUILT_SHA=$(docker run --rm --network none --entrypoint ruby "$IMAGE" -e 'puts ENV.fetch("BUILD_COMMIT_SHA")')
[[ $BUILT_SHA == "$SHA" ]] || die "La imagen construida no identifica el commit solicitado."

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

# Do not overwrite a configuration edited in the UI while the image was building.
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
# Keep middleware output private: an app response can contain configuration.
midclt call -j app.update "$APP" "$(cat "$WORK/payload.json")" > "$BACKUP/update-result.json"
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
  actual=$(docker exec "$id" ruby -e 'puts ENV.fetch("BUILD_COMMIT_SHA", "unset")')
  [[ $actual == "$SHA" ]] || die "Un servicio no está ejecutando el commit solicitado."
done
docker exec "$web" /bin/bash -ec 'set -a; . /config/relay.env; set +a; exec bin/rails db:abort_if_pending_migrations'
docker exec "$web" ruby -v
docker ps --filter "label=com.docker.compose.project=$PROJECT" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
cp "$WORK/after.json" "$ROOT/deployment/app-current.json"
printf '%s\n' "$SHA" > "$ROOT/deployment/deployed-sha"
# init installs the updater shipped with the new image on every successful startup.
touch "$BACKUP/UPDATE_COMPLETE"
echo "Actualización terminada correctamente. Commit: $SHA"
echo "Backup privado conservado en: $BACKUP"
echo "Registro: $LOG"
