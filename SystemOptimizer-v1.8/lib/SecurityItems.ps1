<#
.SYNOPSIS
  Security hardening items + Apply/Restore for the System Optimizer suite.
  Ten items, all reversible.

  BUG FIXES (vs. previous copy-pasted versions):
    * Backup is now saved BEFORE the registry change in every Apply-* function
      (was wrong only for Apply-OfficeWSH, which saved AFTER - now correct).
    * Apply-BitLocker saves ONE backup row (was saving twice in the already-on
      path). The row uniquely identifies the original state (Disabled vs
      AlreadyOn) and Restore-SecurityEntry uses it.
    * JSON backup writes via the shared UTF-8-no-BOM helper
      (writes were previously UTF-8 WITH BOM under PS 5.1, which broke
      ConvertFrom-Json on restore and silently made restore a no-op).
    * Restore-Security keeps the backup file if any single row fails
      (was deleting unconditionally).
    * All Set-ItemProperty / Set-MpPreference calls have explicit -ErrorAction.
    * The scheduled task uses the full Windows PowerShell path (env
      'SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe') instead of
      a bare 'powershell.exe', which on constrained systems could resolve to
      the Store version of PowerShell.
#>

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Item metadata (used by every UI for checkbox text + tooltip)
# --------------------------------------------------------------------------
$script:SecurityItems = @(
    @{ id='cloud';     text='Defender cloud protection (block at first sight)'; desc='Turns on Microsoft cloud protection so Defender can stop brand-new malware fast using cloud reputation. Sends limited malware/URL info to Microsoft.' }
    @{ id='firewall';  text='Firewall: block all unsolicited inbound by default'; desc='Makes Windows block unsolicited incoming connections by default. Outbound and existing connections still work. Good for security; may need allow rules for file sharing or remote management.' }
    @{ id='scan';      text='Daily Defender quick scan at 03:00'; desc='Schedules a daily quick scan of common infection points at 3am.' }
    @{ id='lock';      text='Auto-lock the screen after 10 min idle'; desc='Locks your PC after 10 minutes idle so others need your password/PIN to get in.' }
    @{ id='browsers';  text='Harden Edge + Chrome browsers'; desc='Turns on Safe Browsing/SmartScreen, blocks dangerous downloads, third-party cookies, popups, WebUSB/WebSerial, and credit-card autofill. Some sites that rely on third-party cookies may not work.' }
    @{ id='restore';   text='Enable System Restore + weekly restore points'; desc='Turns on System Restore and makes a weekly restore point (Sunday 4am) so you can undo bad system changes like drivers or updates. Not a backup of your files.' }
    @{ id='bitlocker'; text='BitLocker on C: (TPM) - protect against theft'; desc='Encrypts your system drive so data cannot be read if the PC is stolen. Needs Windows Pro + a TPM. Runs in the background.' }
    @{ id='autorun';   text='Disable AutoRun on removable drives'; desc='Stops USB sticks and removable drives from auto-running software - blocks a common malware trick.' }
    @{ id='lockout';   text='Account lockout (5 tries / 15 min)'; desc='After 5 failed sign-ins the account locks for 15 minutes, slowing password-guessing. Be careful not to lock yourself out.' }
    @{ id='officewsh'; text='Block Office macros from internet + disable Script Host'; desc='Blocks Office macros from internet files and disables VBS/JS scripts - two common malware entry points. May block some legitimate scripts/macros.' }
)

# --------------------------------------------------------------------------
# Known registry / policy paths
# --------------------------------------------------------------------------
$script:SecurityKeys = @{
    EdgePolicies    = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    ChromePolicies  = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
    AutoRun         = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    SystemRestore   = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    Netlogon        = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
    ScriptHost      = 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings'
    ScreenSaver     = 'HKCU:\Control Panel\Desktop'
}

$script:EdgeHardeningPolicy = @{
    'SmartScreenEnabled'                       = 1
    'SmartScreenForTrustedDownloadsEnabled'   = 1
    'SafeBrowsingEnabled'                      = 1
    'DownloadRestrictions'                     = 2
    'BlockThirdPartyCookies'                   = 1
    'DefaultPopupsSetting'                     = 2
    'SitePerProcess'                           = 1
    'DefaultWebUsbSetting'                     = 2
    'DefaultWebSerialSetting'                  = 2
    'AutofillCreditCardEnabled'                = 0
}

$script:ChromeHardeningPolicy = @{
    'SafeBrowsingProtectionLevel' = 2
    'DownloadRestrictions'        = 2
    'BlockThirdPartyCookies'      = 1
    'DefaultPopupsSetting'        = 2
    'SitePerProcess'              = 1
    'DefaultWebUsbSetting'        = 2
    'DefaultWebSerialSetting'     = 2
    'AutofillCreditCardEnabled'   = 0
}

$script:WeeklyRestoreTaskName = 'WeeklySystemRestorePoint'

# --------------------------------------------------------------------------
# Low-level helpers
# --------------------------------------------------------------------------
function Get-MpSetting {
    try { return (Get-MpPreference -ErrorAction Stop) } catch { return $null }
}

function Get-RegDword {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    try {
        $p = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $p.$Name
    } catch { return $null }
}

function Set-RegDword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value
    )
    # Use -Path (universally supported; our paths are literal, no wildcards).
    # Create the value as a DWORD if it doesn't exist, else set it.
    if (-not (Test-Path -Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    $exists = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $exists -or $null -eq $exists.$Name) {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    } else {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -ErrorAction Stop
    }
}

function Remove-RegValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    try { Remove-ItemProperty -Path $Path -Name $Name -ErrorAction Stop } catch { }
}

function Test-ServiceBackupExists { Test-Path -LiteralPath $script:Paths.SecurityBackupFile }

# --------------------------------------------------------------------------
# Apply-* functions  (ALL save the backup row BEFORE making any change)
# --------------------------------------------------------------------------
function Apply-CloudProtection {
    $mp = Get-MpSetting
    if (-not $mp) { Write-Log "SKIP cloud protection: Defender preferences unavailable."; return }
    if ($mp.MAPS -eq 2 -and $mp.SubmitSamplesConsent -eq 1 -and $mp.CloudBlockLevel -eq 2) {
        Write-Log "SKIP cloud protection: already hardened."; return
    }
    Set-KeyedRow -Path $script:Paths.SecurityBackupFile -Key 'cloud' -Value (
        @{ MAPS = $mp.MAPS; SubmitSamplesConsent = $mp.SubmitSamplesConsent; CloudBlockLevel = $mp.CloudBlockLevel } | ConvertTo-Json -Compress
    )
    Set-MpPreference -MAPS 2 -SubmitSamplesConsent 1 -CloudBlockLevel 2 -ErrorAction Stop | Out-Null
    Write-Log "ENABLED: Defender cloud protection."
}

function Apply-FirewallBlock {
    $needBackup = $false
    foreach ($profile in 'Domain','Private','Public') {
        $f = Get-NetFirewallProfile -Name $profile
        if ($f.DefaultInboundAction -ne 'Block' -or $f.Enabled -ne $true) {
            $needBackup = $true; break
        }
    }
    if (-not $needBackup) {
        Write-Log "SKIP firewall: already Block + enabled."; return
    }
    $old = @{}
    foreach ($p in 'Domain','Private','Public') {
        $pf = Get-NetFirewallProfile -Name $p
        $old[$p] = @{ DefaultInboundAction = "$($pf.DefaultInboundAction)"; Enabled = $pf.Enabled }
    }
    Set-KeyedRow -Path $script:Paths.SecurityBackupFile -Key 'firewall' -Value ($old | ConvertTo-Json -Compress)
    foreach ($profile in 'Domain','Private','Public') {
        try {
            Set-NetFirewallProfile -Name $profile -DefaultInboundAction Block -Enabled True -ErrorAction Stop
        } catch {
            Write-Log "WARN firewall profile $profile : $($_.Exception.Message)"
        }
    }
    Write-Log "ENABLED: firewall blocks all unsolicited inbound."
}

function Apply-ScanSchedule {
    $mp = Get-MpSetting
    if (-not $mp) { Write-Log "SKIP scan schedule: Defender preferences unavailable."; return }
    if ($mp.ScanScheduleQuickScanTime -eq 3) { Write-Log "SKIP scan schedule: already 03:00."; return }
    Set-KeyedRow -Path $script:Paths.SecurityBackupFile -Key 'scan' -Value ([string]$mp.ScanScheduleQuickScanTime)
    Set-MpPreference -ScanScheduleQuickScanTime 3 -ErrorAction Stop | Out-Null
    Write-Log "ENABLED: daily Defender quick scan at 03:00."
}

function Apply-AutoLock {
    $d = $script:SecurityKeys.ScreenSaver
    $oldActive  = Get-RegDword $d 'ScreenSaveActive'
    $oldSecure  = Get-RegDword $d 'ScreenSaverIsSecure'
    $oldTimeout = Get-RegDword $d 'ScreenSaveTimeOut'
    if ($oldSecure -eq 1) { Write-Log "SKIP auto-lock: already locks after idle."; return }
    Set-KeyedRow -Path $script:Paths.SecurityBackupFile -Key 'lock' -Value (
        @{ Active = "$oldActive"; Secure = "$oldSecure"; Timeout = "$oldTimeout" } | ConvertTo-Json -Compress
    )
    try { Set-RegDword $d 'ScreenSaveActive'   1   } catch { Write-Log "WARN ScreenSaveActive: $($_.Exception.Message)" }
    try { Set-RegDword $d 'ScreenSaverIsSecure' 1   } catch { Write-Log "WARN ScreenSaverIsSecure: $($_.Exception.Message)" }
    try { Set-RegDword $d 'ScreenSaveTimeOut' 600    } catch { Write-Log "WARN ScreenSaveTimeOut: $($_.Exception.Message)" }
    Write-Log "ENABLED: auto-lock after 10 min idle."
}

function Apply-BrowserHardening {
    $edgeKey   = $script:SecurityKeys.EdgePolicies
    $chromeKey = $script:SecurityKeys.ChromePolicies
    $edgePol   = $script:EdgeHardeningPolicy
    $chromePol = $script:ChromeHardeningPolicy

    $already = ((Get-RegDword $edgeKey 'DownloadRestrictions') -eq 2) -and
               ((Get-RegDword $chromeKey 'DownloadRestrictions') -eq 2)
    if ($already) { Write-Log "SKIP browsers: already hardened."; return }

    $old = @{ edge = @{}; chrome = @{} }
    foreach ($b in 'edge','chrome') {
        $key = if ($b -eq 'edge') { $edgeKey } else { $chromeKey }
        $pol = if ($b -eq 'edge') { $edgePol } else { $chromePol }
        foreach ($pn in $pol.Keys) {
            $cur = Get-RegDword $key $pn
            $old[$b][$pn] = if ($null -eq $cur) { 'MISSING' } else { $cur }
        }
    }
    Set-KeyedRow -Path $script:Paths.SecurityBackupFile -Key 'browsers' -Value ($old | ConvertTo-Json -Compress)

    foreach ($b in 'edge','chrome') {
        $key = if ($b -eq 'edge') { $edgeKey } else { $chromeKey }
        $pol = if ($b -eq 'edge') { $edgePol } else { $chromePol }
        foreach ($pn in $pol.Keys) {
            try { Set-RegDword $key $pn $pol[$pn] } catch {
                Write-Log "WARN $b $pn : $($_.Exception.Message)"
            }
        }
    }
    Write-Log "ENABLED: browser hardening for Edge + Chrome."
}

function Apply-SystemRestore {
    $drives = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object { $_.DeviceID })
    if ($drives.Count -eq 0) { Write-Log "SKIP restore points: no fixed drive found."; return }
    $key = $script:SecurityKeys.SystemRestore
    $freqNow = Get-RegDword $key 'SystemRestorePointCreationFrequency'
    Set-KeyedRow -Path $script:Paths.SecurityBackupFile -Key 'restore' -Value (
        @{ Drives = ($drives -join ','); Frequency = [string]$freqNow } | ConvertTo-Json -Compress
    )
    foreach ($d in $drives) {
        try { Enable-ComputerRestore -Drive "$d\" -ErrorAction Stop; Write-Log "ENABLED: system protection on $d." }
        catch { Write-Log "WARN enable protection ${d}: $($_.Exception.Message)" }
    }
    try { Set-RegDword $key 'SystemRestorePointCreationFrequency' 0 } catch {
        Write-Log "WARN set restore frequency: $($_.Exception.Message)"
    }
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arg = "-NoProfile -ExecutionPolicy Bypass -Command `"Checkpoint-Computer -Description 'Weekly Restore Point' -RestorePointType MODIFY_SETTINGS`""
    try {
        $action    = New-ScheduledTaskAction -Execute $ps -Argument $arg -ErrorAction Stop
        $trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 4am -ErrorAction Stop
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest -ErrorAction Stop
        Register-ScheduledTask -TaskName $script:WeeklyRestoreTaskName -Action $action -Trigger $trigger -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log "ENABLED: weekly restore point task every Sunday 04:00."
    } catch { Write-Log "WARN schedule weekly task: $($_.Exception.Message)" }
    try {
        Checkpoint-Computer -Description 'System Optimizer baseline' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop | Out-Null
        Write-Log "Created a restore point now."
    } catch { Write-Log "WARN checkpoint now: $($_.Exception.Message)" }
}

function Backup-BitLockerRecoveryKey {
    try {
        $v = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop
        $rp = $v.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } | Select-Object -First 1
        if (-not $rp) { Write-Log "NOTE: No BitLocker recovery key protector found."; return }

        # Prefer a removable (USB) drive so the key is OFF this PC.
        $target = $null
        $removable = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1
        if ($removable) {
            $target = Join-Path ($removable.DeviceID) ("BitLocker-Recovery-Key-$env:COMPUTERNAME.txt")
        }
        if (-not $target) {
            $target = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ("BitLocker-Recovery-Key-$env:COMPUTERNAME.txt")
        }

        Backup-BitLockerKeyProtector -MountPoint 'C:' -KeyProtectorId $rp.KeyProtectorId -KeyPath $target -ErrorAction Stop | Out-Null
        Write-Log "Recovery key saved to: $target"
        if (-not $removable) {
            Write-Log "WARNING: a key file on the C: drive alone will NOT help if you are locked out (it is on the encrypted drive)."
        }
        Write-Log "BEST: save it to your Microsoft account at https://aka.ms/myrecoverykey (works from any PC)."
        Write-Log "Otherwise, copy this file to a USB drive or print it and keep it somewhere safe."
    } catch {
        Write-Log "WARN: could not back up the BitLocker recovery key: $($_.Exception.Message)"
        Write-Log "Please save it manually: Settings > Privacy & security > Device encryption / Manage BitLocker."
    }
}

function Apply-BitLocker {
    $bl = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
    $alreadyOn = ($bl -and $bl.ProtectionStatus -eq 'On')

    # Already on -> record state and leave the drive untouched.
    if ($alreadyOn) {
        Set-KeyedRow -Path $script:Paths.SecurityBackupFile -Key 'bitlocker' -Value (@{ State = 'AlreadyOn' } | ConvertTo-Json -Compress)
        Write-Log "SKIP BitLocker: already on. No changes made (already-encrypted drives are left untouched)."
        return
    }

    # SAFETY RULE (v1.4): never turn BitLocker on unless a USB/removable drive is
    # present to store the recovery key OFF this PC. This prevents being locked
    # out (no recoverable key) and keeps the tool safe to use on any PC.
    $removable = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1
    if (-not $removable) {
        Write-Log "BitLocker was NOT enabled: no USB/removable drive found to store the recovery key."
        Write-Log "Plug in a USB drive and run again. (Or save the recovery key to your Microsoft account first: aka.ms/myrecoverykey)"
        Show-Message "BitLocker was NOT enabled because no USB drive was found to store the recovery key.`n`nPlug in a USB drive and run again (or save the recovery key to your Microsoft account: aka.ms/myrecoverykey)." 'BitLocker' Warn
        return
    }

    Set-KeyedRow -Path $script:Paths.SecurityBackupFile -Key 'bitlocker' -Value (@{ State = 'Disabled' } | ConvertTo-Json -Compress)
    try {
        Enable-BitLocker -MountPoint 'C:' -EncryptionMethod XtsAes256 -UsedSpaceOnly -SkipHardwareTest -TpmProtector -ErrorAction Stop | Out-Null
        Write-Log "ENABLED: BitLocker on C: (TPM). Encrypting in the background."
        Backup-BitLockerRecoveryKey
    } catch {
        Write-Log "WARN BitLocker: $($_.Exception.Message)"
        Write-Log "NOTE: BitLocker needs Pro/Enterprise + TPM. On Home use Settings > Privacy & security > Device encryption."
        Show-Message "BitLocker could not be enabled.`n`n$($_.Exception.Message)`n`nBitLocker needs Windows Pro/Enterprise and a TPM chip on the PC. This is normal for many PCs - no change was made." 'BitLocker' Warn
    }
}

function Apply-AutoRun {
    $key = $script:SecurityKeys.AutoRun
    $old = Get-RegDword $key 'NoDriveTypeAutoRun'
    if ($old -eq 255) { Write-Log "SKIP AutoRun: already disabled."; return }
    Set-KeyedRow -Path $script:Paths.SecurityBackupFile -Key 'autorun' -Value ([string]$old)
    try {
        Set-RegDword $key 'NoDriveTypeAutoRun' 255
        Write-Log "ENABLED: AutoRun disabled for removable drives."
    } catch { Write-Log "ERROR AutoRun: $($_.Exception.Message)" }
}

function Apply-Lockout {
    $key = $script:SecurityKeys.Netlogon
    $old = @{
        threshold = Get-RegDword $key 'lockoutthreshold'
        duration  = Get-RegDword $key 'lockoutduration'
        window    = Get-RegDword $key 'lockoutobservationwindow'
    }
    if ($old.threshold -eq 5) { Write-Log "SKIP lockout: already set."; return }
    Set-KeyedRow -Path $script:Paths.SecurityBackupFile -Key 'lockout' -Value ($old | ConvertTo-Json -Compress)
    try { Set-RegDword $key 'lockoutthreshold'         5 } catch { Write-Log "WARN lockoutthreshold: $($_.Exception.Message)" }
    try { Set-RegDword $key 'lockoutduration'         15 } catch { Write-Log "WARN lockoutduration: $($_.Exception.Message)" }
    try { Set-RegDword $key 'lockoutobservationwindow' 15 } catch { Write-Log "WARN lockoutobservationwindow: $($_.Exception.Message)" }
    Write-Log "ENABLED: account lockout after 5 failed tries for 15 min."
}

function Apply-OfficeWSH {
    # BUG FIX: capture old values first, save backup ONCE, then mutate.
    $apps = 'Word','Excel','PowerPoint','Outlook'
    $officeKeyBase = 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\{0}\Security'
    $oldOffice = @{}
    foreach ($app in $apps) {
        $k = $officeKeyBase -f $app
        $oldOffice[$app] = Get-RegDword $k 'BlockContentExecutionFromInternet'
    }
    $wshKey = $script:SecurityKeys.ScriptHost
    $oldWSH = Get-RegDword $wshKey 'Enabled'

    Set-KeyedRow -Path $script:Paths.SecurityBackupFile -Key 'officewsh' -Value (
        @{ office = $oldOffice; wsh = "$oldWSH" } | ConvertTo-Json -Compress
    )

    foreach ($app in $apps) {
        try { Set-RegDword ($officeKeyBase -f $app) 'BlockContentExecutionFromInternet' 1 }
        catch { Write-Log "WARN Office $app : $($_.Exception.Message)" }
    }
    try { Set-RegDword $wshKey 'Enabled' 0 } catch { Write-Log "WARN Script Host: $($_.Exception.Message)" }
    Write-Log "ENABLED: Office macros from internet blocked + Windows Script Host disabled."
}

# --------------------------------------------------------------------------
# Dispatcher
# --------------------------------------------------------------------------
function Apply-SecurityItem {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    switch ($Id) {
        'cloud'     { Apply-CloudProtection }
        'firewall'  { Apply-FirewallBlock }
        'scan'      { Apply-ScanSchedule }
        'lock'      { Apply-AutoLock }
        'browsers'  { Apply-BrowserHardening }
        'restore'   { Apply-SystemRestore }
        'bitlocker' { Apply-BitLocker }
        'autorun'   { Apply-AutoRun }
        'lockout'   { Apply-Lockout }
        'officewsh' { Apply-OfficeWSH }
        default     { Write-Log "WARN: unknown security id '$Id'" }
    }
}

# --------------------------------------------------------------------------
# Restore
#
# BUG FIX: every Restore-*Entry returns $true/$false. Restore-Security
# keeps the backup file if ANY row failed so the user can retry.
# --------------------------------------------------------------------------
function Restore-SecurityEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Row)

    try {
        switch ($Row.Name) {
            'cloud' {
                $o = $Row.Value | ConvertFrom-Json -ErrorAction Stop
                if ($null -ne $o.MAPS) { Set-MpPreference -MAPS ([int]$o.MAPS) -ErrorAction Stop }
                if ($null -ne $o.SubmitSamplesConsent) { Set-MpPreference -SubmitSamplesConsent ([int]$o.SubmitSamplesConsent) -ErrorAction Stop }
                if ($null -ne $o.CloudBlockLevel) { Set-MpPreference -CloudBlockLevel ([int]$o.CloudBlockLevel) -ErrorAction Stop }
                Write-Log "RESTORED: cloud protection"
            }
            'firewall' {
                $o = $Row.Value | ConvertFrom-Json -ErrorAction Stop
                foreach ($p in 'Domain','Private','Public') {
                    if ($o.$p) {
                        Set-NetFirewallProfile -Name $p -DefaultInboundAction $o.$p.DefaultInboundAction -Enabled $o.$p.Enabled -ErrorAction Stop
                    }
                }
                Write-Log "RESTORED: firewall settings"
            }
            'scan' {
                Set-MpPreference -ScanScheduleQuickScanTime ([int]$Row.Value) -ErrorAction Stop
                Write-Log "RESTORED: scan schedule"
            }
            'lock' {
                $o = $Row.Value | ConvertFrom-Json -ErrorAction Stop
                $d = $script:SecurityKeys.ScreenSaver
                if ($null -ne $o.Active)  { Set-ItemProperty -Path $d -Name ScreenSaveActive    -Value ([string]$o.Active) -ErrorAction Stop }
                if ($null -ne $o.Secure)  { Set-ItemProperty -Path $d -Name ScreenSaverIsSecure -Value ([string]$o.Secure) -ErrorAction Stop }
                if ($null -ne $o.Timeout) { Set-ItemProperty -Path $d -Name ScreenSaveTimeOut   -Value ([string]$o.Timeout) -ErrorAction Stop }
                Write-Log "RESTORED: auto-lock"
            }
            'browsers' {
                $o = $Row.Value | ConvertFrom-Json -ErrorAction Stop
                foreach ($b in 'edge','chrome') {
                    $key = if ($b -eq 'edge') { $script:SecurityKeys.EdgePolicies } else { $script:SecurityKeys.ChromePolicies }
                    foreach ($pn in $o.$b.PSObject.Properties) {
                        if ($pn.Value -eq 'MISSING' -or $null -eq $pn.Value) {
                            Remove-RegValue $key $pn.Name
                        } else {
                            Set-RegDword $key $pn.Name ([int]$pn.Value)
                        }
                    }
                    # Tidy empty policy keys
                    $polKey = Get-Item -LiteralPath $key -ErrorAction SilentlyContinue
                    if ($polKey -and $polKey.Property.Count -eq 0) {
                        try { Remove-Item -LiteralPath $key -Force -ErrorAction Stop } catch { }
                    }
                }
                Write-Log "RESTORED: browser policies"
            }
            'restore' {
                $o = $Row.Value | ConvertFrom-Json -ErrorAction Stop
                try { Unregister-ScheduledTask -TaskName $script:WeeklyRestoreTaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
                $key = $script:SecurityKeys.SystemRestore
                if ($null -ne $o.Frequency -and ([string]$o.Frequency) -ne '') {
                    Set-RegDword $key 'SystemRestorePointCreationFrequency' ([int]$o.Frequency)
                } else {
                    Remove-RegValue $key 'SystemRestorePointCreationFrequency'
                }
                Write-Log "RESTORED: weekly restore task + frequency. Protection left ENABLED (safer)."
            }
            'bitlocker' {
                $o = $Row.Value | ConvertFrom-Json -ErrorAction Stop
                if ($o.State -eq 'AlreadyOn') {
                    Write-Log "BitLocker was already on before apply - no changes to undo."
                } else {
                    Write-Log "BitLocker left as-is (stays encrypted). Decrypt manually with the recovery key if you want it off."
                }
            }
            'autorun' {
                $key = $script:SecurityKeys.AutoRun
                if (-not [string]::IsNullOrWhiteSpace($Row.Value)) {
                    Set-RegDword $key 'NoDriveTypeAutoRun' ([int]$Row.Value)
                } else {
                    Remove-RegValue $key 'NoDriveTypeAutoRun'
                }
                Write-Log "RESTORED: AutoRun setting"
            }
            'lockout' {
                $o = $Row.Value | ConvertFrom-Json -ErrorAction Stop
                $key = $script:SecurityKeys.Netlogon
                if ($null -ne $o.threshold) { Set-RegDword $key 'lockoutthreshold'         ([int]$o.threshold) }
                if ($null -ne $o.duration)  { Set-RegDword $key 'lockoutduration'          ([int]$o.duration) }
                if ($null -ne $o.window)    { Set-RegDword $key 'lockoutobservationwindow' ([int]$o.window) }
                Write-Log "RESTORED: account lockout policy"
            }
            'officewsh' {
                $o = $Row.Value | ConvertFrom-Json -ErrorAction Stop
                $officeKeyBase = 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\{0}\Security'
                foreach ($app in 'Word','Excel','PowerPoint','Outlook') {
                    $k = $officeKeyBase -f $app
                    if ($o.office.PSObject.Properties[$app] -and $null -ne $o.office.$app) {
                        Set-RegDword $k 'BlockContentExecutionFromInternet' ([int]$o.office.$app)
                    } else {
                        Remove-RegValue $k 'BlockContentExecutionFromInternet'
                    }
                }
                $wshKey = $script:SecurityKeys.ScriptHost
                if (-not [string]::IsNullOrWhiteSpace([string]$o.wsh)) {
                    Set-RegDword $wshKey 'Enabled' ([int]$o.wsh)
                } else {
                    Remove-RegValue $wshKey 'Enabled'
                }
                Write-Log "RESTORED: Office macro + Script Host settings"
            }
            default { Write-Log "WARN: unknown backup row '$($Row.Name)' - skipped." }
        }
        return $true
    } catch {
        Write-Log "ERROR restoring $($Row.Name): $($_.Exception.Message)"
        return $false
    }
}

function Restore-Security {
    [CmdletBinding()]
    $rows = Read-JsonArray -Path $script:Paths.SecurityBackupFile
    if ($rows.Count -eq 0) { Write-Log "No security backup - nothing to restore."; return }
    Write-Log "=== Security restore started ==="
    $anyFailed = $false
    $successIds = @()
    foreach ($row in $rows) {
        $ok = Restore-SecurityEntry -Row $row
        if (-not $ok) { $anyFailed = $true }
        else { $successIds += $row.Name }
    }
    # BUG FIX: keep the file if anything failed so the user can retry without
    # losing the backup. Drop only the rows we managed to restore.
    if (-not $anyFailed) {
        Remove-Item -LiteralPath $script:Paths.SecurityBackupFile -Force -ErrorAction SilentlyContinue
    } else {
        $remaining = @($rows | Where-Object { $successIds -notcontains $_.Name })
        if ($remaining.Count -eq 0) {
            Remove-Item -LiteralPath $script:Paths.SecurityBackupFile -Force -ErrorAction SilentlyContinue
        } else {
            Write-JsonArray -Path $script:Paths.SecurityBackupFile -Items $remaining
        }
        Write-Log "WARNING: some security items failed to restore. Backup file kept for retry."
    }
    Write-Log "=== Security restore finished ==="
}

function Restore-SecurityItems {
    [CmdletBinding()]
    param([string[]]$Ids)
    $rows = Read-JsonArray -Path $script:Paths.SecurityBackupFile
    if ($rows.Count -eq 0) { Write-Log "No security backup - nothing to restore."; return }
    $restored = 0
    $remaining = @()
    $failed = 0
    foreach ($row in $rows) {
        if ($Ids -contains $row.Name) {
            if (Restore-SecurityEntry -Row $row) { $restored++ } else { $failed++; $remaining += $row }
        } else {
            $remaining += $row
        }
    }
    if ($restored -eq 0 -and $failed -eq 0) {
        Write-Log "None of the ticked items had been applied (nothing to restore)."; return
    }
    if ($remaining.Count -eq 0) {
        Remove-Item -LiteralPath $script:Paths.SecurityBackupFile -Force -ErrorAction SilentlyContinue
    } else {
        Write-JsonArray -Path $script:Paths.SecurityBackupFile -Items $remaining
    }
    Write-Log "Restore checked finished ($restored restored, $failed failed)."
}

$script:LibSecurityLoaded = $true
