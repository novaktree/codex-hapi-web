param(
    [string]$ThreadId,
    [string]$ThreadTitle = '',
    [switch]$ProbeOnly
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

$win32Signature = @'
using System;
using System.Runtime.InteropServices;
public static class CodexWin32 {
  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

  [DllImport("user32.dll")]
  public static extern bool SetCursorPos(int x, int y);

  [DllImport("user32.dll")]
  public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();

  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
'@
Add-Type $win32Signature

function New-Text {
    param([int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

$LabelSettings = New-Text 0x8BBE, 0x7F6E
$LabelBackToApp = New-Text 0x8FD4, 0x56DE, 0x5E94, 0x7528
$LabelOpenArchivedThreads = New-Text 0x6253, 0x5F00, 0x5DF2, 0x5F52, 0x6863, 0x7EBF, 0x7A0B
$LabelArchivedThreads = New-Text 0x5DF2, 0x5F52, 0x6863, 0x7EBF, 0x7A0B
$LabelUnarchive = New-Text 0x53D6, 0x6D88, 0x5F52, 0x6863
$LabelRemoveFromArchive = New-Text 0x4ECE, 0x5F52, 0x6863, 0x4E2D, 0x79FB, 0x9664
$LabelViewNow = New-Text 0x73B0, 0x5728, 0x67E5, 0x770B
$LabelViewImmediately = New-Text 0x7ACB, 0x5373, 0x67E5, 0x770B
$LabelArchive = New-Text 0x5F52, 0x6863
$LabelCancel = New-Text 0x53D6, 0x6D88
$LabelArchiveQuestion = New-Text 0x5F52, 0x6863, 0x7EBF, 0x7A0B, 0x003F

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

function Normalize-UiText {
    param([string]$Text)

    $safeText = if ($null -eq $Text) { '' } else { [string]$Text }
    return ([regex]::Replace($safeText, '\s+', ' ')).Trim()
}

function Get-ThreadTextCandidates {
    param([string]$Title)

    $items = @()
    $normalized = Normalize-UiText $Title
    if ($normalized.Length -ge 4 -and -not ($items -contains $normalized)) {
        $items += $normalized
    }
    return $items
}

function Get-CodexSessionRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        return Join-Path $env:CODEX_HOME 'sessions'
    }

    return Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\sessions'
}

function Extract-FirstUserMessageTitle {
    param([string]$SessionFile)

    foreach ($line in Get-Content $SessionFile -ErrorAction SilentlyContinue) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $record = $line | ConvertFrom-Json -Depth 20
        } catch {
            continue
        }

        if ($record.type -ne 'response_item') {
            continue
        }

        $payload = $record.payload
        if (-not $payload -or $payload.type -ne 'message' -or $payload.role -ne 'user') {
            continue
        }

        $texts = @()
        foreach ($part in @($payload.content)) {
            if ($null -ne $part.text -and -not [string]::IsNullOrWhiteSpace([string]$part.text)) {
                $texts += [string]$part.text
                continue
            }
            if ($null -ne $part.content -and -not [string]::IsNullOrWhiteSpace([string]$part.content)) {
                $texts += [string]$part.content
            }
        }

        $joined = ($texts -join "`n").Trim()
        if (-not $joined) {
            continue
        }
        if ($joined.StartsWith('# AGENTS.md instructions for ') -or $joined.Contains('<environment_context>')) {
            continue
        }

        $firstLine = (($joined -split "`r?`n")[0]).Trim()
        if ($firstLine.Length -gt 72) {
            $firstLine = $firstLine.Substring(0, 72).Trim()
        }
        return $firstLine
    }

    return ''
}

function Resolve-ThreadTitle {
    param(
        [string]$Id,
        [string]$ExplicitTitle
    )

    $normalizedExplicit = Normalize-UiText $ExplicitTitle
    if (-not [string]::IsNullOrWhiteSpace($normalizedExplicit)) {
        return $normalizedExplicit
    }

    if ([string]::IsNullOrWhiteSpace($Id)) {
        return ''
    }

    $sessionRoot = Get-CodexSessionRoot
    if (-not (Test-Path $sessionRoot)) {
        return ''
    }

    $sessionFile = Get-ChildItem -Path $sessionRoot -Filter "*$Id*.jsonl" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $sessionFile) {
        return ''
    }

    return Normalize-UiText (Extract-FirstUserMessageTitle -SessionFile $sessionFile.FullName)
}

function Get-CodexGuiPath {
    $path = Get-Process -Name Codex -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Path -and
            $_.Path -match 'OpenAI\.Codex' -and
            [System.IO.Path]::GetFileName($_.Path) -ceq 'Codex.exe'
        } |
        Select-Object -ExpandProperty Path -Unique |
        Select-Object -First 1

    if ($path) {
        return $path
    }

    $package = Get-AppxPackage OpenAI.Codex -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($package) {
        $candidate = Join-Path $package.InstallLocation 'app\Codex.exe'
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "Could not resolve Codex desktop GUI executable path."
}

function Get-ForegroundProcessId {
    $handle = [CodexWin32]::GetForegroundWindow()
    if ($handle -eq [IntPtr]::Zero) {
        return $null
    }

    [uint32]$processId = 0
    [void][CodexWin32]::GetWindowThreadProcessId($handle, [ref]$processId)
    if ($processId -le 0) {
        return $null
    }

    return [int]$processId
}

function Get-CodexWindowProcess {
    param(
        [switch]$PreferForeground,
        [switch]$PreferNewest
    )

    $candidates = @(Get-Process Codex -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 })

    if (-not $candidates) {
        throw "Could not find a visible Codex desktop window."
    }

    if ($PreferForeground) {
        $foregroundId = Get-ForegroundProcessId
        if ($foregroundId) {
            $foreground = $candidates | Where-Object { $_.Id -eq $foregroundId } | Select-Object -First 1
            if ($foreground) {
                return $foreground
            }
        }
    }

    if ($PreferNewest) {
        return $candidates | Sort-Object StartTime -Descending | Select-Object -First 1
    }

    return $candidates | Sort-Object StartTime | Select-Object -First 1
}

function Get-CodexWindowCandidates {
    return @(Get-Process Codex -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Sort-Object StartTime -Descending)
}

function Refresh-CodexWindow {
    param(
        [ref]$Process,
        [switch]$PreferForeground,
        [switch]$PreferNewest
    )

    Start-Sleep -Milliseconds 800
    $Process.Value = Get-CodexWindowProcess -PreferForeground:$PreferForeground -PreferNewest:$PreferNewest
    Write-Step "Reattached to Codex PID $($Process.Value.Id)"
    Focus-CodexWindow -Process $Process.Value
}

function Get-CurrentThreadId {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutMs = 3000
    )

    Focus-CodexWindow -Process $Process

    $previousClipboard = $null
    $hadClipboard = $false
    try {
        $previousClipboard = Get-Clipboard -Raw -ErrorAction Stop
        $hadClipboard = $true
    } catch {}

    $sentinel = "__CODEX_THREAD_DEEPLINK__$([guid]::NewGuid())"
    Set-Clipboard -Value $sentinel

    [System.Windows.Forms.SendKeys]::SendWait("^%l")
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $captured = ''

    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        try {
            $clipboardText = Get-Clipboard -Raw -ErrorAction Stop
        } catch {
            $clipboardText = ''
        }

        if (-not [string]::IsNullOrWhiteSpace($clipboardText) -and $clipboardText -ne $sentinel) {
            $match = [regex]::Match($clipboardText, 'codex://threads/([0-9a-fA-F-]{36})')
            if ($match.Success) {
                $captured = $match.Groups[1].Value
                break
            }
        }
    }

    if ($hadClipboard) {
        Set-Clipboard -Value $previousClipboard
    } else {
        Set-Clipboard -Value ''
    }

    if (-not $captured) {
        throw "Could not read the current Codex desktop thread id from the copy-deeplink shortcut."
    }

    return $captured
}

function Assert-ThreadIdActive {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$ExpectedThreadId
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedThreadId)) {
        return
    }

    $currentThreadId = Get-CurrentThreadId -Process $Process
    if ($currentThreadId -ne $ExpectedThreadId) {
        throw "Codex desktop is currently on thread '$currentThreadId', not the requested thread '$ExpectedThreadId'. Refusing to archive the wrong thread."
    }
}

function Open-ThreadByDeepLink {
    param(
        [string]$Id,
        [ref]$Process,
        [string[]]$ThreadTexts = @()
    )

    if ([string]::IsNullOrWhiteSpace($Id)) {
        return
    }

    if ($Id -notmatch '^[0-9a-fA-F-]{36}$') {
        throw "ThreadId does not look valid: $Id"
    }

    $arg = "codex://threads/$Id"
    try {
        $currentThreadId = Get-CurrentThreadId -Process $Process.Value -TimeoutMs 2000
        if ($currentThreadId -eq $Id) {
            Write-Step "Target thread is already active in Codex desktop."
            return
        }
        Write-Step "Current desktop thread is $currentThreadId; switching to $Id"
    } catch {
        Write-Step "Could not read current desktop thread before switch: $($_.Exception.Message)"
    }

    $codexGui = Get-CodexGuiPath
    Write-Step "Opening thread via Codex desktop executable: $Id"
    try {
        Start-Process -FilePath $codexGui -ArgumentList $arg | Out-Null
    } catch {
        throw "Could not open Codex thread through the desktop executable. $($_.Exception.Message)"
    }

    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        Start-Sleep -Milliseconds 700
        Refresh-CodexWindow -Process $Process -PreferForeground -PreferNewest
        try {
            $currentThreadId = Get-CurrentThreadId -Process $Process.Value -TimeoutMs 2000
            if ($currentThreadId -eq $Id) {
                Write-Step "Desktop switched to target thread $Id"
                return
            }
            Write-Step "Desktop still reports thread $currentThreadId; waiting for $Id"
        } catch {
            Write-Step "Waiting for thread switch: $($_.Exception.Message)"
        }
    }

    throw "Codex desktop did not switch to thread '$Id'. Refusing to archive the current desktop page."
}

function Focus-CodexWindow {
    param([System.Diagnostics.Process]$Process)

    [CodexWin32]::ShowWindowAsync($Process.MainWindowHandle, 5) | Out-Null
    Start-Sleep -Milliseconds 150
    [CodexWin32]::SetForegroundWindow($Process.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 400
}

function Click-WindowCenter {
    param([System.Diagnostics.Process]$Process)

    $root = Get-RootElement -Process $Process
    $rect = $root.Current.BoundingRectangle
    if ($rect.Width -le 1 -or $rect.Height -le 1) {
        return
    }

    $x = [int]($rect.Left + ($rect.Width / 2))
    $y = [int]($rect.Top + ([Math]::Min($rect.Height * 0.35, $rect.Height - 10)))
    [CodexWin32]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 120
    [CodexWin32]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [CodexWin32]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 250
}

function Get-RootElement {
    param([System.Diagnostics.Process]$Process)

    return [System.Windows.Automation.AutomationElement]::FromHandle($Process.MainWindowHandle)
}

function Get-VisibleNamedElements {
    param([System.Windows.Automation.AutomationElement]$Root)

    $all = $Root.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition
    )

    $result = @()
    for ($i = 0; $i -lt $all.Count; $i++) {
        $item = $all.Item($i)
        $name = $item.Current.Name
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $rect = $item.Current.BoundingRectangle
        if ($rect.Width -le 1 -or $rect.Height -le 1) {
            continue
        }

        $result += $item
    }

    return $result
}

function Test-RootContainsThreadTexts {
    param(
        [System.Windows.Automation.AutomationElement]$Root,
        [string[]]$ThreadTexts
    )

    if (-not $ThreadTexts -or $ThreadTexts.Count -eq 0) {
        return $true
    }

    foreach ($element in Get-VisibleNamedElements -Root $Root) {
        $name = Normalize-UiText $element.Current.Name
        if (-not $name) {
            continue
        }
        foreach ($threadText in $ThreadTexts) {
            if (-not $threadText) {
                continue
            }
            if ($name -eq $threadText) {
                return $true
            }
            if ($threadText.Length -ge 8 -and ($name.Contains($threadText) -or $threadText.Contains($name))) {
                return $true
            }
        }
    }

    return $false
}

function Find-CodexWindowForThreadTexts {
    param(
        [string[]]$ThreadTexts,
        [int]$Attempts = 10,
        [int]$SleepMilliseconds = 500
    )

    if (-not $ThreadTexts -or $ThreadTexts.Count -eq 0) {
        return $null
    }

    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        foreach ($candidate in Get-CodexWindowCandidates) {
            try {
                $root = Get-RootElement -Process $candidate
                if ($root -and (Test-RootContainsThreadTexts -Root $root -ThreadTexts $ThreadTexts)) {
                    return $candidate
                }
            } catch {}
        }
        Start-Sleep -Milliseconds $SleepMilliseconds
    }

    return $null
}

function Assert-ThreadIsVisible {
    param(
        [System.Diagnostics.Process]$Process,
        [string[]]$ThreadTexts
    )

    if (-not $ThreadTexts -or $ThreadTexts.Count -eq 0) {
        return
    }

    $root = Get-RootElement -Process $Process
    if (-not (Test-RootContainsThreadTexts -Root $root -ThreadTexts $ThreadTexts)) {
        Dump-Candidates -Root $root -Pattern ".*"
        throw "Target thread '$($ThreadTexts[0])' is not active in the current Codex window. Refusing to archive the wrong thread."
    }
}

function Find-FirstElement {
    param(
        [System.Windows.Automation.AutomationElement]$Root,
        [string[]]$Names,
        [string[]]$ControlTypes = @()
    )

    $elements = Get-VisibleNamedElements -Root $Root |
        Where-Object {
            $nameMatch = $false
            foreach ($candidate in $Names) {
                if ($_.Current.Name -eq $candidate) {
                    $nameMatch = $true
                    break
                }
            }

            if (-not $nameMatch) {
                return $false
            }

            if (-not $ControlTypes -or $ControlTypes.Count -eq 0) {
                return $true
            }

            return $ControlTypes -contains $_.Current.ControlType.ProgrammaticName
        } |
        Sort-Object {
            $_.Current.BoundingRectangle.Top
        }, {
            $_.Current.BoundingRectangle.Left
        }

    return $elements | Select-Object -First 1
}

function Dump-Candidates {
    param(
        [System.Windows.Automation.AutomationElement]$Root,
        [string]$Pattern = "Settings|Open|Archive|Unarchive|View now|Back to app"
    )

    Write-Host "---- Visible matching controls ----"
    Get-VisibleNamedElements -Root $Root |
        Where-Object {
            $_.Current.Name -match $Pattern
        } |
        Sort-Object {
            $_.Current.BoundingRectangle.Top
        }, {
            $_.Current.BoundingRectangle.Left
        } |
        Select-Object -First 120 |
        ForEach-Object {
            $rect = $_.Current.BoundingRectangle
            "{0} | {1} | {2} | top={3:n0} left={4:n0}" -f `
                $_.Current.ControlType.ProgrammaticName, `
                $_.Current.Name, `
                $_.Current.AutomationId, `
                $rect.Top, `
                $rect.Left
        }
    Write-Host "-----------------------------------"
}

function Invoke-OrClick {
    param([System.Windows.Automation.AutomationElement]$Element)

    $invokePattern = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$invokePattern)) {
        $invokePattern.Invoke()
        return
    }

    $rect = $Element.Current.BoundingRectangle
    $x = [int]($rect.Left + ($rect.Width / 2))
    $y = [int]($rect.Top + ($rect.Height / 2))

    [CodexWin32]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 120
    [CodexWin32]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [CodexWin32]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

function Click-NamedElement {
    param(
        [System.Windows.Automation.AutomationElement]$Root,
        [string[]]$Names,
        [string[]]$ControlTypes = @(),
        [string]$What
    )

    $element = Find-FirstElement -Root $Root -Names $Names -ControlTypes $ControlTypes
    if (-not $element) {
        Write-Step "Could not find $What."
        Dump-Candidates -Root $Root
        throw "Missing control: $What"
    }

    Write-Step "Clicking ${What}: $($element.Current.Name)"
    Invoke-OrClick -Element $element
    return $element
}

function Send-ArchiveShortcut {
    Write-Step "Sending Ctrl+Shift+A to archive the current thread"
    [System.Windows.Forms.SendKeys]::SendWait("^+a")
}

function Open-SettingsView {
    param([System.Diagnostics.Process]$Process)

    Write-Step "Sending Ctrl+, to open settings"
    [System.Windows.Forms.SendKeys]::SendWait("^{,}")
    Start-Sleep -Seconds 2

    $root = Get-RootElement -Process $Process
    $archivedEntry = Find-FirstElement -Root $root `
        -Names @($LabelOpenArchivedThreads, $LabelArchivedThreads, "Archived chats", "Archived threads") `
        -ControlTypes @("ControlType.ListItem", "ControlType.Button", "ControlType.Text")

    if ($archivedEntry) {
        Write-Step "Settings view opened via shortcut."
        return
    }

    Write-Step "Shortcut did not expose archived threads entry. Falling back to settings button."
    Click-NamedElement -Root $root `
        -Names @($LabelSettings, "Settings") `
        -ControlTypes @("ControlType.Button") `
        -What "settings button"

    Start-Sleep -Seconds 1
}

function Confirm-ArchiveDialogIfPresent {
    param([System.Diagnostics.Process]$Process)

    Start-Sleep -Seconds 1
    $root = Get-RootElement -Process $Process

    $archiveButton = Find-FirstElement -Root $root `
        -Names @($LabelArchive, "Archive") `
        -ControlTypes @("ControlType.Button")

    if (-not $archiveButton) {
        return $false
    }

    $cancelButton = Find-FirstElement -Root $root `
        -Names @($LabelCancel, "Cancel") `
        -ControlTypes @("ControlType.Button")

    if ($cancelButton) {
        Write-Step "Archive confirmation dialog detected."
    } else {
        Write-Step "Archive button detected after shortcut."
    }

    Invoke-OrClick -Element $archiveButton
    Start-Sleep -Seconds 2
    return $true
}

$process = Get-CodexWindowProcess -PreferForeground
Write-Step "Targeting Codex PID $($process.Id)"
Focus-CodexWindow -Process $process

$threadIdToUse = $null
if (-not [string]::IsNullOrWhiteSpace($ThreadId)) {
    $threadIdToUse = $ThreadId.Trim()
}

$processRef = [ref]$process
$resolvedThreadTitle = Resolve-ThreadTitle -Id $threadIdToUse -ExplicitTitle $ThreadTitle
if (-not [string]::IsNullOrWhiteSpace($resolvedThreadTitle)) {
    Write-Step "Resolved target thread title: $resolvedThreadTitle"
}
$threadTextCandidates = Get-ThreadTextCandidates -Title $resolvedThreadTitle

$root = Get-RootElement -Process $process
$back = Find-FirstElement -Root $root -Names @($LabelBackToApp, "Back to app") -ControlTypes @("ControlType.Button")
if ($back) {
    Write-Step "Leaving settings/details view first"
    Invoke-OrClick -Element $back
    Start-Sleep -Seconds 1
    $root = Get-RootElement -Process $process
}

if ($threadIdToUse) {
    Open-ThreadByDeepLink -Id $threadIdToUse -Process $processRef -ThreadTexts $threadTextCandidates
    $process = $processRef.Value
}

$root = Get-RootElement -Process $process
if ($ProbeOnly) {
    Dump-Candidates -Root $root
    exit 0
}

if ($threadIdToUse) {
    Write-Step "Reconfirming target thread before archive shortcut"
    Open-ThreadByDeepLink -Id $threadIdToUse -Process $processRef -ThreadTexts $threadTextCandidates
    $process = $processRef.Value
}

Focus-CodexWindow -Process $process
if ($threadIdToUse) {
    Assert-ThreadIdActive -Process $process -ExpectedThreadId $threadIdToUse
} else {
    Assert-ThreadIsVisible -Process $process -ThreadTexts $threadTextCandidates
}
Click-WindowCenter -Process $process
Send-ArchiveShortcut
Start-Sleep -Seconds 2
[void](Confirm-ArchiveDialogIfPresent -Process $process)
$processRef = [ref]$process
Refresh-CodexWindow -Process $processRef
$process = $processRef.Value

Open-SettingsView -Process $process
$root = Get-RootElement -Process $process

Click-NamedElement -Root $root `
    -Names @($LabelOpenArchivedThreads, $LabelArchivedThreads, "Archived chats", "Archived threads") `
    -ControlTypes @("ControlType.ListItem", "ControlType.Button", "ControlType.Text") `
    -What "archived threads entry"

Start-Sleep -Seconds 2
$processRef = [ref]$process
Refresh-CodexWindow -Process $processRef
$process = $processRef.Value
$root = Get-RootElement -Process $process

$unarchive = Find-FirstElement -Root $root `
    -Names @($LabelUnarchive, $LabelRemoveFromArchive, "Unarchive", "Treu de l'arxiu") `
    -ControlTypes @("ControlType.Button", "ControlType.MenuItem", "ControlType.Hyperlink", "ControlType.Text")

if (-not $unarchive) {
    Write-Step "Unarchive control not found after opening archived threads."
    Dump-Candidates -Root $root
    throw "Could not find the unarchive control."
}

Write-Step "Clicking unarchive control: $($unarchive.Current.Name)"
Invoke-OrClick -Element $unarchive

Start-Sleep -Seconds 1
$processRef = [ref]$process
Refresh-CodexWindow -Process $processRef
$process = $processRef.Value
$root = Get-RootElement -Process $process

$viewNow = Find-FirstElement -Root $root `
    -Names @($LabelViewNow, $LabelViewImmediately, "View now", "Open") `
    -ControlTypes @("ControlType.Button", "ControlType.Hyperlink", "ControlType.Text")

if ($viewNow) {
    Write-Step "Clicking view-now control: $($viewNow.Current.Name)"
    Invoke-OrClick -Element $viewNow
    Start-Sleep -Seconds 1
} else {
    Write-Step "No explicit view-now control found. Refresh path ended after unarchive."
}

if ($threadIdToUse) {
    $processRef = [ref]$process
    Open-ThreadByDeepLink -Id $threadIdToUse -Process $processRef -ThreadTexts $threadTextCandidates
    $process = $processRef.Value
}

$root = Get-RootElement -Process $process
Dump-Candidates -Root $root -Pattern "Settings|Open|Archive|Unarchive|View now|Back to app"
Write-Step "Official UI refresh script finished."
