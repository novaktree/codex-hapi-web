param(
    [int]$Port = 3113
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
Import-ProjectDotEnv -ProjectRoot $root | Out-Null

if (-not $PSBoundParameters.ContainsKey('Port') -and $env:CODEX_HAPI_PORT) {
  $Port = [int]$env:CODEX_HAPI_PORT
}

$runtime = Join-Path $root '.runtime'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null

$out = Join-Path $runtime "localtunnel-$Port.out.log"
$err = Join-Path $runtime "localtunnel-$Port.err.log"

$existing = Get-CimInstance Win32_Process | Where-Object {
  $_.CommandLine -match 'localtunnel' -and $_.CommandLine -match "--port $Port"
}

foreach ($proc in $existing) {
  try {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
  } catch {}
}

Start-Process -FilePath 'C:\Program Files\nodejs\npx.cmd' `
  -ArgumentList 'localtunnel', '--port', "$Port" `
  -WorkingDirectory $root `
  -RedirectStandardOutput $out `
  -RedirectStandardError $err

Start-Sleep -Seconds 10

if (Test-Path $out) {
  Get-Content $out -Tail 60
}

if (Test-Path $err) {
  Get-Content $err -Tail 60
}
