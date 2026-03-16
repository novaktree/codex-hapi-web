param(
    [int]$Port = 3113,
    [string]$AppServerListenUrl = '',
    [string]$BackendTaskName = '',
    [string]$AppServerTaskName = '',
    [switch]$StopVoiceLocal
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
Import-ProjectDotEnv -ProjectRoot $root | Out-Null

if (-not $PSBoundParameters.ContainsKey('Port') -and $env:CODEX_HAPI_PORT) {
  $Port = [int]$env:CODEX_HAPI_PORT
}
if (-not $BackendTaskName -and $env:CODEX_HAPI_BACKEND_TASK_NAME) {
  $BackendTaskName = $env:CODEX_HAPI_BACKEND_TASK_NAME
}
if (-not $AppServerTaskName -and $env:CODEX_HAPI_APP_SERVER_TASK_NAME) {
  $AppServerTaskName = $env:CODEX_HAPI_APP_SERVER_TASK_NAME
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

$backend = Get-CimInstance Win32_Process | Where-Object {
  $_.CommandLine -match 'app\.main:app' -and $_.CommandLine -match "(^|\s)--port\s+$Port(\s|$)"
}
foreach ($proc in $backend) {
  try {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
  } catch {}
}

$appServer = Get-CimInstance Win32_Process | Where-Object {
  $_.CommandLine -match 'app-server' -and $_.CommandLine -match [regex]::Escape("$($listenUri.Port)")
}
foreach ($proc in $appServer) {
  try {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
  } catch {}
}

foreach ($taskName in @(
  $(if ($BackendTaskName) { $BackendTaskName } else { 'CodexHapiBackend' }),
  $(if ($AppServerTaskName) { $AppServerTaskName } else { 'CodexSharedAppServer' })
)) {
  $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null
  }
}

if ($StopVoiceLocal) {
  $docker = Get-Command docker -ErrorAction SilentlyContinue
  $dockerCompose = Get-Command docker-compose -ErrorAction SilentlyContinue
  if ($docker) {
    Push-Location $root
    try {
      if ($dockerCompose) {
        & $dockerCompose.Source -f .\docker-compose.voice-local.yml down
      } else {
        & docker compose -f .\docker-compose.voice-local.yml down
      }
      if ($LASTEXITCODE -ne 0) {
        throw "voice-local docker shutdown failed with exit code $LASTEXITCODE"
      }
    } finally {
      Pop-Location
    }
  }
}

Write-Host "Stopped backend and shared Codex app-server."
