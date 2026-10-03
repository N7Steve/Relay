param(
    [ValidateSet('start', 'stop', 'logs')]
    [string]$Task = 'start',
    [switch]$NoBrowser
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
if (-not $dockerPath) { throw 'Docker Desktop no esta instalado.' }
if ($env:DOCKER_HOST -and -not $env:DOCKER_HOST.StartsWith('npipe://')) {
    throw 'Usa Docker Desktop local; DOCKER_HOST apunta a un motor remoto.'
}
$activeContext = & $dockerPath context show
if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar el contexto de Docker.' }
$activeContext = "$activeContext".Trim()
$endpoint = & $dockerPath context inspect $activeContext --format '{{.Endpoints.docker.Host}}'
if ($LASTEXITCODE -ne 0 -or -not "$endpoint".Trim().StartsWith('npipe://')) {
    throw 'Selecciona un contexto local de Docker Desktop.'
}
$osType = & $dockerPath --context $activeContext info --format '{{.OSType}}' 2>$null
if ($LASTEXITCODE -ne 0 -or "$osType".Trim() -ne 'linux') {
    throw 'Arranca Docker Desktop con contenedores Linux y vuelve a intentarlo.'
}
$composeArguments = @(
    '--context', $activeContext, 'compose', '--project-name', 'relay-local',
    '--project-directory', $repoRoot,
    '--env-file', (Join-Path $repoRoot 'docker/local.env'),
    '--file', (Join-Path $repoRoot 'compose.local.yml')
)
function Invoke-LocalCompose {
    param([string[]]$Arguments)
    & $dockerPath @composeArguments @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker Compose fallo con codigo $LASTEXITCODE." }
}

switch ($Task) {
    'stop' { Invoke-LocalCompose -Arguments @('down') }
    'logs' { Invoke-LocalCompose -Arguments @('logs', '--tail', '150', 'app', 'worker') }
    'start' {
        Invoke-LocalCompose -Arguments @('build', 'app')
        Invoke-LocalCompose -Arguments @('up', '--detach', '--wait', '--wait-timeout', '300')
        Write-Host 'Relay listo en http://localhost:3002. Los datos locales se conservan al detenerlo.'
        if (-not $NoBrowser) {
            $chromeCommand = Get-Command chrome -ErrorAction SilentlyContinue
            $chromePath = if ($chromeCommand) { $chromeCommand.Source } else { $null }
            if (-not $chromePath) {
                $chromeCandidates = @(
                    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
                    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
                    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
                )
                $chromePath = $chromeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            }
            if ($chromePath) { Start-Process -FilePath $chromePath -ArgumentList 'http://localhost:3002' }
            else { Start-Process 'http://localhost:3002' }
        }
    }
}
