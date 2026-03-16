param(
    [int]$Port = 3113,
    [string]$AppServerListenUrl = '',
    [string]$BackendTaskName = '',
    [string]$AppServerTaskName = '',
    [switch]$SkipVoiceLocal
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
Import-ProjectDotEnv -ProjectRoot $root | Out-Null

if (-not $PSBoundParameters.ContainsKey('Port') -and $env:CODEX_HAPI_PORT) {
  $Port = [int]$env:CODEX_HAPI_PORT
}
if (-not $AppServerListenUrl -and $env:CODEX_APP_SERVER_URL) {
  $AppServerListenUrl = $env:CODEX_APP_SERVER_URL
}
if (-not $BackendTaskName -and $env:CODEX_HAPI_BACKEND_TASK_NAME) {
  $BackendTaskName = $env:CODEX_HAPI_BACKEND_TASK_NAME
}
if (-not $AppServerTaskName -and $env:CODEX_HAPI_APP_SERVER_TASK_NAME) {
  $AppServerTaskName = $env:CODEX_HAPI_APP_SERVER_TASK_NAME
}
if ($AppServerListenUrl) {
  [Environment]::SetEnvironmentVariable('CODEX_APP_SERVER_URL', $AppServerListenUrl, 'Process')
}
if ($BackendTaskName) {
  [Environment]::SetEnvironmentVariable('CODEX_HAPI_BACKEND_TASK_NAME', $BackendTaskName, 'Process')
}
if ($AppServerTaskName) {
  [Environment]::SetEnvironmentVariable('CODEX_HAPI_APP_SERVER_TASK_NAME', $AppServerTaskName, 'Process')
}

$voiceBackend = if ($env:CODEX_HAPI_VOICE_BACKEND) {
  $env:CODEX_HAPI_VOICE_BACKEND.ToLowerInvariant()
} else {
  'local'
}

Write-Host "==> Starting shared Codex app-server"
& (Join-Path $PSScriptRoot 'start-codex-app-server-detached.ps1') `
  -ListenUrl $AppServerListenUrl `
  -TaskName $(if ($AppServerTaskName) { $AppServerTaskName } else { 'CodexSharedAppServer' })

if (-not $SkipVoiceLocal -and $voiceBackend -eq 'local') {
  $docker = Get-Command docker -ErrorAction SilentlyContinue
  if ($docker) {
    Write-Host "==> Starting local voice backend via Docker"
    & (Join-Path $PSScriptRoot 'start-voice-local-docker.ps1')
  } else {
    Write-Host "==> Docker not found. Skipping local voice backend startup."
  }
}

Write-Host "==> Starting web backend on port $Port"
& (Join-Path $PSScriptRoot 'start-backend-detached.ps1') `
  -Port $Port `
  -TaskName $(if ($BackendTaskName) { $BackendTaskName } else { 'CodexHapiBackend' })

Write-Host "==> Local URL"
Write-Host "http://127.0.0.1:$Port"

$tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
if ($tailscale) {
  try {
    $tailscaleUrl = & (Join-Path $PSScriptRoot 'show-tailscale-url.ps1') -Port $Port
    Write-Host "==> Tailscale URL"
    Write-Host $tailscaleUrl
  } catch {}
}
