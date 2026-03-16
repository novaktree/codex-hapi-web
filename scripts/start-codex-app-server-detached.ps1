param(
    [string]$ListenUrl = '',
    [string]$TaskName = 'CodexSharedAppServer',
    [int]$WaitSeconds = 8
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
Import-ProjectDotEnv -ProjectRoot $root | Out-Null

if (-not $ListenUrl) {
  $ListenUrl = $env:CODEX_APP_SERVER_URL
}
if (-not $ListenUrl) {
  $ListenUrl = 'ws://127.0.0.1:8766'
}
if (-not $PSBoundParameters.ContainsKey('TaskName') -and $env:CODEX_HAPI_APP_SERVER_TASK_NAME) {
  $TaskName = $env:CODEX_HAPI_APP_SERVER_TASK_NAME
}

$runtime = Join-Path $root '.runtime'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null

$out = Join-Path $runtime 'codex-app-server.log'
$err = Join-Path $runtime 'codex-app-server.err.log'
$runner = Join-Path $runtime 'run-codex-app-server.cmd'

$codexCommand = Get-Command codex.cmd -ErrorAction SilentlyContinue
if (-not $codexCommand) {
  $codexCommand = Get-Command codex -ErrorAction SilentlyContinue
}

$codexCmd = if ($codexCommand) {
  $codexCommand.Source
} else {
  Join-Path $env:APPDATA 'npm\codex.cmd'
}

if (-not (Test-Path $codexCmd)) {
  throw "codex command not found. Install Codex CLI first."
}

$listenUri = [Uri]($ListenUrl -replace '^ws://', 'http://' -replace '^wss://', 'https://')
$port = $listenUri.Port

$existing = Get-CimInstance Win32_Process | Where-Object {
  $_.CommandLine -match 'app-server' -and $_.CommandLine -match [regex]::Escape("$port")
}

foreach ($proc in $existing) {
  try {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
  } catch {}
}

@"
@echo off
cd /d "$root"
"$codexCmd" app-server --listen "$ListenUrl" 1>>"$out" 2>>"$err"
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

Set-Content -Path (Join-Path $runtime 'codex-app-server.url') -Value $ListenUrl -NoNewline -Encoding ascii
Set-Content -Path (Join-Path $runtime 'codex-app-server.mode') -Value 'managed' -NoNewline -Encoding ascii

Start-Sleep -Seconds $WaitSeconds

try {
  $tcp = Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { $_.LocalPort -eq $port } | Select-Object -First 1
  if ($tcp) {
    Set-Content -Path (Join-Path $runtime 'codex-app-server.pid') -Value ([string]$tcp.OwningProcess) -NoNewline -Encoding ascii
    "LISTENING pid=$($tcp.OwningProcess) url=$ListenUrl"
  } else {
    throw "Port $port is not listening yet"
  }
} catch {
  if (Test-Path $err) {
    Get-Content $err -Tail 80
  } else {
    throw
  }
}
