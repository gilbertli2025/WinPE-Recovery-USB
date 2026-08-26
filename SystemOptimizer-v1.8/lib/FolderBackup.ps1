<#
.SYNOPSIS
  Folder backup & restore for V1.6. Backs up a user's personal folders
  (Documents, Pictures, Music, Videos, Downloads, Desktop) to the USB using
  robocopy (fast incremental mirror - only copies changed files). Also
  exports the installed-programs list and tracks last-backup time (for the
  reminder). Restore lets the user pick folders and/or specific files.
#>

$ErrorActionPreference = 'Stop'

# Display name -> real folder path on THIS PC.
function Get-UserFolderMap {
    $up = [Environment]::GetFolderPath('UserProfile')
    [ordered]@{
        'Documents' = [Environment]::GetFolderPath('MyDocuments')
        'Pictures'  = [Environment]::GetFolderPath('MyPictures')
        'Music'     = [Environment]::GetFolderPath('MyMusic')
        'Videos'    = [Environment]::GetFolderPath('MyVideos')
        'Downloads' = (Join-Path $up 'Downloads')
        'Desktop'   = [Environment]::GetFolderPath('Desktop')
    }
}

# Default backup base on the USB for a given PC: X:\SystemOptimizer-Backup\<PC>
function Get-BackupBase([string]$ComputerName = $env:COMPUTERNAME) {
    $rem = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1
    if ($rem) { return Join-Path (Join-Path $rem.DeviceID 'SystemOptimizer-Backup') $ComputerName }
    return $null
}

# Create a new timestamped backup session folder (keeps a backup history).
# Rotates: keeps the newest 7 sessions on the USB.
function New-BackupSession([string]$ComputerName = $env:COMPUTERNAME) {
    $base = Get-BackupBase $ComputerName
    if (-not $base) { return $null }
    if (-not (Test-Path $base)) { New-Item -ItemType Directory -Path $base -Force | Out-Null }
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $session = Join-Path $base $ts
    New-Item -ItemType Directory -Path $session -Force | Out-Null
    try {
        $old = @(Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{8}-\d{6}$' } | Sort-Object Name -Descending)
        if ($old.Count -gt 7) { $old | Select-Object -Skip 7 | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
    } catch { }
    return $session
}

# Latest backup session (for restore). Falls back to the base folder.
function Get-LatestBackupSession([string]$ComputerName = $env:COMPUTERNAME) {
    $base = Get-BackupBase $ComputerName
    if (-not $base -or -not (Test-Path $base)) { return $null }
    $sessions = @(Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{8}-\d{6}$' } | Sort-Object Name -Descending)
    if ($sessions.Count -gt 0) { return $sessions[0].FullName }
    return $base
}

# Total size (GB) of the folders One-Click would back up (only selected ones).
function Get-BackupSizeGB([string[]]$Folders = @('Documents','Pictures','Music','Videos','Downloads','Desktop')) {
    $map = Get-UserFolderMap
    $total = 0L
    foreach ($k in $Folders) {
        $p = $map[$k]
        if ($p -and (Test-Path -LiteralPath $p)) {
            try { $total += (Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } catch { }
        }
    }
    return [math]::Round($total / 1GB, 2)
}

# Free space (GB) on the attached USB drive, or $null if none.
function Get-UsbFreeSpaceGB {
    $rem = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1
    if (-not $rem) { return $null }
    return [math]::Round($rem.FreeSpace / 1GB, 2)
}

# List all per-PC backup folders present on the USB (for "restore to another PC").
# Returns each PC's latest timestamped session when available.
function Get-UsbBackupFolders {
    $rem = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1
    if (-not $rem) { return @() }
    $root = Join-Path $rem.DeviceID 'SystemOptimizer-Backup'
    if (-not (Test-Path $root)) { return @() }
    $result = @()
    foreach ($pc in (Get-ChildItem $root -Directory -ErrorAction SilentlyContinue)) {
        $sessions = @(Get-ChildItem $pc.FullName -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{8}-\d{6}$' } | Sort-Object Name -Descending)
        if ($sessions.Count -gt 0) { $result += $sessions[0].FullName } else { $result += $pc.FullName }
    }
    return $result
}

function Invoke-Robocopy([string]$Src, [string]$Dst, [string[]]$Items) {
    $args = @($Src, $Dst) + $Items + @('/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NP', '/NJH')
    & robocopy.exe $args 2>&1 | Out-Null
    return $LASTEXITCODE   # 0-7 success, >=8 failure
}

# Back up selected user folders to the USB. Returns $true on success.
function Backup-UserFolders {
    [CmdletBinding()]
    param([string[]]$Folders = @('Documents','Pictures','Music','Videos','Downloads','Desktop'), [string]$Target)

    if (-not $Target) { $Target = if ($script:BackupSession) { $script:BackupSession } else { Get-BackupBase }; if (-not $Target) { Show-Message "No USB drive found to back up to.`n`nPlug in a USB drive and try again.`n`nClick OK to continue." 'Backup' Warn; return $false } }
    New-Item -ItemType Directory -Path $Target -Force | Out-Null

    $map = Get-UserFolderMap
    $filesRoot = Join-Path $Target 'files'
    New-Item -ItemType Directory -Path $filesRoot -Force | Out-Null

    $ok = $true; $copied = @()
    foreach ($n in $Folders) {
        $src = $map[$n]
        if ($src -and (Test-Path -LiteralPath $src)) {
            $dst = Join-Path $filesRoot $n
            $code = Invoke-Robocopy $src $dst
            if ($code -lt 8) { Write-Log "  backed up $n"; $copied += $n }
            else { $ok = $false; Write-Log "  FAILED $n (robocopy exit $code)" }
        } else {
            Write-Log "  skip $n (folder not present)"
        }
    }

    @{ LastBackup = (Get-Date -Format o); Folders = $copied } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Target 'backup-info.json') -Encoding UTF8

    Write-Log "Folder backup complete -> $Target"
    return $ok
}

# Restore folders and/or specific files/sub-folders from a backup folder.
# Selections: hashtable DisplayName -> $true (whole folder) OR -> array of
# relative items (files/subfolders) inside that folder's backup.
function Restore-UserFolders {
    [CmdletBinding()]
    param([string]$Source, [hashtable]$Selections)

    if (-not (Test-Path -LiteralPath $Source)) { Show-Message "Backup folder not found:`n$Source`n`nClick OK to continue." 'Restore' Warn; return }
    $filesRoot = Join-Path $Source 'files'
    $map = Get-UserFolderMap
    $restored = 0

    foreach ($n in $Selections.Keys) {
        $bkDir = Join-Path $filesRoot $n
        $dst = $map[$n]
        if ((Test-Path -LiteralPath $bkDir) -and $dst) {
            $sel = $Selections[$n]
            if ($sel -is [bool] -and $sel) {
                $code = Invoke-Robocopy $bkDir $dst
                if ($code -lt 8) { Write-Log "  restored folder $n"; $restored++ } else { Write-Log "  FAILED restore $n (exit $code)" }
            } elseif ($sel -is [System.Collections.IList]) {
                foreach ($it in $sel) {
                    $s = Join-Path $bkDir $it
                    if (Test-Path -LiteralPath $s) {
                        $parent = Split-Path -Parent $s
                        $leaf = Split-Path -Leaf $s
                        $code = Invoke-Robocopy $parent $dst $leaf
                        if ($code -lt 8) { Write-Log "  restored $n\$it"; $restored++ }
                }
            }
        }
    }
    Write-Log ("Restore finished. Folders/items restored: " + $restored)
    return ($restored -gt 0)
}
}

# Save a list of installed programs to the backup (for the recovery guide).
function Export-InstalledPrograms {
    [CmdletBinding()]
    param([string]$Target)
    if (-not $Target) { $Target = if ($script:BackupSession) { $script:BackupSession } else { Get-BackupBase }; if (-not $Target) { Show-Message "No USB drive found.`n`nClick OK to continue." 'Export' Warn; return $null } }
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    $out = Join-Path $Target 'InstalledPrograms.txt'
    $names = [System.Collections.Generic.HashSet[string]]::new()
    # 1) traditional installs (registry DisplayName - clean list)
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object DisplayName | ForEach-Object { if ($_.DisplayName) { [void]$names.Add([string]$_.DisplayName) } }
    # 2) Store apps via winget - take only the Name column (skip header/separator)
    try {
        winget.exe list --disable-interactivity --accept-source-agreements 2>$null |
            Select-Object -Skip 1 | ForEach-Object {
                $line = $_.TrimEnd()
                if ($line -notmatch '^-{3,}') {
                    $name = ($line -split '\s{2,}')[0]
                    if ($name -and $name.Trim()) { [void]$names.Add($name.Trim()) }
                }
            }
    } catch { }
    $clean = @($names) | Where-Object { $_ } | Sort-Object -Unique
    $clean | Set-Content -LiteralPath $out -Encoding UTF8
    Write-Log ("Program list exported (" + $clean.Count + " programs) -> " + $out)
    return $out
}

# Read the last-backup info marker (for the reminder / health card).
function Get-LastBackupInfo {
    [CmdletBinding()]
    param([string]$Target)
    if (-not $Target) { $Target = Get-LatestBackupSession }
    if (-not $Target -or -not (Test-Path (Join-Path $Target 'backup-info.json'))) { return $null }
    try { return (Get-Content (Join-Path $Target 'backup-info.json') -Raw | ConvertFrom-Json) } catch { return $null }
}

$script:LibFolderBackupLoaded = $true
