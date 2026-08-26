<#
.SYNOPSIS
  Maintenance + cleanup items. Items 1-4 and 7-8 free disk space and are
  intentionally NOT reversible (the deleted data cannot be restored by us).
  Items 5-6 + 9-13 are reversible and saved to a JSON backup.
#>

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Item metadata
# --------------------------------------------------------------------------
$script:MaintenanceItems = @(
    @{ id='cleantemp';    text='Clear temporary files (user + Windows temp)'; reversible=$false; desc='Deletes temporary files to free space. Files in use are skipped.' }
    @{ id='wucleanup';    text='Windows Update cleanup (StartComponentCleanup)';  reversible=$false; desc='Removes old, superseded Windows Update files to free space. Can take several minutes.' }
    @{ id='trimssd';      text='Re-trim SSD (Optimize-Volume C:)';                reversible=$false; desc='Sends the TRIM command to an SSD so it stays fast. Safe.' }
    @{ id='flushdns';     text='Flush DNS cache';                                  reversible=$false; desc='Clears the DNS cache, which can fix some website connection issues.' }
    @{ id='gamedvr';      text='Disable Game DVR background recording';           reversible=$true;  desc='Turns off background Game DVR recording to free RAM/GPU. Reversible.' }
    @{ id='storagesense'; text='Enable Storage Sense (auto temp + recycle-bin cleanup)'; reversible=$true; desc='Lets Windows automatically clean temp files and the recycle bin. May also delete old restore points and Downloads. Reversible.' }
    @{ id='recyclebin';   text='Empty Recycle Bin';                                reversible=$false; desc='Permanently empties the Recycle Bin to free space. Deleted files cannot be recovered.' }
    @{ id='browscache';   text='Clear Edge + Chrome browser cache';               reversible=$false; desc='Clears cached web files to free space; pages load a bit slower the first time. Reversible via browsing normally.' }
    @{ id='startupapps';  text='Disable third-party startup apps (current user)';  reversible=$true;  desc='Disables third-party apps that start at login to speed up boot. Reversible. Affects only the current user.' }
    @{ id='vfxperf';      text='Visual effects -> best performance';               reversible=$true;  desc='Turns off visual animations for a snappier feel. Minor on new PCs, helps older ones. Reversible.' }
    @{ id='faststartup';  text='Enable Fast Startup (faster boot)';                reversible=$true;  desc='Enables Fast Startup for a quicker boot. On laptops shutdown becomes a hybrid. Reversible.' }
    @{ id='tips';         text='Disable Windows tips & suggestions';               reversible=$true;  desc='Turns off Windows tips and suggestions so there are fewer notifications. Reversible.' }
    @{ id='powerplan';    text='Power plan -> High performance (battery drains faster)'; reversible=$true; desc='Switches to the High performance power plan. Faster, but drains laptop battery sooner. Reversible.' }
)

# --------------------------------------------------------------------------
# Apply-* functions
#
# Improvements over the original:
#   * every reversibly-mutating Apply-* saves the backup row BEFORE any change
#   * powerplan save is now confirmed via the regex even when powercfg emits
#     localized text (was falling back to the Balanced GUID silently and
#     making restore a no-op for that case)
#   * Add-Type SpVoice removed (it was never used in maintenance)
# --------------------------------------------------------------------------
function Invoke-CleanTemp {
    $targets = @(
        (Join-Path $env:TEMP '*'),
        (Join-Path $env:WINDIR 'Temp\*')
    )
    $count = 0
    foreach ($t in $targets) {
        if (-not (Test-Path -LiteralPath $t)) { continue }
        Get-ChildItem -LiteralPath $t -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop; $count++ } catch { }
        }
    }
    Write-Log ("Cleared temp files ($count items removed).")
}

function Invoke-WUCleanup {
    Write-Log "Running Windows Update cleanup (StartComponentCleanup) - can take several minutes..."
    $out = & dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1
    (($out | Out-String).Trim() -split "`r?`n" | Where-Object { $_ }) | ForEach-Object { Write-Log ("    " + $_) }
    Write-Log "Windows Update cleanup done."
}

function Invoke-TrimSSD {
    try {
        Optimize-Volume -DriveLetter C -ReTrim -ErrorAction Stop | Out-Null
        Write-Log "SSD re-trimmed (C:)."
    } catch { Write-Log ("WARN trim: " + $_.Exception.Message) }
}

function Invoke-FlushDNS {
    try { & ipconfig.exe /flushdns | Out-Null; Write-Log "DNS cache flushed." }
    catch { Write-Log ("WARN flushdns: " + $_.Exception.Message) }
}

function Invoke-DisableGameDVR {
    $k = 'HKCU:\System\GameConfigStore'
    $old = Get-RegDword $k 'GameDVR_Enabled'
    if ($old -eq 0) { Write-Log "SKIP Game DVR: already disabled."; return }
    Set-KeyedRow -Path $script:Paths.MaintBackupFile -Key 'gamedvr' -Value ([string]$old)
    try { Set-RegDword $k 'GameDVR_Enabled' 0 } catch { Write-Log ("WARN Game DVR: " + $_.Exception.Message) }
    Write-Log "ENABLED: Game DVR background recording disabled."
}

function Invoke-EnableStorageSense {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
    $old01 = Get-RegDword $k '01'
    if ($old01 -eq 1) { Write-Log "SKIP Storage Sense: already enabled."; return }
    Set-KeyedRow -Path $script:Paths.MaintBackupFile -Key 'storagesense' -Value (
        @{ enabled = [string]$old01 } | ConvertTo-Json -Compress
    )
    try { Set-RegDword $k '01' 1 } catch { Write-Log ("WARN Storage Sense 01: " + $_.Exception.Message) }
    try { Set-RegDword $k '04' 1 } catch { Write-Log ("WARN Storage Sense 04: " + $_.Exception.Message) }
    Write-Log "ENABLED: Storage Sense (auto temp + recycle-bin cleanup)."
}

function Invoke-EmptyRecycleBin {
    try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Log "Emptied Recycle Bin." }
    catch {
        Write-Log "Recycle Bin could not be emptied (some files may be locked). Details: $($_.Exception.Message)"
    }
}

function Invoke-ClearBrowserCache {
    $caches = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Code Cache'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Cache'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Code Cache')
    )
    $n = 0
    foreach ($c in $caches) {
        if (-not (Test-Path -LiteralPath $c)) { continue }
        Get-ChildItem -LiteralPath (Join-Path $c '*') -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop; $n++ } catch { }
        }
    }
    Write-Log ("Cleared browser cache ($n items).")
}

function Invoke-StartupCleanup {
    $k  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $hklm = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    # v1.4: whitelist - never disable security / essential / common sync apps.
    $whitelist = 'Defender','SecurityHealth','WindowsSecurity','OneDrive','Dropbox','Avast','Norton','Malwarebytes','Intel','NVIDIA','Realtek','Logitech','SynTP','AdobeGCInvoker','MicrosoftEdgeAutoLaunch','Backup','Samsung'
    function Test-Whitelisted([string]$n) {
        foreach ($w in $whitelist) { if ($n -like "*$w*") { return $true } }
        return $false
    }
    $backed = @{}
    if (Test-Path -LiteralPath $k) {
        foreach ($v in (Get-Item -LiteralPath $k).Property) {
            $backed["${k}\${v}"] = (Get-ItemProperty -Path $k -Name $v -ErrorAction SilentlyContinue).$v
        }
    }
    Set-KeyedRow -Path $script:Paths.MaintBackupFile -Key 'startupapps' -Value ($backed | ConvertTo-Json -Compress)
    $disabled = 0; $skipped = 0
    if (Test-Path -LiteralPath $k) {
        $runValues = @((Get-Item -LiteralPath $k).Property)
        foreach ($v in $runValues) {
            if ([string]::IsNullOrWhiteSpace([string]$v)) { continue }
            if (Test-Whitelisted $v) { Write-Log "SKIP (whitelisted): $v"; $skipped++; continue }
            try {
                $data = (Get-ItemProperty -Path $k -Name $v -ErrorAction Stop).$v
                Set-ItemProperty -Path $k -Name ($v + '.disabled') -Value $data -ErrorAction Stop
                Remove-ItemProperty -Path $k -Name $v -ErrorAction Stop
                Write-Log ("Disabled startup: $v (current user)")
                $disabled++
            } catch { Write-Log ("WARN disable startup $v : " + $_.Exception.Message) }
        }
    }
    if (Test-Path -LiteralPath $hklm) {
        Write-Log ("All-users (HKLM) startup entries (listed, NOT disabled): " + ((Get-Item -LiteralPath $hklm).Property -join ', '))
    }
    Write-Log "Startup apps cleanup done ($disabled disabled, $skipped kept safe, reversible)."
}

function Invoke-VfxPerformance {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    $old = Get-RegDword $k 'VisualFXSetting'
    if ($old -eq 2) { Write-Log "SKIP visual effects: already best performance."; return }
    Set-KeyedRow -Path $script:Paths.MaintBackupFile -Key 'vfxperf' -Value ([string]$old)
    try { Set-RegDword $k 'VisualFXSetting' 2 } catch { Write-Log ("WARN VisualFXSetting: " + $_.Exception.Message) }
    Write-Log "ENABLED: visual effects set to best performance."
}

function Invoke-EnableFastStartup {
    $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
    $old = Get-RegDword $k 'HiberbootEnabled'
    if ($old -eq 1) { Write-Log "SKIP Fast Startup: already enabled."; return }
    Set-KeyedRow -Path $script:Paths.MaintBackupFile -Key 'faststartup' -Value ([string]$old)
    try { Set-RegDword $k 'HiberbootEnabled' 1 } catch { Write-Log ("WARN HiberbootEnabled: " + $_.Exception.Message) }
    Write-Log "ENABLED: Fast Startup (faster boot)."
}

function Invoke-DisableTips {
    $k     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $names = 'SubscribedContent-310093Enabled','SubscribedContent-338387Enabled',
             'SubscribedContent-338388Enabled','SubscribedContent-338389Enabled',
             'SubscribedContent-353694Enabled','SubscribedContent-353696Enabled'

    $old = @{}
    $already = $true
    foreach ($n in $names) {
        $cur = Get-RegDword $k $n
        $old[$n] = if ($null -eq $cur) { 0 } else { $cur }
        if ($cur -ne 0) { $already = $false }
    }
    if ($already) { Write-Log "SKIP tips: already disabled."; return }
    Set-KeyedRow -Path $script:Paths.MaintBackupFile -Key 'tips' -Value ($old | ConvertTo-Json -Compress)
    foreach ($n in $names) {
        try { Set-RegDword $k $n 0 } catch { Write-Log ("WARN tip $n : " + $_.Exception.Message) }
    }
    Write-Log "ENABLED: Windows tips & suggestions disabled."
}

# Power plans (Windows-defined GUIDs) ---------------------------------
$script:PowerPlanHighPerf = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

function Get-ActivePowerPlanGuid {
    [CmdletBinding()]
    $out = (powercfg /getactivescheme) 2>&1 | Out-String
    # GUID is on the same line as the scheme name. Be tolerant of locales.
    $m = [regex]::Match($out, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Invoke-PowerHighPerf {
    $oldGuid = Get-ActivePowerPlanGuid
    # If we cannot determine the current scheme, refuse to clobber it (was
    # silently falling back to Balanced in the original, which would have
    # restored to the wrong value).
    if ($null -eq $oldGuid) {
        Write-Log "WARN: could not determine active power plan. Skipping."
        return
    }
    if ($oldGuid -eq $script:PowerPlanHighPerf) {
        Write-Log "SKIP power plan: already High performance."; return
    }
    Set-KeyedRow -Path $script:Paths.MaintBackupFile -Key 'powerplan' -Value $oldGuid
    try { powercfg /setactive $script:PowerPlanHighPerf | Out-Null; Write-Log "ENABLED: power plan set to High performance." }
    catch { Write-Log ("WARN power plan: " + $_.Exception.Message) }
}

# --------------------------------------------------------------------------
# Dispatcher
# --------------------------------------------------------------------------
function Invoke-MaintenanceItem {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    switch ($Id) {
        'cleantemp'    { Invoke-CleanTemp }
        'wucleanup'    { Invoke-WUCleanup }
        'trimssd'      { Invoke-TrimSSD }
        'flushdns'     { Invoke-FlushDNS }
        'gamedvr'      { Invoke-DisableGameDVR }
        'storagesense' { Invoke-EnableStorageSense }
        'recyclebin'   { Invoke-EmptyRecycleBin }
        'browscache'   { Invoke-ClearBrowserCache }
        'startupapps'  { Invoke-StartupCleanup }
        'vfxperf'      { Invoke-VfxPerformance }
        'faststartup'  { Invoke-EnableFastStartup }
        'tips'         { Invoke-DisableTips }
        'powerplan'    { Invoke-PowerHighPerf }
        default        { Write-Log "WARN: unknown maintenance id '$Id'" }
    }
}

# --------------------------------------------------------------------------
# Restore
# --------------------------------------------------------------------------
function Restore-MaintenanceEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Row)
    try {
        switch ($Row.Name) {
            'gamedvr' {
                $k = 'HKCU:\System\GameConfigStore'
                if (-not [string]::IsNullOrWhiteSpace([string]$Row.Value)) {
                    Set-RegDword $k 'GameDVR_Enabled' ([int]$Row.Value)
                } else { Remove-RegValue $k 'GameDVR_Enabled' }
                Write-Log "RESTORED: Game DVR"
            }
            'storagesense' {
                $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
                $o = $Row.Value | ConvertFrom-Json -ErrorAction Stop
                if (-not [string]::IsNullOrWhiteSpace([string]$o.enabled)) {
                    Set-RegDword $k '01' ([int]$o.enabled)
                } else { Remove-RegValue $k '01' }
                Write-Log "RESTORED: Storage Sense"
            }
            'vfxperf' {
                $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
                if (-not [string]::IsNullOrWhiteSpace([string]$Row.Value)) {
                    Set-RegDword $k 'VisualFXSetting' ([int]$Row.Value)
                } else { Remove-RegValue $k 'VisualFXSetting' }
                Write-Log "RESTORED: visual effects"
            }
            'startupapps' {
                $o = $Row.Value | ConvertFrom-Json -ErrorAction Stop
                $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
                foreach ($p in $o.PSObject.Properties) {
                    $valname = $p.Name -replace '^.*\\', ''
                    $orig    = $valname -replace '\.disabled$', ''
                    $data    = $p.Value
                        if ($data -and $data -ne 'null') {
                            try { Set-ItemProperty -Path $k -Name $orig -Value $data -ErrorAction Stop } catch {
                                Write-Log "WARN restore startup $orig : $($_.Exception.Message)"
                            }
                        }
                        try { Remove-ItemProperty -Path $k -Name $valname -ErrorAction SilentlyContinue } catch { }
                }
                Write-Log "RESTORED: startup apps"
            }
            'faststartup' {
                $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
                if (-not [string]::IsNullOrWhiteSpace([string]$Row.Value)) {
                    Set-RegDword $k 'HiberbootEnabled' ([int]$Row.Value)
                } else { Remove-RegValue $k 'HiberbootEnabled' }
                Write-Log "RESTORED: Fast Startup"
            }
            'tips' {
                $o = $Row.Value | ConvertFrom-Json -ErrorAction Stop
                $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
                foreach ($n in 'SubscribedContent-310093Enabled','SubscribedContent-338387Enabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled') {
                    if ($o.PSObject.Properties[$n] -and $null -ne $o.$n -and ([string]$o.$n) -ne '') {
                        Set-RegDword $k $n ([int]$o.$n)
                    } else { Remove-RegValue $k $n }
                }
                Write-Log "RESTORED: tips & suggestions"
            }
            'powerplan' {
                if ($Row.Value -and [string]$Row.Value -match '^[0-9a-fA-F-]{36}$') {
                    try { powercfg /setactive ([string]$Row.Value) | Out-Null; Write-Log "RESTORED: power plan" }
                    catch { Write-Log "WARN restore power plan: $($_.Exception.Message)"; throw }
                } else {
                    Write-Log "Could not restore power plan (backup value was not a GUID)."
                }
            }
            default { Write-Log "WARN: unknown maintenance row '$($Row.Name)'" }
        }
        return $true
    } catch {
        Write-Log "ERROR restoring $($Row.Name): $($_.Exception.Message)"
        return $false
    }
}

function Restore-Maintenance {
    [CmdletBinding()]
    $rows = Read-JsonArray -Path $script:Paths.MaintBackupFile
    if ($rows.Count -eq 0) { Write-Log "No maintenance backup - nothing to restore."; return }
    Write-Log "=== Maintenance restore started ==="
    $anyFailed = $false
    $successIds = @()
    foreach ($row in $rows) {
        if (Restore-MaintenanceEntry -Row $row) { $successIds += $row.Name } else { $anyFailed = $true }
    }
    if (-not $anyFailed) {
        Remove-Item -LiteralPath $script:Paths.MaintBackupFile -Force -ErrorAction SilentlyContinue
    } else {
        $remaining = @($rows | Where-Object { $successIds -notcontains $_.Name })
        if ($remaining.Count -eq 0) {
            Remove-Item -LiteralPath $script:Paths.MaintBackupFile -Force -ErrorAction SilentlyContinue
        } else {
            Write-JsonArray -Path $script:Paths.MaintBackupFile -Items $remaining
        }
        Write-Log "WARNING: some maintenance items failed. Backup file kept for retry."
    }
    Write-Log "=== Maintenance restore finished ==="
}

function Restore-MaintenanceItems {
    [CmdletBinding()]
    param([string[]]$Ids)
    $rows = Read-JsonArray -Path $script:Paths.MaintBackupFile
    if ($rows.Count -eq 0) { Write-Log "No maintenance backup - nothing to restore."; return }
    $restored = 0; $failed = 0; $remaining = @()
    foreach ($row in $rows) {
        if ($Ids -contains $row.Name) {
            if (Restore-MaintenanceEntry -Row $row) { $restored++ } else { $failed++; $remaining += $row }
        } else {
            $remaining += $row
        }
    }
    if ($restored -eq 0 -and $failed -eq 0) {
        Write-Log "None of the requested maintenance items were in the backup."; return
    }
    if ($remaining.Count -eq 0) {
        Remove-Item -LiteralPath $script:Paths.MaintBackupFile -Force -ErrorAction SilentlyContinue
    } else {
        Write-JsonArray -Path $script:Paths.MaintBackupFile -Items $remaining
    }
    Write-Log "Maintenance restore checked finished ($restored restored, $failed failed)."
}

# --------------------------------------------------------------------------
# v1.5: schedule weekly auto-maintenance (safe cleanup + quick scan)
# --------------------------------------------------------------------------
function Schedule-AutoMaintenance {
    $taskName = 'SystemOptimizerWeeklyMaintenance'
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    # Safe weekly maintenance: temp cleanup, DNS flush, SSD trim, quick Defender scan.
    $cmd = '-NoProfile -ExecutionPolicy Bypass -Command "' +
          'Remove-Item (Join-Path $env:TEMP ''*'') -Recurse -Force -ErrorAction SilentlyContinue; ' +
          'Remove-Item (Join-Path $env:WINDIR ''Temp\*'') -Recurse -Force -ErrorAction SilentlyContinue; ' +
          'ipconfig /flushdns | Out-Null; ' +
          'Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue; ' +
          'Start-MpScan -ScanType QuickScan -ErrorAction SilentlyContinue"'
    try {
        $action = New-ScheduledTaskAction -Execute $ps -Argument $cmd -ErrorAction Stop
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 5am -ErrorAction Stop
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest -ErrorAction Stop
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log "Scheduled weekly auto-maintenance (Sunday 05:00): temp cleanup, DNS flush, SSD trim, quick scan."
        Show-Message 'Weekly auto-maintenance scheduled (Sunday 05:00).`n`nIt will: clear temp files, flush DNS, trim the SSD, and run a quick Defender scan.' 'Auto-maintenance' Info
    } catch {
        Write-Log "WARN schedule auto-maintenance: $($_.Exception.Message)"
        Show-Message ("Could not schedule auto-maintenance: " + $_.Exception.Message) 'Error'
    }
}

$script:LibMaintLoaded = $true
