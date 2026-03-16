param(
    [int]$Port = 0,
    [string]$AppServerListenUrl = '',
    [string]$BackendTaskName = '',
    [string]$AppServerTaskName = '',
    [switch]$SkipVoiceLocal,
    [switch]$ForceNpmInstall,
    [switch]$ForceFrontendBuild
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
Import-ProjectDotEnv -ProjectRoot $root | Out-Null

Write-Host "==> Bootstrapping project"
& (Join-Path $PSScriptRoot 'bootstrap.ps1') `
  -ForceNpmInstall:$ForceNpmInstall `
  -ForceFrontendBuild:$ForceFrontendBuild

Write-Host "==> Starting stack"
$startStackArgs = @{}
if ($PSBoundParameters.ContainsKey('Port') -and $Port -gt 0) {
  $startStackArgs.Port = $Port
}
if ($PSBoundParameters.ContainsKey('AppServerListenUrl') -and $AppServerListenUrl) {
  $startStackArgs.AppServerListenUrl = $AppServerListenUrl
}
if ($PSBoundParameters.ContainsKey('BackendTaskName') -and $BackendTaskName) {
  $startStackArgs.BackendTaskName = $BackendTaskName
}
if ($PSBoundParameters.ContainsKey('AppServerTaskName') -and $AppServerTaskName) {
  $startStackArgs.AppServerTaskName = $AppServerTaskName
}
if ($SkipVoiceLocal) {
  $startStackArgs.SkipVoiceLocal = $true
}

& (Join-Path $PSScriptRoot 'start-stack.ps1') @startStackArgs
