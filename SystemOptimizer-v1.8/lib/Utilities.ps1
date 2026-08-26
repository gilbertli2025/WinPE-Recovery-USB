<#
.SYNOPSIS
  V1.6 Utilities: duplicate-file finder, disk analyzer, large-file finder.
  All are READ-ONLY scans that return data; deletions go to the Recycle Bin
  only (never permanent) via Remove-ToRecycleBin. The GUI shows previews and
  requires explicit confirmation before deleting.
#>

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

# Disk analyzer: return immediate subfolders of $Path with recursive sizes.
function Get-DiskUsage {
    [CmdletBinding()]
    param([string]$Path, [int]$Top = 20)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $results = @()
    foreach ($dir in (Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue)) {
        $size = (Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum
        $results += [pscustomobject]@{ Name = $dir.Name; Path = $dir.FullName; SizeMB = [math]::Round($size/1MB, 1) }
    }
    $results | Sort-Object SizeMB -Descending | Select-Object -First $Top
}

# Large-file finder: top files over a minimum size.
function Find-LargeFiles {
    [CmdletBinding()]
    param([string]$Path, [double]$MinimumMB = 100, [int]$Top = 30)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $min = [long]($MinimumMB * 1MB)
    Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge $min } |
        Sort-Object Length -Descending |
        Select-Object -First $Top |
        ForEach-Object { [pscustomobject]@{ Name = $_.Name; Path = $_.FullName; SizeMB = [math]::Round($_.Length/1MB,1) } }
}

# Duplicate-file finder: group by size, then hash candidates. Returns groups.
function Find-DuplicateFiles {
    [CmdletBinding()]
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }

    # 1) group files by size (candidates only)
    $bySize = @{}
    foreach ($f in (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue)) {
        if ($f.Length -gt 0) {
            $k = $f.Length
            if (-not $bySize.ContainsKey($k)) { $bySize[$k] = [System.Collections.ArrayList]::new() }
            [void]$bySize[$k].Add($f)
        }
    }

    # 2) hash each size-group that has 2+ members
    $groups = [System.Collections.ArrayList]::new()
    foreach ($k in $bySize.Keys) {
        $pile = $bySize[$k]
        if ($pile.Count -ge 2) {
            $byHash = @{}
            foreach ($f in $pile) {
                $h = $null
                try { $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA1 -ErrorAction Stop).Hash } catch { $h = $null }
                if ($h) {
                    if (-not $byHash.ContainsKey($h)) { $byHash[$h] = [System.Collections.ArrayList]::new() }
                    [void]$byHash[$h].Add($f)
                }
            }
            foreach ($h in $byHash.Keys) {
                $dup = $byHash[$h]
                if ($dup.Count -gt 1) {
                    $members = @()
                    foreach ($f in $dup) { $members += [pscustomobject]@{ Path = $f.FullName; SizeMB = [math]::Round($f.Length/1MB,1) } }
                    [void]$groups.Add([pscustomobject]@{ Hash = $h; Files = $members })
                }
            }
        }
    }
    ,$groups
}

# Find .lnk shortcuts whose target no longer exists (broken). Read-only scan.
function Find-BrokenShortcuts {
    [CmdletBinding()]
    param([string[]]$Paths = @(([Environment]::GetFolderPath('Desktop')), (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu')))
    $broken = New-Object System.Collections.Generic.List[object]
    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch { return @() }
    foreach ($p in $Paths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        Get-ChildItem -LiteralPath $p -Recurse -Filter *.lnk -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $sc = $shell.CreateShortcut($_.FullName)
                $target = $sc.TargetPath
                if ($target -and -not (Test-Path -LiteralPath $target)) {
                    $broken.Add([pscustomobject]@{ Path = $_.FullName; Target = $target; SizeMB = [math]::Round($_.Length/1MB,1) })
                }
            } catch { }
        }
    }
    return ,$broken
}

# Drive health (SMART) - read-only report: status, temp, wear, size.
function Get-DriveHealth {
    $rows = New-Object System.Collections.Generic.List[object]
    try {
        Get-PhysicalDisk -ErrorAction SilentlyContinue | ForEach-Object {
            $d = $_
            $rel = $null; try { $rel = Get-StorageReliabilityCounter -PhysicalDisk $d -ErrorAction Stop } catch { }
            $temp = if ($rel -and $rel.Temperature) { $rel.Temperature } else { $null }
            $wear = if ($rel -and $null -ne $rel.Wear) { [math]::Round($rel.Wear, 0) } else { $null }
            $rows.Add([pscustomobject]@{
                Name = $d.FriendlyName
                Status = [string]$d.HealthStatus
                SizeGB = [math]::Round($d.Size/1GB, 0)
                TempC = $temp
                WearPct = $wear
            })
        }
    } catch { Write-Log "Drive health unavailable: $($_.Exception.Message)" }
    return ,$rows
}

# Network repair - DNS flush + Winsock reset (safe, needs admin). Returns output.
function Invoke-NetworkRepair {
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add('--- ipconfig /flushdns ---')
    $out.Add((ipconfig.exe /flushdns 2>&1 | Out-String).Trim())
    $out.Add('--- netsh winsock reset ---')
    $out.Add((netsh.exe winsock reset 2>&1 | Out-String).Trim())
    return ,$out
}

# Read-only system health summary + recommendations.
function Get-SystemHealthReport {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('SYSTEM HEALTH CHECK')
    try { $c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"; $free = [math]::Round($c.FreeSpace/1GB,1); $lines.Add(('Disk C: free space: ' + $free + ' GB')) } catch { $lines.Add('Disk C: ?') }
    try { $os = Get-CimInstance Win32_OperatingSystem; $up = [math]::Round((New-TimeSpan -Start $os.LastBootUpTime -End (Get-Date)).TotalDays,1); $lines.Add('Uptime: ' + $up + ' day(s)') } catch { }
    try { $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue; $lines.Add('Windows Defender: ' + $(if ($mp.RealTimeProtectionEnabled) { 'On' } else { 'Off' })) } catch { }
    try { $st = Get-StartupEntries; $lines.Add('Startup items: ' + $st.Count) } catch { }
    $lines.Add('')
    $lines.Add('Suggestions:')
    $lines.Add('  - Keep Windows and your apps updated')
    $lines.Add('  - Back up your settings & files to this USB regularly')
    $lines.Add('  - Keep this USB drive safe (it holds your backup + recovery key)')
    return ,$lines
}

# Read-only PC health score (0-100) + recommendations.
function Get-PcHealthScore {
    $score = 100
    $recs = New-Object System.Collections.Generic.List[string]
    try {
        $c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $freePct = ($c.FreeSpace / $c.Size) * 100
        if ($freePct -lt 10) { $score -= 25; $recs.Add('Low disk space on C: - free up some space.') }
        elseif ($freePct -lt 20) { $score -= 10; $recs.Add('C: free space is getting low - free up space.') }
    } catch { }
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $used = (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100
        if ($used -gt 90) { $score -= 20; $recs.Add('High RAM usage - close some programs.') }
        elseif ($used -gt 80) { $score -= 10 }
    } catch { }
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $up = (New-TimeSpan -Start $os.LastBootUpTime -End (Get-Date)).TotalDays
        if ($up -gt 14) { $score -= 10; $recs.Add('PC has been on over 14 days - a restart can help.') }
    } catch { }
    try {
        $avNames = Get-ActiveAntivirus
        if ($avNames.Count -eq 0) { $score -= 20; $recs.Add('No active antivirus - turn on Windows Defender or your antivirus.') }
    } catch { }
    try {
        $st = Get-StartupEntries
        if ($st.Count -gt 10) { $score -= 10; $recs.Add('Many startup items - consider disabling some.') }
    } catch { }
    if (-not (Test-UsbPresent)) { $score -= 5 }
    $score = [math]::Max(0, [math]::Min(100, $score))
    return [pscustomobject]@{ Score = $score; Recommendations = @($recs) }
}

# Returns the names of antivirus products whose real-time protection is ON,
# including third-party AV (Webroot, Norton, Bitdefender, OpenText, etc.) read
# from Windows Security Center. Falls back to Windows Defender.
function Get-ActiveAntivirus {
    $names = New-Object System.Collections.Generic.List[string]
    try {
        $av = @(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue)
        foreach ($p in $av) { if (($p.productState -band 0x1000) -ne 0) { $names.Add([string]$p.displayName) } }
    } catch { }
    if ($names.Count -eq 0) {
        $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($mp -and $mp.RealTimeProtectionEnabled) { $names.Add('Windows Defender') }
    }
    return $names.ToArray()
}

# Full read-only health check with a per-item breakdown (score + reasons).
# Used by the Health tab so users can compare the score before and after a mode.
function Get-HealthCheck {
    $rows = New-Object System.Collections.Generic.List[object]
    $score = 100
    $now = Get-Date
    $fmt = 'yyyy-MM-dd HH:mm'
    $rows.Add([pscustomobject]@{Name='Checked'; Status='OK'; Detail=$now.ToString($fmt)})
    $avNames = Get-ActiveAntivirus
    if ($avNames.Count -ge 1) { $rows.Add([pscustomobject]@{Name='Antivirus';Status='OK';Detail=('Protection is on: ' + ($avNames -join ', '))}) }
    else { $score -= 20; $rows.Add([pscustomobject]@{Name='Antivirus';Status='Fail';Detail='No active antivirus detected - turn on Windows Defender or your antivirus'}) }
    try {
        $profiles = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue | Where-Object { $_.Enabled })
        if ($profiles.Count -ge 1) { $rows.Add([pscustomobject]@{Name='Windows Firewall';Status='OK';Detail='Firewall is on'}) }
        else { $score -= 15; $rows.Add([pscustomobject]@{Name='Windows Firewall';Status='Fail';Detail='Firewall appears to be OFF - turn it on'}) }
    } catch { $rows.Add([pscustomobject]@{Name='Windows Firewall';Status='?';Detail='could not be checked'}) }
    try {
        $c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $freePct = ($c.FreeSpace / $c.Size) * 100
        if ($freePct -lt 10) { $score -= 25; $rows.Add([pscustomobject]@{Name='Disk space (C:)';Status='Fail';Detail=("{0:N0}% free - free up some space" -f $freePct)}) }
        elseif ($freePct -lt 20) { $score -= 10; $rows.Add([pscustomobject]@{Name='Disk space (C:)';Status='Warn';Detail=("{0:N0}% free - getting low" -f $freePct)}) }
        else { $rows.Add([pscustomobject]@{Name='Disk space (C:)';Status='OK';Detail=("{0:N0}% free" -f $freePct)}) }
    } catch { $rows.Add([pscustomobject]@{Name='Disk space (C:)';Status='?';Detail='could not be checked'}) }
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $used = (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100
        if ($used -gt 90) { $score -= 20; $rows.Add([pscustomobject]@{Name='Memory (RAM)';Status='Fail';Detail=("{0:N0}% in use - close some programs" -f $used)}) }
        elseif ($used -gt 80) { $score -= 10; $rows.Add([pscustomobject]@{Name='Memory (RAM)';Status='Warn';Detail=("{0:N0}% in use" -f $used)}) }
        else { $rows.Add([pscustomobject]@{Name='Memory (RAM)';Status='OK';Detail=("{0:N0}% in use" -f $used)}) }
        $up = (New-TimeSpan -Start $os.LastBootUpTime -End $now).TotalDays
        if ($up -gt 14) { $score -= 10; $rows.Add([pscustomobject]@{Name='Restart (uptime)';Status='Warn';Detail=("{0:N0} day(s) since restart - a restart can help" -f $up)}) }
        else { $rows.Add([pscustomobject]@{Name='Restart (uptime)';Status='OK';Detail=("{0:N0} day(s) since restart" -f $up)}) }
    } catch { $rows.Add([pscustomobject]@{Name='Memory / restart';Status='?';Detail='could not be checked'}) }
    try {
        $st = Get-StartupEntries
        $cnt = $st.Count
        if ($cnt -gt 10) { $score -= 10; $rows.Add([pscustomobject]@{Name='Startup items';Status='Warn';Detail=("$cnt startup items - consider disabling some")}) }
        else { $rows.Add([pscustomobject]@{Name='Startup items';Status='OK';Detail=("$cnt startup item(s)")}) }
    } catch { $rows.Add([pscustomobject]@{Name='Startup items';Status='?';Detail='could not be checked'}) }
    try {
        if (Test-UsbPresent) { $rows.Add([pscustomobject]@{Name='Backup USB';Status='OK';Detail='A USB drive is connected'}) }
        else { $score -= 5; $rows.Add([pscustomobject]@{Name='Backup USB';Status='Warn';Detail='No USB drive - connect one to run One-Click Optimize'}) }
    } catch { }
    try {
        $bi = Get-LastBackupInfo
        if ($bi) { $bd = $(if ($bi.Date) { $bi.Date } else { 'found' }); $rows.Add([pscustomobject]@{Name='Last backup';Status='OK';Detail=("Settings backup: " + $bd)}) }
        else { $score -= 5; $rows.Add([pscustomobject]@{Name='Last backup';Status='Warn';Detail='No settings backup found yet'}) }
    } catch { $rows.Add([pscustomobject]@{Name='Last backup';Status='?';Detail='could not be checked'}) }
    try {
        $bad = @(Get-DriveHealth | Where-Object { $_.Status -ne 'Healthy' })
        if ($bad.Count -eq 0) { $rows.Add([pscustomobject]@{Name='Drive health';Status='OK';Detail='All drives report healthy'}) }
        else { $score -= 20; $rows.Add([pscustomobject]@{Name='Drive health';Status='Fail';Detail=(($bad | ForEach-Object { $_.Name + ': ' + $_.Status }) -join '; ')}) }
    } catch { $rows.Add([pscustomobject]@{Name='Drive health';Status='?';Detail='could not be checked'}) }
    try {
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $score -= 5; $rows.Add([pscustomobject]@{Name='Windows Update';Status='Warn';Detail='Restart pending to finish updates'}) }
        else { $rows.Add([pscustomobject]@{Name='Windows Update';Status='OK';Detail='No restart pending'}) }
    } catch { }
    $score = [math]::Max(0, [math]::Min(100, $score))
    return [pscustomobject]@{ Score=$score; Rows=$rows.ToArray(); Checked=$now.ToString($fmt) }
}

# Safe, reversible performance tweaks for a smoother feel.
function Invoke-PerformanceBoost {
    & powercfg.exe /setactive SCHEME_MIN 2>&1 | Out-Null
    try { Set-ItemProperty -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0 -Type DWord -ErrorAction Stop } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 2 -Type DWord -ErrorAction Stop } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAnimations' -Value 0 -Type DWord -ErrorAction Stop } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value 0 -Type DWord -ErrorAction Stop } catch { }
    Write-Log 'Performance Boost applied (High Performance power plan, Game DVR off, visual effects on performance).'
}
function Invoke-PerformanceRestore {
    & powercfg.exe /setactive SCHEME_BALANCED 2>&1 | Out-Null
    try { Set-ItemProperty -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 1 -Type DWord -ErrorAction Stop } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 0 -Type DWord -ErrorAction Stop } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAnimations' -Value 1 -Type DWord -ErrorAction Stop } catch { }
    try { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value 1 -Type DWord -ErrorAction Stop } catch { }
    Write-Log 'Performance Boost reverted to Windows defaults.'
}

# Read-only system report (OS / CPU / RAM / disk / network / uptime) as text.
function Get-SystemReport {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('SYSTEM REPORT')
    try { $os = Get-CimInstance Win32_OperatingSystem; $lines.Add('OS: ' + $os.Caption + '  ' + $os.Version) } catch { }
    try { $cs = Get-CimInstance Win32_ComputerSystem; $lines.Add('Computer: ' + $cs.Manufacturer + ' ' + $cs.Model) } catch { }
    try { $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1; $lines.Add('CPU: ' + $cpu.Name.Trim()) } catch { }
    try { $os = Get-CimInstance Win32_OperatingSystem; $lines.Add('RAM: ' + [math]::Round($os.TotalVisibleMemorySize/1MB,1) + ' GB total, ' + [math]::Round($os.FreePhysicalMemory/1MB,1) + ' GB free') } catch { }
    try { $c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"; $lines.Add('C: drive ' + [math]::Round($c.Size/1GB,0) + ' GB, ' + [math]::Round($c.FreeSpace/1GB,1) + ' GB free') } catch { }
    try { Get-PhysicalDisk -ErrorAction SilentlyContinue | ForEach-Object { $lines.Add('Disk: ' + $_.FriendlyName + ' (' + $_.HealthStatus + ')') } } catch { }
    try { $os = Get-CimInstance Win32_OperatingSystem; $up = [math]::Round((New-TimeSpan -Start $os.LastBootUpTime -End (Get-Date)).TotalDays,1); $lines.Add('Uptime: ' + $up + ' day(s)') } catch { }
    try { $n = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" | Select-Object -First 2; foreach ($x in $n) { if ($x.IPAddress) { $lines.Add('Network IP: ' + ($x.IPAddress -join ', ')) } } } catch { }
    $lines.Add('')
    $lines.Add('Generated: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    return ,$lines
}

# Read-only hardware info report.
function Get-HardwareInfo {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('HARDWARE INFO')
    try { $cs = Get-CimInstance Win32_ComputerSystem; $lines.Add('Computer: ' + $cs.Manufacturer + ' ' + $cs.Model) } catch { }
    try { $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1; $lines.Add('CPU: ' + $cpu.Name.Trim() + '  (' + $cpu.NumberOfCores + ' cores / ' + $cpu.NumberOfLogicalProcessors + ' threads)') } catch { }
    try { $gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1; $lines.Add('GPU: ' + $gpu.Name) } catch { }
    try { $mem = Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum; $lines.Add('RAM: ' + [math]::Round($mem.Sum/1GB,1) + ' GB') } catch { }
    try { $mo = Get-CimInstance Win32_BaseBoard; $lines.Add('Motherboard: ' + $mo.Manufacturer + ' ' + $mo.Product) } catch { }
    try { $bios = Get-CimInstance Win32_BIOS; $lines.Add('BIOS: ' + $bios.Manufacturer + ' ' + $bios.SMBIOSBIOSVersion) } catch { }
    $lines.Add('')
    $lines.Add('Generated: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    return ,$lines
}

# Network diagnostics: ping + traceroute to a target.
function Invoke-NetworkDiagnostics([string]$Target = 'www.google.com') {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('--- ping ' + $Target + ' ---')
    $lines.Add((ping.exe -n 4 $Target 2>&1 | Out-String).Trim())
    $lines.Add('')
    $lines.Add('--- traceroute ' + $Target + ' ---')
    $lines.Add((tracert.exe -d -h 8 $Target 2>&1 | Out-String).Trim())
    return ,$lines
}

# Generate a battery health report (opens the folder / returns the path).
function New-BatteryReport {
    $out = Join-Path $env:TEMP ("battery-report-" + $env:COMPUTERNAME + ".html")
    & powercfg.exe /batteryreport /output $out 2>&1 | Out-Null
    if (Test-Path $out) { Start-Process $out | Out-Null }
    return $out
}

# List apps with available updates (winget). Review-only (no install).
function Get-AppUpdates {
    $lines = New-Object System.Collections.Generic.List[string]
    try {
        $u = winget.exe upgrade --disable-interactivity 2>$null
        $rows = @($u | Select-Object -Skip 1 | Where-Object { $_ -and $_ -notmatch '^-{3,}' })
        foreach ($r in $rows) {
            $parts = $r -split '\s{2,}'
            if ($parts.Count -ge 2) { $lines.Add($parts[0].Trim() + '  ->  ' + $parts[1].Trim()) }
        }
        if ($lines.Count -eq 0) { $lines.Add('No app updates available right now.') }
    } catch { $lines.Add('Could not check for updates.') }
    $lines.Add('')
    $lines.Add('HOW TO UPDATE:')
    $lines.Add('  - To update them all: open Terminal (admin) and run:  winget upgrade --all')
    $lines.Add('  - Or open the Microsoft Store and click Update.')
    return ,$lines
}

# Delete to Recycle Bin (safe). Returns count deleted.
function Remove-ToRecycleBin {
    [CmdletBinding()]
    param([string[]]$Paths)
    $n = 0
    foreach ($p in $Paths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (Test-Path -LiteralPath $p) {
            try {
                $item = Get-Item -LiteralPath $p
                if ($item.PSIsContainer) {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
                } else {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
                }
                $n++
            } catch { Write-Log "  could not delete $p : $($_.Exception.Message)" }
        }
    }
    return $n
}

$script:LibUtilitiesLoaded = $true
