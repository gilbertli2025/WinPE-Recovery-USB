<#
.SYNOPSIS
  Service catalog + Apply / Restore / Verify for the System Optimizer suite.
  One source of truth; previously this logic was copy-pasted across 3 files.
#>

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Service list (system-critical vs. safe vs. optional)
# --------------------------------------------------------------------------
$script:ServiceGroups = [ordered]@{
    Protected = @(
        'BDESVC','WinDefend','SecurityHealthService','W32Time','BITS','wuauserv',
        'TrustedInstaller','FontCache','winmgmt','eventlog','Schedule','RpcSs',
        'DcomLaunch','RpcEptMapper','LSM','SENS','CryptSvc','Dnscache','Dhcp',
        'NlaSvc','Audiosrv','AudioEndpointBuilder','gpsvc','ProfSvc','Themes'
    )

    Safe = @(
        'DiagTrack',            # Connected User Experiences and Telemetry
        'dmwappushservice',     # Device Management WAP Push Message
        'WMPNetworkSvc',        # Windows Media Player Network Sharing
        'Fax',                  # Fax service
        'RetailDemo',           # Retail Demo Service
        'RemoteRegistry',       # Remote Registry (also a security improvement)
        'WerSvc',               # Windows Error Reporting
        'NetTcpPortSharing',    # Net.Tcp Port Sharing
        'PhoneSvc',             # Phone Service
        'TabletInputService',   # Touch Keyboard and Handwriting Panel
        'XblAuthManager',       # Xbox Live Auth Manager
        'XblGameSave',          # Xbox Live Game Save
        'XboxNetApiSvc',        # Xbox Live Networking
        'XboxGipSvc',           # Xbox Accessory Management
        'HoloSvc',              # Windows Mixed Reality
        'MapsBroker',           # Downloaded Maps Manager
        'lfsvc',                # Geolocation Service
        'PcaSvc'                # Program Compatibility Assistant
    )

    Optional = @(
        'WSearch',              # Windows Search indexing (slower file search if off)
        'SysMain',              # Superfetch (usually fine to disable on SSD)
        'Spooler',              # Print Spooler (disable only if you never print)
        'TermService',          # Remote Desktop Services
        'SessionEnv',           # Remote Desktop Configuration
        'UmRdpService',         # Remote Desktop UserMode Port Redirector
        'WwanSvc',              # WWAN AutoConfig (cellular adapters)
        'bthserv',              # Bluetooth Support Service
        'BTAGService',          # Bluetooth Audio Gateway
        'BthAvctpSvc',          # Bluetooth AVCTP
        'WbioSrvc',             # Windows Biometric Service
        'stisvc',               # Windows Image Acquisition (scanners/cameras)
        'SharedAccess',         # Internet Connection Sharing
        'WpcMonSvc',            # Parental Controls
        'wlidsvc',              # Microsoft Account Sign-in Assistant
        'NvTelemetryContainer', # NVIDIA Telemetry
        'WdiServiceHost',       # Diagnostic Service Host
        'WdiSystemHost'         # Diagnostic System Host
    )
}

function Get-ServiceCategory {
    param([string]$Name)
    if ($script:ServiceGroups.Optional -contains $Name) { return 'Optional' }
    if ($script:ServiceGroups.Safe     -contains $Name) { return 'Safe' }
    return 'Unknown'
}

# --------------------------------------------------------------------------
# Low-level helpers
# --------------------------------------------------------------------------
function Get-CurrentStartType {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    try { return (Get-Service -Name $Name -ErrorAction Stop).StartType } catch { return '' }
}

function Get-RunningDependent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    try {
        $cim = Get-CimInstance Win32_DependentService -ErrorAction SilentlyContinue
        if (-not $cim) { return $null }
        foreach ($d in $cim) {
            if ($d.Antecedent -notmatch [regex]::Escape("Name='$Name'")) { continue }
            $depName = ([regex]::Match($d.Dependent, "Name='([^']+)'")).Groups[1].Value
            if (-not $depName) { continue }
            $dep = Get-Service -Name $depName -ErrorAction SilentlyContinue
            if ($dep -and $dep.Status -ne 'Stopped') { return $depName }
        }
    } catch { }
    return $null
}

# --------------------------------------------------------------------------
# Snapshot + backup helpers
#
# BUG FIX: snapshot was previously taken on BOTH apply and restore (in the
# standalone tools) which made Verify compare the post-restore state against
# itself. Snapshot is now ONLY created by Backup-ServicesSnapshot, which is
# called only on apply.
# --------------------------------------------------------------------------
function Backup-ServicesSnapshot {
    [CmdletBinding()]
    param()
    $snapPath = $script:Paths.ServicesSnapshot
    $bakPath  = $script:Paths.ServicesSnapshotBak
    # Keep the previous snapshot as .bak so Verify can detect "snapshot file
    # was overwritten after restore" rather than silently passing.
    if (Test-Path -LiteralPath $snapPath) {
        try { Copy-Item -LiteralPath $snapPath -Destination $bakPath -Force } catch { }
    }
    # BUG FIX (v1.4): if the tool is not running as admin, writing to %ProgramData%
    # is denied. Catch that and show a clear message instead of a crash dialog.
    try {
        $all = Get-CimInstance Win32_Service | Select-Object Name, StartMode, State
        $all | Export-Csv -LiteralPath $snapPath -NoTypeInformation -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $script:Paths.ServicesBackupFile)) {
            @() | Export-Csv -LiteralPath $script:Paths.ServicesBackupFile -NoTypeInformation -ErrorAction Stop
        }
    } catch {
        $msg = $_.Exception.Message
        Write-Log "ERROR writing services backup: $msg"
        if ($msg -match 'denied') {
            Write-Log "The app must be run as Administrator to write to %ProgramData%."
        }
        throw "Could not write the services backup. Please run System Optimizer as Administrator. ($msg)"
    }
}

function Save-ServiceBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$OldStartType,
        [Parameter(Mandatory)][bool]$WasRunning
    )
    $rows = @(Read-CsvRows -Path $script:Paths.ServicesBackupFile | Where-Object { $_.Name -ne $Name })
    $rows += [PSCustomObject]@{
        Name         = $Name
        OldStartType = $OldStartType
        WasRunning   = $WasRunning
        Category     = Get-ServiceCategory $Name
        Date         = (Get-Date).ToString('o')
    }
    Write-CsvRows -Path $script:Paths.ServicesBackupFile -Rows $rows
}

# --------------------------------------------------------------------------
# Apply / Restore / Verify
# --------------------------------------------------------------------------
function Disable-Services {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Names)

    foreach ($name in $Names) {
        if ($script:ServiceGroups.Protected -contains $name) {
            Write-Log "SKIP (protected): $name"; continue
        }
        if (-not (Get-Service -Name $name -ErrorAction SilentlyContinue)) {
            Write-Log "SKIP (not installed): $name"; continue
        }
        $current = Get-CurrentStartType $name
        if ($current -eq 'Disabled') {
            Write-Log "SKIP (already disabled): $name"; continue
        }
        $dep = Get-RunningDependent $name
        if ($dep) {
            Write-Log "SKIP (running dependent '$dep'): $name"; continue
        }
        $old        = $current
        $wasRunning = $false
        try {
            $svc        = Get-Service -Name $name -ErrorAction Stop
            $wasRunning = ($svc.Status -eq 'Running')
        } catch { }
        try {
            Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
            try { Stop-Service -Name $name -Force -ErrorAction Stop } catch {
                Write-Log "WARN (could not stop): $name"
            }
            Save-ServiceBackup -Name $name -OldStartType $old -WasRunning $wasRunning
            Write-Log "DISABLED: $name (was $old)"
        } catch {
            Write-Log "ERROR disabling $name : $($_.Exception.Message)"
        }
    }
}

function Restore-ServicesRows {
    [CmdletBinding()]
    param([object[]]$Rows)

    if (-not $Rows -or $Rows.Count -eq 0) {
        Write-Log "Backup is empty - nothing to restore."; return
    }
    foreach ($row in $Rows) {
        $name = $row.Name
        if (-not (Get-Service -Name $name -ErrorAction SilentlyContinue)) {
            Write-Log "SKIP (not installed): $name"; continue
        }
        $old = [string]$row.OldStartType
        if ([string]::IsNullOrWhiteSpace($old)) {
            Write-Log "WARN: no OldStartType recorded for $name ; cannot restore."
            continue
        }
        try {
            Set-Service -Name $name -StartupType $old -ErrorAction Stop
            # WasRunning is serialized as the literal string "True" / "False"
            # from Export-Csv. Compare both ways to be tolerant.
            $wr = [string]$row.WasRunning
            if ($wr -eq 'True' -or $wr -eq 'true') {
                try { Start-Service -Name $name -ErrorAction Stop } catch {
                    Write-Log "WARN: could not restart $name : $($_.Exception.Message)"
                }
            }
            Write-Log "RESTORED: $name (startup -> $old)"
        } catch {
            Write-Log "ERROR restoring $name : $($_.Exception.Message)"
        }
    }
}

function Restore-Services {
    [CmdletBinding()]
    $rows = Read-CsvRows -Path $script:Paths.ServicesBackupFile
    Restore-ServicesRows -Rows $rows
}

function Restore-OptionalServices {
    [CmdletBinding()]
    $rows = @(Read-CsvRows -Path $script:Paths.ServicesBackupFile | Where-Object { $_.Category -eq 'Optional' })
    if ($rows.Count -eq 0) {
        Write-Log "No OPTIONAL services in the backup to restore."
        return
    }
    Restore-ServicesRows -Rows $rows
}

# --------------------------------------------------------------------------
# Verify (two modes: Simple for the unified GUI, Full for the standalone
# tools which check snapshot + log marker + protected-services-unchanged)
# --------------------------------------------------------------------------
function Test-ServicesDisabled {
    [CmdletBinding()]
    $rows = Read-CsvRows -Path $script:Paths.ServicesBackupFile
    if (-not (Test-Path -LiteralPath $script:Paths.ServiceBackup)) {
        Write-Log "[FAIL] no services backup folder - optimizer not run."; return
    }
    if (-not (Test-Path -LiteralPath $script:Paths.ServicesBackupFile)) {
        Write-Log "[FAIL] services backup file missing."; return
    }
    if ($rows.Count -eq 0) {
        Write-Log "Services backup empty - nothing to verify."; return
    }
    Write-Log "Services targeted: $($rows.Count)"
    $p = 0; $f = 0; $w = 0
    foreach ($row in $rows) {
        $svc = Get-Service -Name $row.Name -ErrorAction SilentlyContinue
        if (-not $svc) { Write-Log "[WARN] $($row.Name) no longer exists."; $w++; continue }
        if ($svc.StartType -eq 'Disabled') {
            Write-Log "[PASS] $($row.Name) disabled."; $p++
        } else {
            Write-Log "[FAIL] $($row.Name) expected Disabled, is $($svc.StartType)."; $f++
        }
    }
    Write-Log "Services: PASS=$p FAIL=$f WARN=$w"
}

function Test-ServicesFull {
    [CmdletBinding()]
    $p = 0; $f = 0; $w = 0
    if (-not (Test-Path -LiteralPath $script:Paths.ServiceBackup)) {
        Write-Log "No backup folder found - optimizer has NOT been run."; return
    }
    $ran = $false
    $logPath = $script:Paths.ServicesLog
    if (Test-Path -LiteralPath $logPath) {
        $log = Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue
        if ($log -match "Optimizer started") {
            $ran = $true
            Write-Log "[PASS] Optimization run detected in log."; $p++
        } else {
            Write-Log "[WARN] Log exists but no start marker - optimization may not have run."; $w++
        }
    } else {
        Write-Log "[FAIL] Log file not found ($logPath)."; $f++
    }

    if (-not (Test-Path -LiteralPath $script:Paths.ServicesBackupFile)) {
        Write-Log "[FAIL] Backup file not found."; return
    }
    $rows = Read-CsvRows -Path $script:Paths.ServicesBackupFile
    if ($rows.Count -eq 0) {
        Write-Log "Backup empty - nothing to verify."; return
    }
    Write-Log "Services targeted: $($rows.Count)"
    foreach ($row in $rows) {
        $svc = Get-Service -Name $row.Name -ErrorAction SilentlyContinue
        if (-not $svc) { Write-Log "[WARN] $($row.Name) no longer exists."; $w++; continue }
        if ($svc.StartType -eq 'Disabled') {
            Write-Log "[PASS] $($row.Name) disabled."; $p++
        } else {
            Write-Log "[FAIL] $($row.Name) expected Disabled, is $($svc.StartType)."; $f++
        }
    }
    if ($ran -and (Test-Path -LiteralPath $logPath)) {
        $errLines = Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue | Where-Object { $_ -match '^ERROR' }
        if ($errLines) {
            Write-Log "[FAIL] The log contains error(s):"; $f++
            $errLines | ForEach-Object { Write-Log ("       " + $_) }
        } else {
            Write-Log "[PASS] No errors found in the optimization log."; $p++
        }
    }

    # Verify protected services unchanged from snapshot (only if snapshot
    # taken AFTER the run, NOT after a subsequent restore)
    $snapPath = $script:Paths.ServicesSnapshot
    if (Test-Path -LiteralPath $snapPath) {
        $snap = @(Import-Csv -LiteralPath $snapPath -ErrorAction SilentlyContinue)
        $checked = 0
        foreach ($row in $snap) {
            if ($script:ServiceGroups.Protected -notcontains $row.Name) { continue }
            $cur = Get-Service -Name $row.Name -ErrorAction SilentlyContinue
            if (-not $cur) { continue }
            $checked++
            $norm = switch ($row.StartMode) {
                'Auto'      { 'Automatic' }
                'AutoStart' { 'Automatic' }
                default     { $row.StartMode }
            }
            if ($norm -eq $cur.StartType) {
                Write-Log "[PASS] Protected $($row.Name) unchanged."; $p++
            } else {
                Write-Log "[WARN] Protected $($row.Name) changed ($($row.StartMode) -> $($cur.StartType))."; $w++
            }
        }
        if ($checked -eq 0) { Write-Log "[WARN] No protected services found in snapshot."; $w++ }
    }
    Write-Log "Summary: PASS=$p FAIL=$f WARN=$w"
}

$script:LibServiceLoaded = $true
