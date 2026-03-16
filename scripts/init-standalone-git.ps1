param(
    [string]$DefaultBranch = 'main',
    [string]$CommitMessage = 'Initial public release',
    [string]$RemoteUrl = '',
    [string]$GitUserName = '',
    [string]$GitUserEmail = '',
    [switch]$Push
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Get-GitValue {
    param([string]$Key)

    $local = (& git config --local --get $Key 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($local)) {
        return $local.Trim()
    }

    $global = (& git config --global --get $Key 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($global)) {
        return $global.Trim()
    }

    return ''
}

$gitName = $GitUserName
$gitEmail = $GitUserEmail

if ($gitName) {
    & git config --local user.name $gitName
}
if ($gitEmail) {
    & git config --local user.email $gitEmail
}

if (-not $gitName) {
    $gitName = Get-GitValue -Key 'user.name'
}
if (-not $gitEmail) {
    $gitEmail = Get-GitValue -Key 'user.email'
}

if (-not $gitName -or -not $gitEmail) {
    throw @"
Git identity is not configured.

Run these commands first:
git config --global user.name "Your GitHub Name"
git config --global user.email "you@example.com"

Or run this script with:
-GitUserName "Your GitHub Name" -GitUserEmail "you@example.com"
"@
}

$gitDir = Join-Path $root '.git'
if (-not (Test-Path $gitDir)) {
    & git init -b $DefaultBranch | Out-Null
    Write-Host "Initialized standalone Git repository on branch '$DefaultBranch'."
} else {
    Write-Host "Git repository already exists in this directory."
}

$currentBranch = (& git branch --show-current).Trim()
if (-not $currentBranch) {
    & git checkout -B $DefaultBranch | Out-Null
    $currentBranch = $DefaultBranch
}

& git add .

$hasHead = $true
& git rev-parse --verify HEAD *> $null
if ($LASTEXITCODE -ne 0) {
    $hasHead = $false
}

if (-not $hasHead) {
    & git commit -m $CommitMessage | Out-Null
    Write-Host "Created initial commit."
} else {
    $status = (& git status --short)
    if ($status) {
        & git commit -m $CommitMessage | Out-Null
        Write-Host "Created new commit with current changes."
    } else {
        Write-Host "Working tree is clean. No new commit created."
    }
}

if ($RemoteUrl) {
    $hasOrigin = $true
    & git remote get-url origin *> $null
    if ($LASTEXITCODE -ne 0) {
        $hasOrigin = $false
    }

    if ($hasOrigin) {
        & git remote set-url origin $RemoteUrl
        Write-Host "Updated remote 'origin' to $RemoteUrl"
    } else {
        & git remote add origin $RemoteUrl
        Write-Host "Added remote 'origin' -> $RemoteUrl"
    }
}

if ($Push) {
    if (-not $RemoteUrl) {
        $originUrl = (& git remote get-url origin 2>$null)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($originUrl)) {
            throw "Push requested, but no remote origin is configured. Pass -RemoteUrl first."
        }
    }

    & git push -u origin $currentBranch
}

Write-Host ""
Write-Host "Repository root: $root"
Write-Host "Current branch: $currentBranch"
Write-Host "Next command:"
if ($RemoteUrl) {
    Write-Host "git push -u origin $currentBranch"
} else {
    Write-Host "powershell -ExecutionPolicy Bypass -File .\\scripts\\init-standalone-git.ps1 -RemoteUrl https://github.com/<your-name>/codex-hapi-web.git"
}
