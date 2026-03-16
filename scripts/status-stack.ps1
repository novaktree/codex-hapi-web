param(
    [int]$Port = 3113,
    [string]$AppServerListenUrl = ''
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
Import-ProjectDotEnv -ProjectRoot $root | Out-Null

if (-not $PSBoundParameters.ContainsKey('Port') -and $env:CODEX_HAPI_PORT) {
  $Port = [int]$env:CODEX_HAPI_PORT
}

$runtimeUrlFile = Join-Path $root '.runtime\codex-app-server.url'
$listenUrl = $AppServerListenUrl
if (-not $listenUrl -and $env:CODEX_APP_SERVER_URL) {
  $listenUrl = $env:CODEX_APP_SERVER_URL
}
if (-not $listenUrl -and (Test-Path $runtimeUrlFile)) {
  $listenUrl = (Get-Content -Raw $runtimeUrlFile).Trim()
}
if (-not $listenUrl) {
  $listenUrl = 'ws://127.0.0.1:8766'
}
$listenUri = [Uri]($listenUrl -replace '^ws://', 'http://' -replace '^wss://', 'https://')

Write-Host "==> Backend health"
try {
  (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$Port/health" -TimeoutSec 5).Content
} catch {
  Write-Host $_.Exception.Message
}

Write-Host ""
Write-Host "==> Codex app-server listener"
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
  Where-Object { $_.LocalPort -eq $listenUri.Port } |
  Select-Object LocalAddress,LocalPort,OwningProcess |
  Format-Table -AutoSize

$tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
if ($tailscale) {
  try {
    Write-Host ""
    Write-Host "==> Tailscale URL"
    & (Join-Path $PSScriptRoot 'show-tailscale-url.ps1') -Port $Port
  } catch {}
}
