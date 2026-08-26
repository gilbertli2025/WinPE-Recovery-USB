<#
.SYNOPSIS
  Backup & Restore user settings, plus a pre-flight readiness check.
  Backs up safe, portable items (browser bookmarks, Wi-Fi profiles, HKCU
  settings, the tool's own profile) to a chosen USB/folder. Passwords are
  intentionally NOT backed up (security risk, not portable) - a password
  manager is recommended instead.

  v1.4 safety: BitLocker is never enabled without a USB drive.
#>

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Pre-flight check - run before applying changes.
# Returns $true if it is safe to proceed, $false otherwise.
# --------------------------------------------------------------------------
function Test-PreFlight {
    [CmdletBinding()]
    param([string[]]$SecurityIds = @(), [string[]]$MaintIds = @())

    $ok = $true

    if (-not (Test-Admin)) {
        Show-Message 'System Optimizer must run as Administrator to make changes. Please restart it as Administrator.' 'Admin required' Error
        Write-Log "PRE-FLIGHT FAIL: not running as admin."
        return $false
    }
    Write-Log "PRE-FLIGHT: admin OK."

    # Enough free space on C: (need at least ~3 GB to be safe)
    try {
        $c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
        $freeGB = [math]::Round($c.FreeSpace/1GB, 1)
        if ($freeGB -lt 3) {
            Show-Message "Low disk space on C: ($freeGB GB free). Optimizer may need space; please free some first." 'Low disk space' Warn
            Write-Log "PRE-FLIGHT WARN: low disk space ($freeGB GB)."
        } else {
            Write-Log "PRE-FLIGHT: free space OK ($freeGB GB)."
        }
    } catch { Write-Log "PRE-FLIGHT WARN: could not check disk space." }

    # System Restore enabled on C: so changes are reversible
    try {
        $rps = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
        if ($rps.Count -eq 0) {
            Show-Message 'No System Restore point found on C:. Consider enabling System Restore (Security item 6) so changes can be rolled back.' 'Restore' Warn
            Write-Log "PRE-FLIGHT WARN: no restore point found."
        } else {
            Write-Log "PRE-FLIGHT: restore point present ($($rps.Count) point(s))."
        }
    } catch { Write-Log "PRE-FLIGHT WARN: could not check restore points." }

    # If BitLocker is being applied, a USB drive must be present (recovery key)
    if ($SecurityIds -contains 'bitlocker') {
        $bl = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
        $alreadyOn = ($bl -and $bl.ProtectionStatus -eq 'On')
        if (-not $alreadyOn) {
            $removable = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1
            if (-not $removable) {
                Show-Message 'BitLocker needs a USB drive to store the recovery key. Plug in a USB drive first, or skip BitLocker.' 'BitLocker' Warn
                Write-Log "PRE-FLIGHT FAIL: BitLocker selected but no USB drive present."
                $ok = $false
            } else {
                Write-Log "PRE-FLIGHT: USB drive present for BitLocker recovery key."
            }
        } else {
            Write-Log "PRE-FLIGHT: BitLocker already on (no change needed)."
        }
    }

    if (-not $ok) { Write-Log 'PRE-FLIGHT: one or more required checks failed.' }
    else { Write-Log 'PRE-FLIGHT: OK to proceed.' }
    return $ok
}

# --------------------------------------------------------------------------
# Backup user settings to a chosen folder (prefer a USB drive).
# --------------------------------------------------------------------------
function Get-BackupTarget {
    if ($script:BackupSession) { return $script:BackupSession }
    # Prefer a removable (USB) drive. Use a per-PC subfolder so one USB can
    # hold backups for several computers and you can tell them apart.
    $removable = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1
    if ($removable) {
        $dir = Join-Path (Join-Path ($removable.DeviceID) 'SystemOptimizer-Backup') $env:COMPUTERNAME
        return $dir
    }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Choose where to save the settings backup (a USB drive is best)'
    if ($dlg.ShowDialog() -eq 'OK') { return (Join-Path $dlg.SelectedPath $env:COMPUTERNAME) }
    return $null
}

function Backup-UserSettings {
    $target = Get-BackupTarget
    if (-not $target) { Show-Message "No backup location was chosen, so nothing was backed up.`n`nPlug in a USB drive and try again.`n`nClick OK to continue." 'Backup' Warn; return }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Write-Log "Backing up user settings to: $target"

    # 1) Browser bookmarks
    $bk = 0
    foreach ($b in @('Microsoft\Edge','Google\Chrome')) {
        $bookmark = Join-Path $env:LOCALAPPDATA ("$b\User Data\Default\Bookmarks")
        if (Test-Path -LiteralPath $bookmark) {
            $dest = Join-Path $target ("bookmarks-" + ($b.Split('\')[-1]) + ".json")
            Copy-Item -LiteralPath $bookmark -Destination $dest -Force
            Write-Log "  Backed up bookmarks: $($b.Split('\')[-1])"
            $bk++
        }
    }
    if ($bk -eq 0) { Write-Log "  No browser bookmarks found (Edge/Chrome)." }

    # 2) Wi-Fi profiles
    try {
        $wifi = Join-Path $target 'wifi'
        New-Item -ItemType Directory -Path $wifi -Force | Out-Null
        & netsh.exe wlan export profile folder=$wifi key=clear 2>&1 | Out-Null
        $wc = @(Get-ChildItem $wifi -Filter '*.xml' -ErrorAction SilentlyContinue).Count
        Write-Log "  Backed up Wi-Fi profiles: $wc"
    } catch { Write-Log "  Wi-Fi export failed: $($_.Exception.Message)" }

    # 3) User settings (HKCU) as a .reg snapshot
    try {
        $regFile = Join-Path $target ("HKCU-settings-" + $env:COMPUTERNAME + ".reg")
        & reg.exe export "HKCU" $regFile /y 2>&1 | Out-Null
        Write-Log "  Backed up user registry settings (HKCU).reg."
    } catch { Write-Log "  HKCU export failed: $($_.Exception.Message)" }

    # 4) The tool's own profile (checked checkboxes)
    try {
        $profile = Join-Path $target 'SystemOptimizer-profile.json'
        @{
            services = @($script:svcChecks  | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
            security = @($script:secChecks   | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
            maint    = @($script:maintChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
            repair   = @($script:repairChecks| Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        } | ConvertTo-Json | Set-Content -LiteralPath $profile -Encoding UTF8
        Write-Log "  Backed up System Optimizer profile."
    } catch { Write-Log "  Profile export failed: $($_.Exception.Message)" }

    # 5) BitLocker recovery key (if the drive is encrypted) - saved with the backup
    try {
        $bl = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
        if ($bl -and $bl.ProtectionStatus -eq 'On') {
            $rp = $bl.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } | Select-Object -First 1
            if ($rp) {
                $kf = Join-Path $target "BitLocker-Recovery-Key-$env:COMPUTERNAME.txt"
                Backup-BitLockerKeyProtector -MountPoint 'C:' -KeyProtectorId $rp.KeyProtectorId -KeyPath $kf -ErrorAction SilentlyContinue | Out-Null
                Write-Log "  Backed up BitLocker recovery key to the backup folder."
            }
        }
    } catch { Write-Log "  BitLocker key backup skipped: $($_.Exception.Message)" }

    Write-Log "Backup complete. Location: $target"
    Show-Message "Your settings were backed up to:`n`n$target`n`nThis backup is safe to keep on your USB drive.`n`nClick OK to continue. You can switch to any tab when ready." 'Backup done' Info
    Write-Log "NOTE: passwords are NOT backed up (security). Use a password manager for those."
}

# --------------------------------------------------------------------------
# Verify that a backup folder is complete/readable.
# --------------------------------------------------------------------------
function Get-ChosenBackupFolder {
    # Prefer the USB latest session if present; else let the user pick.
    $sess = Get-LatestBackupSession
    if ($sess -and (Test-Path $sess)) { return $sess }
    $removable = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1
    if ($removable) {
        $cand = Join-Path (Join-Path ($removable.DeviceID) 'SystemOptimizer-Backup') $env:COMPUTERNAME
        if (Test-Path $cand) { return $cand }
    }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Choose the backup folder'
    if ($dlg.ShowDialog() -eq 'OK') { return $dlg.SelectedPath }
    return $null
}

function Test-BackupIntegrity {
    $src = Get-ChosenBackupFolder
    if (-not $src) { Show-Message 'No backup folder chosen.' 'Verify' Warn; return $false }
    if (-not (Test-Path $src)) { Show-Message 'Backup folder not found.' 'Verify' Warn; return $false }
    $files = @(Get-ChildItem $src -File -ErrorAction SilentlyContinue)
    $wifiCount = @(Get-ChildItem (Join-Path $src 'wifi') -Filter '*.xml' -ErrorAction SilentlyContinue).Count
    Write-Log "Verifying backup in: $src"
    foreach ($f in $files) { Write-Log ("  " + $f.Name + "  (" + $f.Length + " bytes)") }
    Write-Log ("  Wi-Fi profiles: " + $wifiCount)
    $ok = ($files.Count -gt 0)
    $wifiTxt = if ($wifiCount -gt 0) { "`nWi-Fi profiles: $wifiCount" } else { "" }
    Show-Message ("Your backup is OK - $($files.Count) file(s) are present and readable.$wifiTxt`n`nClick OK to continue.") 'Backup verified' Info
    return $ok
}

# --------------------------------------------------------------------------
# Restore user settings from a chosen folder.
# --------------------------------------------------------------------------
function Restore-UserSettings {
    [CmdletBinding()]
    param([string]$Source)
    $src = if ($Source) { $Source } else { Get-ChosenBackupFolder }
    if (-not $src) { return }
    if (-not (Test-Path $src)) { Show-Message 'Backup folder not found.' 'Restore' Warn; return }
    Write-Log "Restoring user settings from: $src"

    $restored = 0
    foreach ($b in @(@('Edge','Microsoft\Edge'), @('Chrome','Google\Chrome'))) {
        $bookmark = Join-Path $src ("bookmarks-" + $b[0] + ".json")
        if (Test-Path -LiteralPath $bookmark) {
            $dest = Join-Path $env:LOCALAPPDATA ("$($b[1])\User Data\Default\Bookmarks")
            if (Test-Path -LiteralPath (Split-Path $dest)) {
                Copy-Item -LiteralPath $bookmark -Destination $dest -Force
                Write-Log "  Restored bookmarks: $($b[0])"
                $restored++
            }
        }
    }

    # Wi-Fi profiles
    $wifi = Join-Path $src 'wifi'
    if (Test-Path $wifi) {
        Get-ChildItem $wifi -Filter '*.xml' -ErrorAction SilentlyContinue | ForEach-Object {
            & netsh.exe wlan add profile filename="$($_.FullName)" user=current 2>&1 | Out-Null
        }
        Write-Log "  Restored Wi-Fi profiles."
        $restored++
    }

    # HKCU registry - warn: only reliable on the SAME PC / same user. On a
    # different PC the user account SID differs, so settings may not fully apply.
    $regFile = Get-ChildItem $src -Filter 'HKCU-settings-*.reg' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($regFile) {
        $samePc = ($regFile.Name -like "*$env:COMPUTERNAME*")
        if (-not $samePc -and -not (Show-YesNo "This registry backup is from another PC. Registry settings may not fully transfer.`n`nImport it anyway?" 'Restore' Warn)) {
            Write-Log "  Skipped registry restore (from a different PC)."
        } else {
            try {
                $out = & reg.exe import $regFile.FullName 2>&1
                Write-Log "  Restored user registry settings. (You may need to sign out/in for full effect.)"
                $restored++
            } catch {
                Write-Log "  Registry restore skipped (import failed - this is harmless, other settings were still restored): $($_.Exception.Message)"
            }
        }
    }

    if ($restored -eq 0) { Write-Log "No restorable settings found in $src." }
    else { Write-Log "Restore complete." }
    Show-Message "Restore finished.`n`nYour browser bookmarks and Wi-Fi profiles were restored.`n`nSome settings need you to sign out and back in (or restart) to take effect.`n`nClick OK to continue." 'Restore done' Info
}

# --------------------------------------------------------------------------
# Run BEFORE applying any changes: create a System Restore point (so system
# changes can be rolled back) and, if a USB is present, offer to back up the
# user settings first.
# --------------------------------------------------------------------------
function Invoke-PreApplyBackup {
    # 1) System Restore point (system-level rollback safety net)
    try {
        Checkpoint-Computer -Description 'System Optimizer - before changes' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop | Out-Null
        Write-Log "Created a System Restore point before applying."
    } catch { Write-Log "WARN could not create restore point: $($_.Exception.Message)" }

    # 2) If a USB drive is present, offer to back up user settings first.
    $rem = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1
    if ($rem) {
        if (Show-YesNo "A USB drive ($($rem.DeviceID)) is present.`n`nBack up your user settings to it first? This is recommended before making changes." 'Back up first?' Question) {
            Backup-UserSettings
        }
    }
}

$script:LibBackupLoaded = $true
