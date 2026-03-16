param(
    [int]$Port = 3113,
    [string]$BindHost = '0.0.0.0'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
Import-ProjectDotEnv -ProjectRoot $root | Out-Null

if (-not $PSBoundParameters.ContainsKey('Port') -and $env:CODEX_HAPI_PORT) {
  $Port = [int]$env:CODEX_HAPI_PORT
}
if (-not $PSBoundParameters.ContainsKey('BindHost') -and $env:CODEX_HAPI_HOST) {
  $BindHost = $env:CODEX_HAPI_HOST
}

Set-Location (Join-Path $root 'backend')
uv run --with fastapi --with uvicorn --with websockets --with httpx --with python-multipart `
  uvicorn app.main:app --host $BindHost --port $Port
