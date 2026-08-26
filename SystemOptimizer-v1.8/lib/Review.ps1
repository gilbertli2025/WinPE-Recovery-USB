<#
.SYNOPSIS
  Security review report. Generates both a console-style summary and a
  persisted report file.

.DESCRIPTION
  This is closer to the rich console review (which had SMBv1 / users / UAC /
  updates sections the GUI versions did not). The GUI omits a few of these
  for layout but they remain available via -Full.
#>

$ErrorActionPreference = 'Stop'

$script:ReviewReportFile = $script:Paths.SecurityReviewFile

function Add-RevLine {
    [CmdletBinding()]
    param([string]$Line, [System.Text.StringBuilder]$Builder)
    [void]$Builder.AppendLine($Line)
}

function Get-RevVal {
    param($V, [string]$Fallback = 'n/a')
    if ($null -eq $V) { return $Fallback }
    return $V
}

function Build-SecurityReport {
    [CmdletBinding()]
    param([switch]$Full)
    $sb = New-Object System.Text.StringBuilder
    $st = $null
    $mp = $null
    try { $st = Get-MpComputerStatus } catch { }
    try { $mp = Get-MpSetting } catch { }

    [void]$sb.AppendLine("=== Security Review - $env:COMPUTERNAME ===")
    [void]$sb.AppendLine("Date: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('-- Windows Defender --')
    [void]$sb.AppendLine("  Real-time protection : " + (Get-RevVal $st.RealTimeProtectionEnabled))
    [void]$sb.AppendLine("  Antivirus enabled    : " + (Get-RevVal $st.AntivirusEnabled))
    [void]$sb.AppendLine("  Tamper protection    : " + (Get-RevVal $st.IsTamperProtected))
    $sigAge = 'n/a'
    try { $sigAge = [math]::Round(((Get-Date) - $st.AntivirusSignatureLastUpdated).TotalDays, 1) } catch { }
    [void]$sb.AppendLine("  Signatures age (days): $sigAge")
    [void]$sb.AppendLine("  Cloud protection MAPS: " + (Get-RevVal $mp.MAPS) + "   (2 = advanced)")
    [void]$sb.AppendLine("  Cloud block level    : " + (Get-RevVal $mp.CloudBlockLevel) + "   (2+ = recommended)")
    $exc = try { @($st.ExclusionPath).Count + @($st.ExclusionProcess).Count + @($st.ExclusionExtension).Count } catch { 'n/a' }
    [void]$sb.AppendLine("  Exclusions count     : $exc")

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('-- Firewall --')
    foreach ($prof in 'Domain','Private','Public') {
        try { $f = Get-NetFirewallProfile -Name $prof
              [void]$sb.AppendLine(("  {0,-8} enabled={1}  defaultInbound={2}" -f $prof, $f.Enabled, $f.DefaultInboundAction)) }
        catch { [void]$sb.AppendLine("  ${prof}: n/a") }
    }

    if ($Full) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('-- Remote access & sharing --')
        $rdp = Get-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections'
        [void]$sb.AppendLine("  Remote Desktop      : " + $(if ($rdp -eq 0) { 'ENABLED (consider disabling)' } else { 'disabled (good)' }))
        [void]$sb.AppendLine("  SMBv1               : " + (Get-RevVal (try { (Get-SmbServerConfiguration).EnableSMB1Protocol } catch { })) + "   (False = good)")
        try {
            $shares = @(Get-SmbShare | Where-Object { $_.Name -notmatch '^\w+\$$' })
            [void]$sb.AppendLine("  User file shares    : " + $(if ($shares.Count -eq 0) { 'none (good)' } else { ($shares.Name -join ', ') }))
        } catch { }

        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('-- Accounts & UAC --')
        try {
            $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
            $enabledUsers = @(Get-LocalUser | Where-Object Enabled)
            foreach ($u in $enabledUsers) {
                $isAdmin = $admins -contains ("$env:COMPUTERNAME\" + $u.Name)
                [void]$sb.AppendLine(("  User '{0}' : {1}" -f $u.Name, $(if ($isAdmin) { 'ADMINISTRATOR' } else { 'standard' })))
            }
        } catch { }
        $lua = Get-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA'
        [void]$sb.AppendLine("  UAC enabled         : " + $(if ($lua -eq 1) { 'yes (good)' } else { 'NO - not recommended' }))

        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('-- Updates & schedule --')
        try {
            $latest = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
            [void]$sb.AppendLine("  Latest update       : " + $(if ($latest) { "$($latest.HotFixID) ($($latest.InstalledOn.ToString('yyyy-MM-dd')))" } else { 'n/a' }))
        } catch { }
        $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
                   (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
        [void]$sb.AppendLine("  Pending reboot      : $pending")
        $q = try { $mp.ScanScheduleQuickScanTime } catch { }
        $qhour = if ($q -is [TimeSpan]) { $q.Hours } elseif ($null -ne $q) { $q } else { 'n/a' }
        [void]$sb.AppendLine("  Defender quick scan : $qhour (hour of day, 24h)")
    }

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('-- Auto-lock --')
    $secure  = Get-RegDword 'HKCU:\Control Panel\Desktop' 'ScreenSaverIsSecure'
    $timeout = Get-RegDword 'HKCU:\Control Panel\Desktop' 'ScreenSaveTimeOut'
    [void]$sb.AppendLine("  Screen locks on idle: " + $(if ($secure -eq 1) { "yes, after $([math]::Round($timeout/60)) min" } else { 'no' }))

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('-- BitLocker --')
    try {
        $bl = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop
        [void]$sb.AppendLine("  C: protection        : $($bl.ProtectionStatus)")
    } catch { [void]$sb.AppendLine("  C: protection        : n/a (requires admin)") }

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('-- Browsers (policies) --')
    foreach ($b in @(@('Edge', $script:SecurityKeys.EdgePolicies), @('Chrome', $script:SecurityKeys.ChromePolicies))) {
        $bname = $b[0]; $key = $b[1]
        $dl   = Get-RegDword $key 'DownloadRestrictions'
        $cookies = Get-RegDword $key 'BlockThirdPartyCookies'
        $safe = if ($bname -eq 'Edge') { Get-RegDword $key 'SmartScreenEnabled' } else { Get-RegDword $key 'SafeBrowsingProtectionLevel' }
        [void]$sb.AppendLine(("  {0,-7} blockDownload={1}  block3rdPartyCookies={2}  safeBrowsing={3}" -f `
            $bname, $(if ($dl -eq 2) { 'yes' } else { 'no' }),
            $(if ($cookies -eq 1) { 'yes' } else { 'no' }),
            (Get-RevVal $safe)))
    }

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('-- System Restore --')
    try {
        $rps = @(Get-ComputerRestorePoint -ErrorAction Stop)
        if ($rps.Count -eq 0) {
            [void]$sb.AppendLine("  Restore points     : none (protection likely OFF)")
        } else {
            $last = $rps | Sort-Object CreationTime -Descending | Select-Object -First 1
            [void]$sb.AppendLine("  Restore points     : $($rps.Count)  latest: $($last.CreationTime.ToString('yyyy-MM-dd HH:mm'))")
        }
    } catch { [void]$sb.AppendLine("  Restore points     : query failed") }
    $weekTask = Get-ScheduledTask -TaskName $script:WeeklyRestoreTaskName -ErrorAction SilentlyContinue
    [void]$sb.AppendLine("  Weekly point task  : " + $(if ($weekTask) { 'scheduled' } else { 'not scheduled' }))

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('-- Recommendations --')
    if ($st.RealTimeProtectionEnabled -and $mp.MAPS -eq 2) { [void]$sb.AppendLine('  - Defender + cloud protection: OK') }
    else { [void]$sb.AppendLine('  - Run Harden to enable cloud protection.') }
    $edgeOK   = (Get-RegDword $script:SecurityKeys.EdgePolicies 'DownloadRestrictions') -eq 2
    $chromeOK = (Get-RegDword $script:SecurityKeys.ChromePolicies 'DownloadRestrictions') -eq 2
    if ($edgeOK -and $chromeOK) { [void]$sb.AppendLine('  - Browser hardening: OK') }
    else { [void]$sb.AppendLine('  - Run Harden to apply browser hardening.') }

    return $sb.ToString()
}

function Save-SecurityReview {
    [CmdletBinding()]
    param([switch]$Full)
    $text = Build-SecurityReport -Full:$Full
    $path = $script:ReviewReportFile
    $dir  = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($path, $text, $script:Utf8NoBom)
    Write-Log ("Review report saved to: " + $path)
    Write-Log ('')
    # Echo to log too (so the GUI's log box shows it)
    foreach ($line in ($text -split "`r?`n")) { if ($line) { Write-Log ("    " + $line) } }
}

function Get-MaintenanceReport {
    [CmdletBinding()]
    $lines = @('-- Maintenance --')
    $gdv  = Get-RegDword 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
    $lines += ("  Game DVR        : " + $(if ($gdv -eq 0) { 'off (good)' } else { 'on (running)' }))
    $ss   = Get-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01'
    $lines += ("  Storage Sense   : " + $(if ($ss -eq 1) { 'on' } else { 'off' }))
    try {
        $t = (Get-ChildItem $env:TEMP -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        $lines += ("  Temp files      : ~{0} MB in {1}" -f [math]::Round($t/1MB, 1), $env:TEMP)
    } catch { $lines += "  Temp files      : query failed" }
    $fs = Get-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled'
    $lines += ("  Fast Startup    : " + $(if ($fs -eq 1) { 'on' } else { 'off' }))
    $active = try { (powercfg /getactivescheme) 2>&1 | Out-String } catch { '' }
    $plan  = ($active -split ':')[-1].Trim()
    $lines += ("  Power plan      : $plan")
    $lines | ForEach-Object { Write-Log $_ }
}

# --------------------------------------------------------------------------
# Diagnostics (v1.4): drive health, disk space, resources, power/battery
# --------------------------------------------------------------------------
function Get-DriveHealthReport {
    Write-Log '-- Drive health (SMART) --'
    try {
        $disks = @(Get-PhysicalDisk -ErrorAction Stop)
        foreach ($d in $disks) {
            $wear = $null
            try { $rc = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue; $wear = $rc.Wear } catch { }
            $w = if ($null -ne $wear) { "$wear%" } else { 'n/a' }
            $fs = Get-Volume -DriveLetter $d.DeviceId.Substring(0,1) -ErrorAction SilentlyContinue
            Write-Log ("  {0}  {1}  {2} GB  health={3}  wear={4}" -f $d.FriendlyName, $d.MediaType, [math]::Round($d.Size/1GB), $d.HealthStatus, $w)
        }
        $bad = $disks | Where-Object { $_.HealthStatus -ne 'Healthy' }
        if ($bad) { Write-Log "  WARNING: one or more drives are not healthy - back up important data and check them." }
        else { Write-Log '  All drives report Healthy.' }
    } catch { Write-Log '  Drive health query failed (may need admin).' }
}

function Get-DiskSpaceReport {
    Write-Log '-- Disk space --'
    try {
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
            $pct = if ($_.Size) { [math]::Round((($_.Size - $_.FreeSpace)/$_.Size)*100) } else { 0 }
            Write-Log ("  {0}  {1} GB free of {2} GB  ({3}% used)" -f $_.DeviceID, [math]::Round($_.FreeSpace/1GB,1), [math]::Round($_.Size/1GB,1), $pct)
        }
    } catch { Write-Log '  Disk space query failed.' }
    # Largest folders under a given root (default C:\Users)
    Write-Log '  Largest folders (top 6):'
    try {
        Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{ Path=$_.FullName; Size=(Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
        } | Sort-Object Size -Descending | Select-Object -First 6 | ForEach-Object {
            Write-Log ("    {0}  ~{1} GB" -f $_.Path, [math]::Round($_.Size/1GB,1))
        }
    } catch { Write-Log '  Folder scan failed.' }
}

function Get-ResourceReport {
    Write-Log '-- System resources --'
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalRam = $os.TotalVisibleMemorySize; $freeRam = $os.FreePhysicalMemory
        Write-Log ("  Memory: {0}% used ({1} GB of {2} GB)" -f [math]::Round((($totalRam-$freeRam)/$totalRam)*100), [math]::Round(($totalRam-$freeRam)/1MB,1), [math]::Round($totalRam/1MB,1))
    } catch { Write-Log '  Memory query failed.' }
    try {
        $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        Write-Log ("  CPU load: {0}%" -f $cpu)
    } catch { Write-Log '  CPU query failed.' }
    Write-Log '  Top processes by memory:'
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 | ForEach-Object {
        Write-Log ("    {0}  {1} MB" -f $_.ProcessName, [math]::Round($_.WorkingSet64/1MB,1))
    }
}

function Get-PowerBatteryReport {
    Write-Log '-- Power / battery --'
    try {
        $plan = (powercfg /getactivescheme 2>&1 | Out-String)
        Write-Log ("  Active power plan: " + (($plan -split ':')[-1].Trim()))
    } catch { Write-Log '  Power plan query failed.' }
    $isBattery = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    if ($isBattery) {
        try { $b = Get-CimInstance Win32_Battery; Write-Log ("  Battery: {0}% (status {1})" -f $b.EstimatedChargeRemaining, $b.BatteryStatus) } catch { Write-Log '  Battery query failed.' }
        Write-Log '  Run `powercfg /batteryreport` in a terminal for a full battery-health report.'
    } else {
        Write-Log '  No battery detected (desktop).'
    }
}

function Get-DiagnosticsReport {
    Get-DriveHealthReport
    Get-DiskSpaceReport
    Get-ResourceReport
    Get-PowerBatteryReport
}

$script:LibReviewLoaded = $true

