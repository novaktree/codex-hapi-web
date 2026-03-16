param()

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
Import-ProjectDotEnv -ProjectRoot $root | Out-Null

$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
  throw "docker not found. Install Docker Desktop first."
}
$dockerCompose = Get-Command docker-compose -ErrorAction SilentlyContinue

Push-Location $root
try {
  if ($dockerCompose) {
    & $dockerCompose.Source -f .\docker-compose.voice-local.yml up -d --build
  } else {
    & docker compose -f .\docker-compose.voice-local.yml up -d --build
  }
  if ($LASTEXITCODE -ne 0) {
    throw "voice-local docker startup failed with exit code $LASTEXITCODE"
  }
} finally {
  Pop-Location
}
