param(
    [int]$Port = 3113,
    [string]$BindHost = '0.0.0.0',
    [string]$TaskName = 'CodexHapiBackend',
    [int]$WaitSeconds = 8
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
if (-not $PSBoundParameters.ContainsKey('TaskName') -and $env:CODEX_HAPI_BACKEND_TASK_NAME) {
  $TaskName = $env:CODEX_HAPI_BACKEND_TASK_NAME
}

$backend = Join-Path $root 'backend'
$runtime = Join-Path $root '.runtime'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null

$out = Join-Path $runtime "backend-$Port.out.log"
$err = Join-Path $runtime "backend-$Port.err.log"
$runner = Join-Path $runtime "run-backend-$Port.cmd"

$portPattern = "(^|\s)--port\s+$Port(\s|$)"
$existing = Get-CimInstance Win32_Process | Where-Object {
  $_.ProcessId -ne $PID -and
  $_.CommandLine -match 'app\.main:app' -and
  $_.CommandLine -match $portPattern
}

foreach ($proc in $existing) {
  try {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
  } catch {}
}

$envNames = @(
  'CODEX_HAPI_HOST',
  'CODEX_HAPI_PORT',
  'CODEX_APP_SERVER_URL',
  'CODEX_HOME',
  'CODEX_HAPI_VOICE_BACKEND',
  'CODEX_HAPI_LOCAL_TRANSCRIPTION_URL',
  'CODEX_HAPI_DESKTOP_REFRESH_SCRIPT',
  'OPENAI_API_KEY',
  'OPENAI_TRANSCRIPTION_MODEL'
)

$envLines = foreach ($name in $envNames) {
  $value = [Environment]::GetEnvironmentVariable($name, 'Process')
  if (-not [string]::IsNullOrWhiteSpace($value)) {
    $escaped = $value -replace '"', '""'
    "set `"$name=$escaped`""
  }
}

$envBlock = if ($envLines) { ($envLines -join "`r`n") + "`r`n" } else { '' }

@"
@echo off
cd /d "$backend"
$envBlock
uv run --with fastapi --with uvicorn --with websockets --with httpx --with python-multipart uvicorn app.main:app --host $BindHost --port $Port 1>>"$out" 2>>"$err"
"@ | Set-Content -Path $runner -Encoding ascii

$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false | Out-Null
}

$startTime = (Get-Date).AddMinutes(1).ToString('HH:mm')
$createArgs = @(
  '/Create'
  '/TN', $TaskName
  '/SC', 'ONCE'
  '/ST', $startTime
  '/RL', 'LIMITED'
  '/F'
  '/TR', "cmd.exe /c `"$runner`""
)

& schtasks @createArgs | Out-Null
& schtasks /Run /TN $TaskName | Out-Null

Start-Sleep -Seconds $WaitSeconds

try {
  (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$Port/health" -TimeoutSec 5).Content
} catch {
  if (Test-Path $err) {
    Get-Content $err -Tail 60
  } else {
    throw
  }
}
