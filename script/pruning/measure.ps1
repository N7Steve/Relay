param([string]$OutputPath = 'tmp/pruning-phase-0/source-metrics.json')

$ErrorActionPreference = 'Stop'
$pruningRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $pruningRoot
try {
    $trackedPaths = @(git ls-files)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inventory Git files' }
    $areas = [ordered]@{}
    foreach ($prefix in @('app/', 'app/models/provider/', 'app/controllers/', 'app/jobs/', 'test/', 'mobile/', 'desktop/', 'bitrig/')) {
        $paths = @($trackedPaths | Where-Object { $_.StartsWith($prefix) })
        $textPaths = @($paths | Where-Object { [IO.Path]::GetExtension($_) -in @('.rb', '.erb', '.js', '.ts', '.css', '.dart', '.rs', '.swift', '.yml', '.yaml') })
        $lineCount = 0
        foreach ($path in $textPaths) { $lineCount += [IO.File]::ReadAllLines((Join-Path $pruningRoot $path)).Length }
        $areas[$prefix] = [ordered]@{ tracked_files = $paths.Count; selected_text_files = $textPaths.Count; selected_text_lines = $lineCount }
    }
    $gemfile = Get-Content -LiteralPath Gemfile
    $lockfile = Get-Content -LiteralPath Gemfile.lock
    $npm = Get-Content -LiteralPath package.json -Raw | ConvertFrom-Json
    $result = [ordered]@{
        revision = (git rev-parse HEAD).Trim()
        measured_at_utc = [DateTime]::UtcNow.ToString('o')
        method = 'Tracked files; physical lines in specified source extensions, including comments/blanks; overlapping areas must not be summed'
        areas = $areas
        gemfile_declarations = @($gemfile | Where-Object { $_ -match '^\s*gem\s+"' }).Count
        locked_ruby_specs = @($lockfile | Where-Object { $_ -match '^    [\w-]+ \(' }).Count
        npm_dependencies = $(if ($null -eq $npm.dependencies) { 0 } else { @($npm.dependencies.PSObject.Properties).Count })
        npm_dev_dependencies = $(if ($null -eq $npm.devDependencies) { 0 } else { @($npm.devDependencies.PSObject.Properties).Count })
        static_schedule_entries = @((Get-Content config/schedule.yml) | Where-Object { $_ -match '^[a-z_]+:$' }).Count
        active_workflow_files = @($trackedPaths | Where-Object { $_ -match '^\.github/workflows/.*\.ya?ml$' }).Count
        provider_adapters = @($trackedPaths | Where-Object { $_ -match '^app/models/provider/[^/]+_adapter\.rb$' }).Count
    }
    $absoluteOutput = [IO.Path]::GetFullPath((Join-Path $pruningRoot $OutputPath))
    New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteOutput) -Force | Out-Null
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $absoluteOutput -Encoding utf8
    Write-Output $absoluteOutput
} finally {
    Pop-Location
}
