param(
    [switch]$ForceNpmInstall,
    [switch]$ForceFrontendBuild
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
Import-ProjectDotEnv -ProjectRoot $root | Out-Null

$frontend = Join-Path $root 'frontend'
$envExample = Join-Path $root '.env.example'
$envFile = Join-Path $root '.env'

if (-not (Test-Path $envFile) -and (Test-Path $envExample)) {
  Copy-Item $envExample $envFile
  Write-Host "Created .env from .env.example"
}

$node = Get-Command node -ErrorAction SilentlyContinue
$npm = Get-Command npm -ErrorAction SilentlyContinue
$uv = Get-Command uv -ErrorAction SilentlyContinue
$codexCmd = Get-Command codex.cmd -ErrorAction SilentlyContinue
if (-not $codexCmd) {
  $codexCmd = Get-Command codex -ErrorAction SilentlyContinue
}

if (-not $node -or -not $npm) {
  throw "Node.js and npm are required."
}
if (-not $uv) {
  throw "uv is required."
}
if (-not $codexCmd) {
  throw "Codex CLI is required."
}

$nodeModules = Join-Path $frontend 'node_modules'
$distIndex = Join-Path $frontend 'dist\index.html'
$packageLock = Join-Path $frontend 'package-lock.json'

$shouldInstall = $ForceNpmInstall -or -not (Test-Path $nodeModules)
$shouldBuild = $ForceFrontendBuild -or -not (Test-Path $distIndex)

if (-not $shouldBuild -and (Test-Path $distIndex)) {
  $latestSource = Get-ChildItem -Path (Join-Path $frontend 'src') -Recurse -File |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
  $latestConfig = @(
    Get-Item $packageLock -ErrorAction SilentlyContinue
    Get-Item (Join-Path $frontend 'package.json') -ErrorAction SilentlyContinue
    Get-Item (Join-Path $frontend 'vite.config.js') -ErrorAction SilentlyContinue
    $latestSource
  ) | Where-Object { $_ } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1

  if ($latestConfig -and $latestConfig.LastWriteTimeUtc -gt (Get-Item $distIndex).LastWriteTimeUtc) {
    $shouldBuild = $true
  }
}

Push-Location $frontend
try {
  if ($shouldInstall) {
    Write-Host "==> Installing frontend dependencies"
    & npm install
    if ($LASTEXITCODE -ne 0) {
      throw "npm install failed with exit code $LASTEXITCODE"
    }
  } else {
    Write-Host "==> Frontend dependencies already present"
  }

  if ($shouldBuild) {
    Write-Host "==> Building frontend"
    & npm run build
    if ($LASTEXITCODE -ne 0) {
      throw "npm run build failed with exit code $LASTEXITCODE"
    }
  } else {
    Write-Host "==> Frontend build already up to date"
  }
} finally {
  Pop-Location
}

Write-Host "Bootstrap finished."
