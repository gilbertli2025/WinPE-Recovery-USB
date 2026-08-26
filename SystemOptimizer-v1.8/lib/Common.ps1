<#
.SYNOPSIS
  Shared helpers for the System Optimizer suite. Dot-source this from every
  entry-point script before any other lib/* is loaded.

.DESCRIPTION
  Provides:
    - $script:Paths            canonical %ProgramData% paths (one source of truth)
    - Write-Log                timestamped log to file; optional console mirror;
                               optional sink (TextBox.AppendText)
    - Read/Write JSON          UTF-8 (no BOM), round-trip safe on PS 5.1 and 7+
    - Test-Admin / Restart-Admin
    - Show-Message / Show-YesNo / Ask-Choice   console-aware UI helpers
    - Invoke-UnderProgress     run a block in a background runspace + a callback
                               for progress + cancellation (used by GUI)

  All disk writes for backups use a single Sync hashtable per file so two
  processes do not silently lose rows (was bug #4 in the original code).
#>

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Paths (single source of truth)
# --------------------------------------------------------------------------
# Paths (single source of truth, re-resolved on every access so a caller
# can change $env:ProgramData after dot-sourcing without affecting earlier
# callers - important for tests, and for installers that relocate data).
# --------------------------------------------------------------------------
$script:Paths = $null   # rebuilt lazily by Get-Paths below

function Get-Paths {
    if ($null -eq $script:Paths) {
        $svc = Join-Path $env:ProgramData 'WinServiceOpt'
        $sec = Join-Path $env:ProgramData 'WinSecOpt'
        $sys = Join-Path $env:ProgramData 'SystemOptimizer'
        foreach ($d in @($svc, $sec, $sys)) {
            if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        }
        $script:Paths = [ordered]@{
            ServiceBackup       = $svc
            SecurityBackup      = $sec
            SystemBackup        = $sys
            ServicesBackupFile  = Join-Path $svc 'services-backup.csv'
            ServicesSnapshot    = Join-Path $svc 'all-services-snapshot.csv'
            ServicesSnapshotBak = Join-Path $svc 'all-services-snapshot.bak.csv'
            ServicesLog         = Join-Path $svc 'optimize.log'
            SecurityBackupFile  = Join-Path $sec 'backup.json'
            SecurityLog         = Join-Path $sec 'harden.log'
            SecurityReviewFile  = Join-Path $sec 'security-review.txt'
            MaintBackupFile     = Join-Path $sys 'maintenance-backup.json'
            UnifiedLog          = Join-Path $sys 'unified.log'
            LastRunFile         = Join-Path $sys 'lastrun.json'
        }
    }
    return $script:Paths
}

# Trigger initial build
Get-Paths | Out-Null

# Is a USB (removable) drive present? Used for the backup-first safety guide.
function Test-UsbPresent {
    $rem = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1
    return [bool]$rem
}

# --------------------------------------------------------------------------
# Logging (no BOM, atomic-ish, console/GUI-agnostic)
# --------------------------------------------------------------------------
# The consumer sets:
#   $script:LogFile         - mandatory (file path)
#   $script:LogSink         - optional scriptblock invoked with the line
#                             (GUI: append to a multiline TextBox)
#   $script:LogMirrorHost   - $true to also Write-Host (console scripts)
# Write-Log is therefore the only logging entry point in the whole suite.

# Defaults so dot-sourcing alone (no consumer-side setup) is safe under
# Set-StrictMode -Version Latest. We don't check-before-write because reading
# an unset script-scope variable throws under StrictMode.
$script:WriteLogSync  = [hashtable]::Synchronized(@{})
$script:Utf8NoBom     = [System.Text.UTF8Encoding]::new($false)
$script:NewLine       = [System.Environment]::NewLine
$script:LogMirrorHost = $false
$script:LogFile        = $null
$script:LogSink        = $null
$script:UiSink         = $null
$script:RunLog         = $null
$script:BackupSession  = $null

function Write-Log {
    [CmdletBinding()]
    param([Parameter(Position=0)][string]$Message)

    if ([string]::IsNullOrEmpty($Message)) { return }
    if (-not $script:LogFile) { return }

    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message

    # File write (UTF-8 NO BOM, PS 5.1+ and 7+). Swallow disk errors so a
    # read-only volume never breaks the whole tool.
    try {
        $dir = Split-Path -Parent $script:LogFile
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $payload = $line + $script:NewLine
        # PS 5.1's `lock` keyword is fragile; use Monitor directly so any PS host works.
        $lockObj = $script:WriteLogSync
        $taken = $false
        try {
            [System.Threading.Monitor]::TryEnter($lockObj, [ref]$taken) | Out-Null
            if ($taken) {
                [System.IO.File]::AppendAllText($script:LogFile, $payload, $script:Utf8NoBom)
            }
        } finally {
            if ($taken) { [System.Threading.Monitor]::Exit($lockObj) }
        }
    } catch {
        # last-resort: surface to error stream without crashing
        Write-Error "Could not write log: $($_.Exception.Message)"
    }

    # Secondary run log (e.g. a per-run copy on the USB). Same line; never crash
    # if the volume is unavailable/read-only.
    if ($script:RunLog) {
        try {
            $dir2 = Split-Path -Parent $script:RunLog
            if (-not (Test-Path $dir2)) { New-Item -ItemType Directory -Path $dir2 -Force | Out-Null }
            [System.IO.File]::AppendAllText($script:RunLog, $payload, $script:Utf8NoBom)
        } catch { }
    }

    # Console mirror
    if ($script:LogMirrorHost) {
        try { Write-Host $line } catch { }
    }

    # UI sink (e.g. TextBox.AppendText). Wrapped in Invoke for background
    # runspaces; safe to call from the UI thread too.
    if ($script:LogSink) {
        try {
            $cb = $script:LogSink
            if ($null -ne $syncContext) {
                $syncContext.Send([System.Threading.SendOrPostCallback]{ param($l) & $script:LogSink $l }, $line) | Out-Null
            } else {
                & $cb $line
            }
        } catch { }
    }
}

# --------------------------------------------------------------------------
# JSON helpers (UTF-8 no BOM, parse-failure-safe)
# --------------------------------------------------------------------------
function Read-JsonArray {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    try {
        $raw = [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom)
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $parsed) { return @() }
        if ($parsed -is [System.Array]) {
            # Already an array - return as-is so `@(Read-JsonArray)` yields the
            # rows (not a nested 1-element wrapper, which corrupted the backup).
            return $parsed
        }
        return ,$parsed
    } catch {
        try { Write-Log "WARN: failed to parse $Path as JSON: $($_.Exception.Message). Treating as empty." } catch { }
        return @()
    }
}

# Helper that the SET functions use to read+filter rows. Unlike a plain
# @(Read-JsonArray | Where-Object ...) this avoids the PS quirk where a
# single wrapped element gets re-emitted by the pipeline. The pipeline
# naturally unrolls arrays of size 0 or 1; we re-coalesce with @(...) here.
function Get-BackedRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $r = Read-JsonArray -Path $Path
    $arr = @($r)
    if ($arr.Count -eq 1 -and $null -eq $arr[0]) {
        # ConvertFrom-Json of "{}" returned $null; collapse
        return @()
    }
    return $arr
}

function Write-JsonArray {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Items
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # Normalise to Object[] so ConvertTo-Json doesn't see .NET collection meta-properties.
    $bag = @($Items)
    if ($bag.Count -eq 0) {
        [System.IO.File]::WriteAllText("$Path.new", '[]', $script:Utf8NoBom)
    } else {
        $json = ConvertTo-Json -InputObject $bag -Depth 10
        if (-not $json.TrimStart().StartsWith('[')) {
            $json = "[ $json ]"
        }
        [System.IO.File]::WriteAllText("$Path.new", $json, $script:Utf8NoBom)
    }
    Move-Item -LiteralPath "$Path.new" -Destination $Path -Force
}

# --------------------------------------------------------------------------
# CSV helpers (services backup uses CSV with -NoTypeInformation, like before)
# --------------------------------------------------------------------------
function Read-CsvRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    try {
        $imported = Import-Csv -LiteralPath $Path -ErrorAction Stop
        if ($null -eq $imported) { return @() }
        return ,@($imported)
    } catch {
        try { Write-Log "WARN: failed to parse CSV $Path : $($_.Exception.Message)" } catch { }
        return @()
    }
}

function Write-CsvRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Rows)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = "$Path.new"
    $Rows | Export-Csv -LiteralPath $tmp -NoTypeInformation -ErrorAction Stop
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# --------------------------------------------------------------------------
# Admin / elevation
# --------------------------------------------------------------------------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Relaunch the current script elevated. Used by every entry-point script
# that needs admin. ALWAYS goes via `powershell -ExecutionPolicy Bypass`
# so dot-sourcing of lib\*.ps1 works on machines with execution policy
# other than Bypass. The PS2EXE wrapper's own policy handling doesn't
# always override system-wide Restricted policies, so we don't trust it.
function Restart-Admin {
    [CmdletBinding()]
    param([string[]]$Arguments = @())

    $me = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($me) -or -not (Test-Path -LiteralPath $me)) {
        # Inside a compiled .exe the PS path is often empty. The .exe lives next
        # to the .ps1 source of the same name; prefer the .ps1 so we can
        # re-launch with -ExecutionPolicy Bypass.
        $candidate = [IO.Path]::ChangeExtension([Diagnostics.Process]::GetCurrentProcess().Path, '.ps1')
        if (Test-Path -LiteralPath $candidate) { $me = $candidate }
        else { $me = [Diagnostics.Process]::GetCurrentProcess().Path }
    }
    if ($me -like '*.ps1') {
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$me`"") + $Arguments
        Start-Process -FilePath 'powershell' -ArgumentList $argList -Verb RunAs | Out-Null
    } else {
        # Last-resort: relaunch the compiled .exe with original arguments.
        # The exe will probably fail with the same execution policy error,
        # but for users on RemoteSigned/AllSigned machines this works.
        Start-Process -FilePath $me -ArgumentList $Arguments -Verb RunAs | Out-Null
    }
}

function Show-Message {
    [CmdletBinding()]
    param([string]$Text, [string]$Title = 'System Optimizer', [ValidateSet('Info','Warn','Error')][string]$Severity = 'Info')
    $icon = switch ($Severity) { 'Warn' { 'Warning' } 'Error' { 'Error' } default { 'Information' } }
    # Always try the UI sink first (lets a caller override for tests), then fall
    # back to the WinForms MessageBox directly. Console-only fallback is ONLY
    # used when no UI host is loaded.
    if ($script:UiSink -and $script:UiSink.MessageBox) {
        & $script:UiSink.MessageBox $Text $Title OK $icon
    } elseif ([System.Windows.Forms.SystemInformation]::UserInteractive) {
        # Center the box over the app window so it clearly belongs to it.
        $owner = $null
        try { $owner = [System.Windows.Forms.Form]::ActiveForm } catch { $owner = $null }
        if ($owner) { [void][System.Windows.Forms.MessageBox]::Show($owner, $Text, $Title, 'OK', $icon) }
        else { [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, 'OK', $icon) }
    } else {
        $color = switch ($Severity) { 'Warn' { 'Yellow' } 'Error' { 'Red' } default { 'Cyan' } }
        Write-Host $Text -ForegroundColor $color
    }
}

function Show-YesNo {
    [CmdletBinding()]
    param([string]$Text, [string]$Title = 'System Optimizer', [string]$Severity = 'Warn')
    $icon = switch ($Severity) { 'Warn' { 'Warning' } 'Error' { 'Error' } default { 'Question' } }
    if ($script:UiSink -and $script:UiSink.MessageBox) {
        $r = & $script:UiSink.MessageBox $Text $Title YesNo $icon
        return ($r -eq 'Yes')
    } elseif ([System.Windows.Forms.SystemInformation]::UserInteractive) {
        $owner = $null
        try { $owner = [System.Windows.Forms.Form]::ActiveForm } catch { $owner = $null }
        if ($owner) { $r = [System.Windows.Forms.MessageBox]::Show($owner, $Text, $Title, 'YesNo', $icon) }
        else { $r = [System.Windows.Forms.MessageBox]::Show($Text, $Title, 'YesNo', $icon) }
        return ($r -eq 'Yes')
    }
    # No UI host. Default to YES so unattended scripts proceed; callers who
    # want to be strict should provide a UiSink.
    return $true
}

# --------------------------------------------------------------------------
# Generic list/keyed-store helpers
# --------------------------------------------------------------------------
function Get-KeyedRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [string]$KeyProperty = 'Name')
    $rows = Read-JsonArray -Path $Path
    return ,$rows
}

function Set-KeyedRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [string]$KeyProperty = 'Name'
    )
    $rows = @(Read-JsonArray -Path $Path | Where-Object { $_.$KeyProperty -ne $Key })
    if ($rows.Count -eq 1 -and $null -eq $rows[0]) {
        # Read-JsonArray returned a literal $null (file was "null"); collapse.
        $rows = @()
    }
    $rows += [PSCustomObject]@{ $KeyProperty = $Key; Value = $Value }
    Write-JsonArray -Path $Path -Items $rows
}

# --------------------------------------------------------------------------
# Background runspace helper (used by GUI for long-running apply/restore).
# Falls back to running inline on PS 5.1 (which lacks ThreadJob) or when the
# caller does not need progress.
# --------------------------------------------------------------------------
function Start-BackgroundAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [scriptblock]$ProgressCallback
    )
    # PowerShell 7+ has ThreadJob; use it. Otherwise run synchronously.
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $job = Start-ThreadJob -ScriptBlock $Action
        while ($job.State -eq 'Running') {
            if ($ProgressCallback) { & $ProgressCallback }
            Start-Sleep -Milliseconds 200
        }
        if ($job.State -ne 'Completed') {
            Write-Log ("Background action did not finish cleanly: " + $job.State)
        }
        Receive-Job -Job $job -Keep | Out-Null
        Remove-Job -Job $job -Force
    } else {
        & $Action
    }
}

# --------------------------------------------------------------------------
# Compatibility marker
# --------------------------------------------------------------------------
$script:LibCommonLoaded = $true
