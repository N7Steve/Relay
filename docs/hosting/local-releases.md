# Local releases

Relay and its Android app are compiled and verified on the development computer.
GitHub stores the source (mirrored as a pull mirror in Gitea) and the local Gitea
Container Registry (`100.81.25.109:30008/n7steve/relay`) stores the private image;
nothing is rebuilt after a push. TrueNAS follows
`100.81.25.109:30008/n7steve/relay:stable` through its
[cron updater](truenas.md#automatic-updates-cron). The signed APK travels inside
the image and Relay serves it to signed-in devices.

## One-time setup

- Python 3.11+, Git and Docker Desktop with Linux containers.
- JDK 17 and the Android SDK. The script uses `JAVA_HOME`/`ANDROID_HOME`, or
  finds `tmp/android-tools` here or in the sibling Ilos checkout.
- The Relay signing identity in `%USERPROFILE%\.android\relay` (`release.jks`,
  `password.txt`, alias `relay`). Its public fingerprint is
  [`android/release-signing.sha256`](../../android/release-signing.sha256).
  **Back up both files privately.** Losing them prevents updating installed apps;
  never regenerate them for an update. `RELAY_ANDROID_KEYSTORE`,
  `RELAY_ANDROID_STORE_PASSWORD`, `RELAY_ANDROID_KEY_ALIAS` and
  `RELAY_ANDROID_KEY_PASSWORD` override the defaults.
- Configure `"insecure-registries": ["100.81.25.109:30008"]` in Docker Engine
  (`%USERPROFILE%\.docker\daemon.json`) and run
  `docker login 100.81.25.109:30008 -u n7steve` with a Gitea token that has
  `write:package`.

```powershell
npm run release:check
```

## Validate uncommitted changes

```powershell
npm run release:prepare -- --preview
```

Runs every check and builds every product from the working tree. A preview cannot
be published. `--skip-rails-tests` (preview only) skips the long Rails suites.

## Publish

1. Commit the reviewed changes on `main`.
2. From the clean commit: `npm run release:prepare`. It prints the release folder.
3. Push that commit to `origin/main`.
4. `npm run release:publish -- "D:\Steve\Proyectos\Relay\tmp\releases\<commit>"`

`prepare` and `publish` never commit or push code. Only `publish` uploads.

## What prepare checks

- Release script tests and the TrueNAS updater/YAML tests (Linux root in a
  disposable Ruby container), including that the embedded updater is in sync.
- Full Rails suite and checks in Docker (`bin/test-docker.ps1 unit` and
  `checks`: RuboCop, ERB lint, Brakeman, bundler-audit, Biome).
- Android debug build, JVM tests, lint and the signed release with the stable
  signing fingerprint.
- A `linux/amd64` image with the APK bundled through the `android-release`
  build context, booted with disposable PostgreSQL and Redis: migrations, health,
  user, worker, restart, the authenticated Android channel and an APK download
  whose size and SHA-256 match.

## Versions and order

The Android `versionCode` is the commit count of `main` and the name is
`0.1.<count>`. History on `main` is linear (no force-push), so each published
commit has a higher code. The server's build identifier is the commit SHA.

`publish` checks that `main` is clean, `HEAD` and `origin/main` are the prepared
commit, the files and image are unchanged and the APK signature is the stable
one. It pushes `sha-<commit>` first and only then moves `stable`. If the second
push fails, TrueNAS keeps the previous release; repeat `publish`.
