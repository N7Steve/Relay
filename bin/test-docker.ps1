param(
    [ValidateSet('unit', 'system', 'checks', 'build', 'stop')]
    [string]$Task = 'unit',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$TestArguments
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
$dockerPath = if ($dockerCommand) { $dockerCommand.Source } else { $null }
if (-not $dockerPath) {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\resources\bin\docker.exe'),
        'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
    )
    $dockerPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $dockerPath) {
    throw 'Docker Desktop no esta instalado. Consulta docs/llm-guides/docker-tests.md.'
}

# Refuse a remote daemon: this command is specifically for this Windows machine.
if ($env:DOCKER_HOST -and -not $env:DOCKER_HOST.StartsWith('npipe://')) {
    throw 'DOCKER_HOST apunta a un motor remoto. Usa Docker Desktop local para estas pruebas.'
}
$activeContext = & $dockerPath context show
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo consultar el contexto de Docker.'
}
$activeContext = "$activeContext".Trim()
$endpoint = & $dockerPath context inspect $activeContext --format '{{.Endpoints.docker.Host}}'
if ($LASTEXITCODE -ne 0 -or -not "$endpoint".Trim().StartsWith('npipe://')) {
    throw 'Selecciona un contexto local de Docker Desktop (desktop-linux o default).'
}
$osType = & $dockerPath --context $activeContext info --format '{{.OSType}}' 2>$null
if ($LASTEXITCODE -ne 0 -or "$osType".Trim() -ne 'linux') {
    throw 'Arranca Docker Desktop con contenedores Linux y vuelve a ejecutar este comando.'
}

$composeArguments = @(
    '--context', $activeContext, 'compose', '--project-name', 'sure-tests',
    '--project-directory', $repoRoot,
    '--env-file', (Join-Path $repoRoot 'docker/test.env'),
    '--file', (Join-Path $repoRoot 'compose.test.yml')
)

function Invoke-TestCompose {
    param([string[]]$Arguments)
    & $dockerPath @composeArguments @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose fallo con codigo $LASTEXITCODE."
    }
}

if ($Task -eq 'stop') {
    Invoke-TestCompose -Arguments @('--profile', 'browser', 'down')
    exit 0
}

Invoke-TestCompose -Arguments @('build', 'runner')
New-Item -ItemType Directory -Path (Join-Path $repoRoot 'tmp/docker-test-results') -Force | Out-Null

if ($Task -eq 'system') {
    Invoke-TestCompose -Arguments @('up', '--detach', '--wait', 'db', 'redis')
    # Clear any browser session left behind by an interrupted previous run.
    Invoke-TestCompose -Arguments @('--profile', 'browser', 'up', '--detach', '--wait', '--force-recreate', '--no-deps', 'selenium')
    $runArguments = @(
        '--profile', 'browser', 'run', '--rm', '--use-aliases',
        '-e', 'SELENIUM_REMOTE_URL=http://selenium:4444',
        '-e', 'CAPYBARA_APP_HOST=runner',
        '-e', 'CAPYBARA_SERVER_PORT=3001', 'runner', 'system'
    )
} else {
    Invoke-TestCompose -Arguments @('up', '--detach', '--wait', 'db', 'redis')
    $runArguments = @('run', '--rm', 'runner', $Task)
}
Invoke-TestCompose -Arguments ($runArguments + $TestArguments)
