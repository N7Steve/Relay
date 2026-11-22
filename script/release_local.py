"""Build, validate and publish Relay (server image + Android APK) from this computer.

    python script/release_local.py check
    python script/release_local.py prepare [--preview]
    python script/release_local.py publish tmp/releases/<commit>

The signed APK is bundled into the server image, so TrueNAS updates both at once
when its cron job pulls ghcr.io/n7steve/relay:stable. Requires Python 3.11+.
"""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
IMAGE = "ghcr.io/n7steve/relay"
CHANNEL = "stable"
APPLICATION_ID = "app.relay.android"
ANDROID = ROOT / "android"
SIGNING_DIR = Path.home() / ".android" / "relay"


def run(*args, env=None, capture=False, cwd=ROOT):
    executable = shutil.which(str(args[0])) or (str(args[0]) if Path(str(args[0])).is_file() else None)
    if not executable:
        raise RuntimeError(f"No se encuentra {args[0]} en PATH")
    result = subprocess.run([executable, *map(str, args[1:])], cwd=cwd, env=env, text=True, capture_output=capture)
    if result.returncode:
        detail = f": {result.stderr.strip()[-600:]}" if capture and result.stderr else ""
        raise RuntimeError(f"Ha fallado {Path(str(args[0])).name} {' '.join(map(str, args[1:3]))} (codigo {result.returncode}){detail}")
    return result.stdout.strip() if capture else ""


def git(*args):
    return run("git", *args, capture=True)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def version_for(commit_count):
    """Monotonic on a linear main: every published commit has a larger count."""
    if commit_count < 1:
        raise ValueError("Numero de commits no valido")
    return commit_count, f"0.1.{commit_count}"


def package_android(metadata_path: Path, commit: str, destination: Path) -> dict:
    """Copy one signed Gradle APK as relay.apk plus the update.json manifest the server serves."""
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if metadata.get("applicationId") != APPLICATION_ID or not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("Identidad de aplicacion o commit inesperados")
    elements = metadata["elements"]
    if len(elements) != 1 or elements[0].get("filters"):
        raise ValueError("Se esperaba una unica APK universal")
    element = elements[0]
    filename = element["outputFile"]
    if Path(filename).name != filename or not filename.endswith(".apk") or "unsigned" in filename:
        raise ValueError("Solo se puede publicar una APK firmada")
    apk = metadata_path.parent / filename
    size = apk.stat().st_size
    code, name = element["versionCode"], element["versionName"]
    minimum = metadata["minSdkVersionForDexing"]
    if not (isinstance(code, int) and 1 <= code <= 2_100_000_000 and isinstance(name, str) and
            re.fullmatch(r"[0-9A-Za-z.\-+]{1,64}", name) and 26 <= minimum <= 100 and 1 <= size <= 150 * 1024 * 1024):
        raise ValueError("Metadatos de la APK no validos")
    release = {"version_code": code, "version_name": name, "application_id": APPLICATION_ID,
               "min_sdk": minimum, "size": size, "sha256": digest(apk), "commit": commit}
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(apk, destination / "relay.apk")
    write_json(destination / "update.json", release)
    return release


def android_env(code, name):
    env = dict(os.environ)
    sdk = env.get("ANDROID_HOME") or env.get("ANDROID_SDK_ROOT")
    candidates = [ROOT / "tmp/android-tools/sdk", Path.home() / "AppData/Local/Android/Sdk", ROOT.parent / "Ilos/tmp/android-tools/sdk"]
    sdk = sdk or next((str(c) for c in candidates if c.is_dir()), None)
    if not sdk:
        raise RuntimeError("Configura ANDROID_HOME con la ruta al SDK Android")
    env["ANDROID_HOME"] = sdk
    if not env.get("JAVA_HOME"):
        jdks = [*sorted((ROOT / "tmp/android-tools/jdk").glob("jdk-17*")), *sorted((ROOT.parent / "Ilos/tmp/android-tools/jdk").glob("jdk-17*"))]
        if not jdks:
            raise RuntimeError("Configura JAVA_HOME con la ruta a JDK 17")
        env["JAVA_HOME"] = str(jdks[0])
    env.setdefault("RELAY_ANDROID_KEYSTORE", str(SIGNING_DIR / "release.jks"))
    if not env.get("RELAY_ANDROID_STORE_PASSWORD"):
        password = SIGNING_DIR / "password.txt"
        if not password.is_file():
            raise RuntimeError(f"No se encuentra la contrasena de firma en {password}")
        env["RELAY_ANDROID_STORE_PASSWORD"] = password.read_text().rstrip("\r\n")
    env.setdefault("RELAY_ANDROID_KEY_PASSWORD", env["RELAY_ANDROID_STORE_PASSWORD"])
    env.setdefault("RELAY_ANDROID_KEY_ALIAS", "relay")
    env["RELAY_ANDROID_VERSION_CODE"] = str(code)
    env["RELAY_ANDROID_VERSION_NAME"] = name
    if not Path(env["RELAY_ANDROID_KEYSTORE"]).is_file():
        raise RuntimeError("No se encuentra la clave estable de firma Android de Relay")
    return env


def verify_apk(apk, env):
    extension = ".bat" if os.name == "nt" else ""
    tools = sorted((Path(env["ANDROID_HOME"]) / "build-tools").glob("*/apksigner" + extension))
    if not tools:
        raise RuntimeError("No se encuentra apksigner en el SDK Android")
    result = run(tools[-1], "verify", "--print-certs", apk, env=env, capture=True)
    match = re.search(r"Signer #1 certificate SHA-256 digest: ([a-f0-9]+)", result)
    expected = (ANDROID / "release-signing.sha256").read_text().strip()
    if not match or match[1] != expected:
        raise RuntimeError("La APK no tiene la identidad estable de firma de Relay")


def wait_until(check, seconds=180, message="Tiempo agotado esperando la comprobacion Docker"):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        with contextlib.suppress(Exception):
            if check():
                return
        time.sleep(3)
    raise RuntimeError(message)


def http(url, headers=None):
    request = urllib.request.Request(url, headers={"User-Agent": "relay-release-smoke", **(headers or {})})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


SMOKE_USER = """
family = Family.create!(name: "Release smoke", currency: "EUR", locale: "es")
user = family.users.create!(email: "release-smoke@example.invalid", password: SecureRandom.hex(16) + "Aa1!", role: :admin)
key = ApiKey.generate_secure_key
ApiKey.create!(user: user, name: "release smoke", key: key, scopes: %w[read], source: "web")
puts "KEY=#{key}"
"""


def verify_image(image, folder, commit, release):
    """Boot the image with disposable PostgreSQL/Redis and fetch the bundled APK through the API."""
    project = "relay-release-smoke-" + secrets.token_hex(4)
    password = secrets.token_hex(24)
    keys = {"SECRET_KEY_BASE": secrets.token_hex(64), "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY": secrets.token_hex(32),
            "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY": secrets.token_hex(32),
            "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT": secrets.token_hex(32)}
    app_env = {"RAILS_ENV": "production", "SELF_HOSTED": "true", "RAILS_FORCE_SSL": "false", "RAILS_ASSUME_SSL": "false",
               "RAILS_SERVE_STATIC_FILES": "true", "BINDING": "0.0.0.0", "PORT": "3000", "POSTGRES_DB": "relay_production",
               "POSTGRES_USER": "relay_user", "POSTGRES_PASSWORD": password, "DB_HOST": "db", "DB_PORT": "5432",
               "REDIS_URL": "redis://redis:6379/1", "ACTIVE_STORAGE_SERVICE": "local", **keys}
    config = {
        "name": project,
        "services": {
            "db": {"image": "postgres:16-bookworm", "environment": {"POSTGRES_DB": "relay_production", "POSTGRES_USER": "relay_user",
                   "POSTGRES_PASSWORD": password},
                   "healthcheck": {"test": ["CMD-SHELL", "pg_isready -U relay_user -d relay_production"], "interval": "3s", "retries": 40}},
            "redis": {"image": "redis:7.4-bookworm", "healthcheck": {"test": ["CMD", "redis-cli", "ping"], "interval": "3s", "retries": 40}},
            "web": {"image": image, "pull_policy": "never", "environment": app_env,
                    "command": ["./bin/rails", "server"], "ports": [{"target": 3000, "published": "0", "host_ip": "127.0.0.1"}],
                    "depends_on": {"db": {"condition": "service_healthy"}, "redis": {"condition": "service_healthy"}},
                    "healthcheck": {"test": ["CMD", "curl", "--fail", "--silent", "--output", "/dev/null", "http://127.0.0.1:3000/up"],
                                    "interval": "5s", "retries": 60, "start_period": "30s"}},
            "worker": {"image": image, "pull_policy": "never", "environment": app_env, "command": ["bundle", "exec", "sidekiq"],
                       "depends_on": {"web": {"condition": "service_healthy"}}},
        },
    }
    config_path = folder / "compose-smoke.json"
    write_json(config_path, config)

    def compose(*args, capture=False):
        return run("docker", "compose", "-p", project, "-f", config_path, *args, capture=capture)

    def container(service):
        return compose("ps", "-q", service, capture=True)

    try:
        compose("up", "-d", "--wait", "--wait-timeout", "300")
        web = container("web")
        inspected = json.loads(run("docker", "inspect", web, capture=True))[0]
        port = inspected["NetworkSettings"]["Ports"]["3000/tcp"][0]["HostPort"]
        if inspected["Config"]["User"] != "1000:1000":
            raise RuntimeError("La imagen no se ejecuta con el usuario rails")
        base = f"http://127.0.0.1:{port}"
        if run("docker", "exec", web, "ruby", "-e", 'puts ENV.fetch("BUILD_COMMIT_SHA")', capture=True) != commit:
            raise RuntimeError("La imagen no identifica el commit preparado")
        bundled = json.loads(run("docker", "exec", web, "cat", "/rails/android-release/update.json", capture=True))
        if bundled != release:
            raise RuntimeError("La imagen no contiene el manifiesto Android preparado")
        status, _ = http(base + "/up")
        if status != 200:
            raise RuntimeError(f"/up respondio {status}")
        status, _ = http(base + "/api/v1/android/updates/latest")
        if status != 401:
            raise RuntimeError("El canal Android no exige autenticacion")
        output = run("docker", "exec", web, "/bin/bash", "-c", 'exec bin/rails runner "$0"', SMOKE_USER, capture=True)
        key = re.search(r"KEY=(\S+)", output)[1]
        status, body = http(base + "/api/v1/android/updates/latest", {"X-Api-Key": key})
        latest = json.loads(body)
        if status != 200 or not latest["enabled"] or latest["release"] != release:
            raise RuntimeError("El servidor no ofrece la version Android preparada")
        status, apk = http(base + f"/api/v1/android/updates/{release['version_code']}/apk", {"X-Api-Key": key})
        if status != 200 or len(apk) != release["size"] or hashlib.sha256(apk).hexdigest() != release["sha256"]:
            raise RuntimeError("La APK servida no coincide con la preparada")
        time.sleep(5)
        worker = json.loads(run("docker", "inspect", container("worker"), capture=True))[0]
        if not worker["State"]["Running"]:
            raise RuntimeError("Sidekiq no arranca con la imagen preparada")
        compose("restart", "web")

        def restarted():
            # The loopback port is reassigned when the container restarts.
            ports = json.loads(run("docker", "inspect", container("web"), capture=True))[0]["NetworkSettings"]["Ports"]
            return http(f"http://127.0.0.1:{ports['3000/tcp'][0]['HostPort']}/up")[0] == 200
        wait_until(restarted, message="Relay no vuelve a arrancar tras reiniciar")
        print("Imagen verificada: migraciones, salud, worker, canal Android autenticado y descarga de la APK.", flush=True)
    finally:
        try:
            compose("down", "--volumes", "--remove-orphans")
        finally:
            config_path.unlink(missing_ok=True)


def require_source(commit=None, clean=True):
    if git("branch", "--show-current") != "main":
        raise RuntimeError("La publicacion local requiere main")
    if clean and git("status", "--porcelain"):
        raise RuntimeError("Hay cambios sin commit. --preview permite validarlos sin publicar.")
    head = git("rev-parse", "HEAD")
    if commit and head != commit:
        raise RuntimeError("HEAD ha cambiado; vuelve a preparar esta version")
    return head


def powershell():
    return shutil.which("pwsh") or shutil.which("powershell") or "powershell"


def check_deployment_scripts():
    """The TrueNAS updater tests need Linux root; run them in a disposable Ruby container."""
    before = (ROOT / "compose.truenas.folder.yml").read_bytes()
    run("docker", "run", "--rm", "-v", f"{ROOT}:/src", "-w", "/src", "ruby:3.4-bookworm", "bash", "-ec",
        "ruby bin/render-relay-yaml.rb && ruby test/deployment/update_relay_test.rb && ruby test/deployment/truenas_folder_test.rb")
    if (ROOT / "compose.truenas.folder.yml").read_bytes() != before:
        raise RuntimeError("compose.truenas.folder.yml no estaba sincronizado con bin/update-relay.sh; revisa el cambio generado")


def prepare(preview, skip_rails_tests=False):
    started = time.monotonic()
    commit = require_source(clean=not preview)
    code, name = version_for(int(git("rev-list", "--count", "HEAD")))
    folder = ROOT / "tmp/releases" / (commit + ("-preview-" + secrets.token_hex(4) if preview else ""))
    if (folder / "prepared.json").exists():
        raise RuntimeError("Este commit ya esta preparado; publica su carpeta")
    folder.mkdir(parents=True, exist_ok=True)
    env = android_env(code, name)
    print(f"Preparando Relay {commit[:12]} con Android {name} ({code})", flush=True)

    run(sys.executable, "-m", "unittest", "discover", "-s", "script/tests")
    check_deployment_scripts()
    if skip_rails_tests:
        if not preview:
            raise RuntimeError("Solo una preview puede omitir las pruebas de Rails")
        print("PREVIEW: pruebas de Rails omitidas", flush=True)
    else:
        run(powershell(), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "bin/test-docker.ps1", "unit")
        run(powershell(), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "bin/test-docker.ps1", "checks")

    gradle = ANDROID / ("gradlew.bat" if os.name == "nt" else "gradlew")
    run(gradle, "--console=plain", "--no-daemon", "assembleDebug", "testDebugUnitTest", "lintDebug", "assembleRelease", env=env, cwd=ANDROID)
    apk = ANDROID / "app/build/outputs/apk/release/app-release.apk"
    verify_apk(apk, env)
    context = folder / "image-context"
    release = package_android(apk.parent / "output-metadata.json", commit, context / "relay-android")
    if (release["version_code"], release["version_name"]) != (code, name):
        raise RuntimeError("Gradle no ha usado la version asignada")

    image = f"relay-local:{commit}"
    run("docker", "buildx", "build", "--load", "--provenance=false", "--platform", "linux/amd64", "-t", image,
        "--build-arg", f"BUILD_COMMIT_SHA={commit}", "--build-context", f"android-release={context}",
        "--label", "org.opencontainers.image.source=https://github.com/N7Steve/Relay",
        "--label", f"org.opencontainers.image.revision={commit}",
        "--label", f"org.opencontainers.image.version={name}", ".")
    verify_image(image, folder, commit, release)
    require_source(commit, clean=not preview)
    image_id = json.loads(run("docker", "image", "inspect", image, capture=True))[0]["Id"]
    write_json(folder / "prepared.json", {
        "commit": commit, "preview": preview, "image": image, "imageId": image_id,
        "versionCode": code, "versionName": name, "durationSeconds": round(time.monotonic() - started),
        "apkSha256": digest(context / "relay-android/relay.apk"), "manifestSha256": digest(context / "relay-android/update.json"),
    })
    print(f"Validacion completa. Carpeta: {folder}", flush=True)
    if preview:
        print("PREVIEW: no publicable. Tras confirmar los cambios y hacer commit, prepara de nuevo.")
    else:
        print("Sube este commit a origin/main y ejecuta: python script/release_local.py publish " + str(folder))


def publish(folder):
    folder = folder.resolve()
    prepared = json.loads((folder / "prepared.json").read_text())
    if prepared["preview"]:
        raise RuntimeError("Una preview no se puede publicar")
    commit = require_source(prepared["commit"])
    if git("ls-remote", "origin", "refs/heads/main").split()[0] != commit:
        raise RuntimeError("Sube primero el commit validado a origin/main")
    android = folder / "image-context/relay-android"
    for filename, key in [("relay.apk", "apkSha256"), ("update.json", "manifestSha256")]:
        if digest(android / filename) != prepared[key]:
            raise RuntimeError("Se han modificado los archivos preparados; no se publican")
    manifest = json.loads((android / "update.json").read_text())
    if manifest["commit"] != commit:
        raise RuntimeError("El manifiesto no corresponde al commit")
    verify_apk(android / "relay.apk", android_env(manifest["version_code"], manifest["version_name"]))
    image = json.loads(run("docker", "image", "inspect", prepared["image"], capture=True))[0]
    if image["Id"] != prepared["imageId"]:
        raise RuntimeError("La imagen preparada ha cambiado")
    # A traceable tag first; TrueNAS only follows the channel once the push is complete.
    target = f"{IMAGE}:sha-{commit}"
    run("docker", "tag", prepared["image"], target)
    run("docker", "push", target)
    run("docker", "tag", prepared["image"], f"{IMAGE}:{CHANNEL}")
    run("docker", "push", f"{IMAGE}:{CHANNEL}")
    digests = json.loads(run("docker", "image", "inspect", target, capture=True))[0].get("RepoDigests", [])
    reference = next((d for d in digests if d.startswith(IMAGE + "@")), target)
    write_json(folder / "published.json", {"commit": commit, "image": reference, "imageId": prepared["imageId"],
                                           "versionCode": manifest["version_code"], "versionName": manifest["version_name"]})
    print(f"Publicado {IMAGE}:{CHANNEL} ({reference}) con Android {manifest['version_name']}.")
    print("TrueNAS lo aplicara en la siguiente ejecucion del cron (update-relay.sh --cron).")


def check():
    for tool in ["git", "docker"]:
        if not shutil.which(tool):
            raise RuntimeError(f"Falta {tool}")
    if run("docker", "info", "--format", "{{.OSType}}", capture=True) != "linux":
        raise RuntimeError("Docker Desktop debe usar contenedores Linux")
    run("docker", "buildx", "version", capture=True)
    env = android_env(1, "0.1.1")
    print(f"Java: {env['JAVA_HOME']}\nSDK Android: {env['ANDROID_HOME']}\nFirma: {env['RELAY_ANDROID_KEYSTORE']}")
    print("Herramientas listas. Para publicar, Docker necesita 'docker login ghcr.io' con write:packages.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check")
    prep = commands.add_parser("prepare")
    prep.add_argument("--preview", action="store_true", help="Valida cambios sin commit; no publicable")
    prep.add_argument("--skip-rails-tests", action="store_true", help="Solo con --preview: omite la suite de Rails")
    pub = commands.add_parser("publish")
    pub.add_argument("folder", type=Path)
    args = parser.parse_args()
    os.chdir(ROOT)
    # One local release at a time, including previews. A process crash releases the lock.
    lock_path = ROOT / "tmp/local-release.lock"
    lock_path.parent.mkdir(exist_ok=True)
    with lock_path.open("r+b" if lock_path.exists() else "w+b") as lock:
        if os.name == "nt":
            import msvcrt
            if lock_path.stat().st_size == 0:
                lock.write(b"0")
                lock.flush()
            lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.command == "check":
            check()
        elif args.command == "prepare":
            prepare(args.preview, args.skip_rails_tests)
        else:
            publish(args.folder)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
