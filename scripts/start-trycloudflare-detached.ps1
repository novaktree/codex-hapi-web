param(
    [int]$Port = 3113,
    [string]$TaskName = 'CodexTryCloudflare',
    [int]$WaitSeconds = 12
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
Import-ProjectDotEnv -ProjectRoot $root | Out-Null

if (-not $PSBoundParameters.ContainsKey('Port') -and $env:CODEX_HAPI_PORT) {
  $Port = [int]$env:CODEX_HAPI_PORT
}

$runtime = Join-Path $root '.runtime'
$quickRuntime = Join-Path $runtime 'cloudflare-quick'
New-Item -ItemType Directory -Force -Path $quickRuntime | Out-Null

$out = Join-Path $quickRuntime "trycloudflare-$Port.out.log"
$err = Join-Path $quickRuntime "trycloudflare-$Port.err.log"
$runner = Join-Path $quickRuntime "run-trycloudflare-$Port.cmd"

$cloudflaredPath = $null
$command = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($command) {
  $cloudflaredPath = $command.Source
}
if (-not $cloudflaredPath) {
  $fallbacks = @(
    'C:\Program Files\cloudflared\cloudflared.exe',
    'C:\Program Files (x86)\cloudflared\cloudflared.exe',
    "$env:ProgramFiles\Cloudflare\Cloudflared\cloudflared.exe"
  )
  $cloudflaredPath = $fallbacks | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $cloudflaredPath) {
  throw "cloudflared not found. Run .\\scripts\\install-cloudflared.ps1 first."
}

$existing = Get-CimInstance Win32_Process | Where-Object {
  $_.Name -match '^cloudflared(\.exe)?$' -and (
    $_.CommandLine -match 'trycloudflare\.com' -or
    $_.CommandLine -match "tunnel --url http://127.0.0.1:$Port" -or
    $_.CommandLine -match "tunnel --url http://localhost:$Port"
  )
}

foreach ($proc in $existing) {
  try {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
  } catch {}
}

@"
@echo off
cd /d "$root"
"$cloudflaredPath" tunnel --no-autoupdate --url http://127.0.0.1:$Port 1>>"$out" 2>>"$err"
"@ | Set-Content -Path $runner -Encoding ascii

try {
  schtasks /Delete /TN $TaskName /F | Out-Null
} catch {}

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

if (Test-Path $err) {
  Get-Content $err -Tail 120
}

if (Test-Path $out) {
  Get-Content $out -Tail 40
}
