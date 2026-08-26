# ============================================================================
#  Profile Repair Utility  (safe + reversible)
#  Lists every Windows user profile, shows its health, backs up a profile
#  folder, and can fix a "temporary profile" (State 1 -> 0).
#  Run it by double-clicking ProfileRepair.cmd
# ============================================================================

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

trap {
    try { [System.Windows.Forms.MessageBox]::Show(("Profile Repair error:`n`n" + $_), 'Profile Repair', 'OK', 'Error') | Out-Null } catch { }
    exit 1
}

$script:GuideFile = Join-Path (Split-Path $MyInvocation.MyCommand.Path) 'UserProfile-Repair-Guide.txt'
$script:ProfileKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

function Get-Profiles {
    $rows = @()
    try {
        Get-ChildItem $script:ProfileKey -ErrorAction SilentlyContinue | Where-Object {
            $_.PSChildName -like 'S-1-5-21-*'
        } | ForEach-Object {
            $sid = $_.PSChildName
            try { $props = Get-ItemProperty $_.PSPath } catch { $props = @{} }
            $state = $props.State; if ($null -eq $state) { $state = -1 }
            $img   = $props.ProfileImagePath
            $account = '(unknown)'
            try {
                $account = (New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate(
                    [System.Security.Principal.NTAccount]).Value
            } catch { }
            $exists = if ($img) { Test-Path $img } else { $false }
            $status = 'OK'
            if ($state -eq 1) { $status = 'TEMPORARY' }
            elseif ($state -eq 2) { $status = 'INACTIVE' }
            elseif (-not $exists) { $status = 'MISSING FOLDER' }
            elseif ($state -ne 0) { $status = 'CHECK' }
            $rows += [pscustomobject]@{
                SID=$sid; Account=$account; State=$state; Folder=$img; Exists=$exists; Status=$status
            }
        }
    } catch { }
    return $rows
}

function Get-SelectedRow {
    if ($lst.SelectedItems.Count -eq 0) { return $null }
    return $lst.SelectedItems[0].Tag
}

function Load-List {
    $lst.Items.Clear()
    $rows = @()
    try { $rows = Get-Profiles } catch { }
    foreach ($r in $rows) {
        $item = New-Object System.Windows.Forms.ListViewItem($r.Status)
        [void]$item.SubItems.Add($r.Account)
        [void]$item.SubItems.Add($r.SID)
        [void]$item.SubItems.Add($(if ($r.State -lt 0) { '?' } else { "$($r.State)" }))
        [void]$item.SubItems.Add($(if ($r.Exists) { 'Yes' } else { 'No' }))
        [void]$item.SubItems.Add($r.Folder)
        $item.Tag = $r
        if ($r.Status -eq 'OK') { $item.ForeColor = [System.Drawing.Color]::Green }
        elseif ($r.Status -eq 'TEMPORARY') { $item.ForeColor = [System.Drawing.Color]::FromArgb(200,120,0) }
        elseif ($r.Status -eq 'INACTIVE' -or $r.Status -eq 'MISSING FOLDER') { $item.ForeColor = [System.Drawing.Color]::Red }
        $lst.Items.Add($item) | Out-Null
    }
    if ($rows.Count -eq 0) {
        $script:lblStatus.Text = "No user profiles found (checked $script:ProfileKey). Check that this PC has a normal sign-in account."
        $script:lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(200,60,60)
    } else {
        $script:lblStatus.Text = "Found $($rows.Count) user profile(s). Select one, then Back up before any fix."
        $script:lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(60,120,60)
    }
}

function Show-Msg($msg) {
    [System.Windows.Forms.MessageBox]::Show($msg, 'Profile Repair', 'OK', 'Information') | Out-Null
}

# --- buttons ----------------------------------------------------------------
function Backup-Profile {
    $r = Get-SelectedRow
    if (-not $r) { Show-Msg 'Please select a profile in the list first.'; return }
    $base = $r.Folder
    if (-not $base) { $base = 'C:\Users\' + ($r.Account -split '\\')[-1] }
    if (-not $r.Exists) {
        if ([System.Windows.Forms.MessageBox]::Show(
            "The folder for this profile was not found: `n$base`n`nContinue anyway?",
            'Back up profile', 'YesNo', 'Warning') -ne 'Yes') { return }
    }
    $scope = [System.Windows.Forms.MessageBox]::Show(
        "Choose what to back up from this profile:`n`n[Yes]   User data + App settings`n       Desktop, Documents, Downloads, Pictures,`n       Music, Videos + AppData\Roaming`n`n[No]    User data only (fast)`n       Desktop, Documents, Downloads, Pictures, Music, Videos`n`n[Cancel]  Don't back up",
        'Back up profile', 'YesNoCancel', 'Question')
    if ($scope -eq 'Cancel') { return }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Choose where to back up (recommend this USB drive)"
    if ($dlg.ShowDialog() -ne 'OK') { return }
    $dest = Join-Path $dlg.SelectedPath $env:COMPUTERNAME
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }

    $folders = @('Desktop','Documents','Downloads','Pictures','Music','Videos')
    if ($scope -eq 'Yes') { $folders += 'AppData\Roaming' }

    $tmp = Join-Path $env:TEMP ("profile-backup-" + $env:COMPUTERNAME + ".cmd")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('@echo off')
    $lines.Add('echo ============================================')
    $lines.Add('echo   Backing up user data')
    $lines.Add('echo ============================================')
    $lines.Add('echo.')
    $lines.Add("echo   Destination: $dest")
    $lines.Add('echo.')
    foreach ($fo in $folders) {
        $srcF = Join-Path $base $fo
        $dstF = Join-Path $dest $fo
        if (-not (Test-Path $srcF)) { $lines.Add("echo   (skip: $fo not found on this PC)"); $lines.Add('echo.'); continue }
        $lines.Add("robocopy `"$srcF`" `"$dstF`" /E /COPY:DAT /R:1 /W:1 /XJ /NFL /NDL")
        $lines.Add("if %errorlevel% GEQ 8 (echo   Note: some files could not be copied for $fo) else (echo   OK: $fo)")
        $lines.Add('echo.')
    }
    $lines.Add('echo  Done. NTUSER.DAT errors (if any) are normal when you are')
    $lines.Add('echo  logged into this profile - your documents are still backed up.')
    $lines.Add('echo  Press any key to close...')
    $lines.Add('pause')
    [System.IO.File]::WriteAllText($tmp, ($lines -join "`r`n"), [System.Text.Encoding]::ASCII)
    try {
        Start-Process $tmp -Verb RunAs
    } catch {
        Show-Msg "Could not start the backup (admin may be required).`n$($_.Exception.Message)"
    }
}

function Restore-Profile {
    $r = Get-SelectedRow
    if (-not $r) { Show-Msg 'Please select the NEW profile to restore into first.'; return }
    $target = $r.Folder
    if (-not $target -or -not (Test-Path $target)) {
        Show-Msg "The selected profile folder was not found: `n$target`n`n(Select the newly created profile in the list.)"
        return
    }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Choose the BACKUP folder (where you saved it, e.g. this USB drive)"
    if ($dlg.ShowDialog() -ne 'OK') { return }
    $srcRoot = $dlg.SelectedPath
    $names = @('Desktop','Documents','Downloads','Pictures','Music','Videos','AppData\Roaming')
    $found = @()
    foreach ($n in $names) { if (Test-Path (Join-Path $srcRoot $n)) { $found += $n } }
    if ($found.Count -eq 0) {
        Show-Msg "No backed-up folders were found in: `n$srcRoot`n`nMake sure you picked the folder that contains Desktop / Documents / etc."
        return
    }
    $list = $found -join ', '
    $yes = [System.Windows.Forms.MessageBox]::Show(
        "Restore into this profile:  $($r.Account)`n  folder: $target`n`nCopying back from backup:`n  $srcRoot`n  folders: $list`n`nImportant:`n- Use this ONLY on a freshly created new profile.`n- NTUSER.DAT is NOT restored (that keeps the new profile healthy).`n- Files with the same name in the new profile will be overwritten by the backup.`n`nContinue?",
        'Restore profile', 'YesNo', 'Warning')
    if ($yes -ne 'Yes') { return }
    $tmp = Join-Path $env:TEMP ("profile-restore-" + $env:COMPUTERNAME + ".cmd")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('@echo off')
    $lines.Add('echo ============================================')
    $lines.Add('echo   Restoring user data')
    $lines.Add('echo ============================================')
    $lines.Add('echo.')
    $lines.Add("echo   From backup: $srcRoot")
    $lines.Add("echo   Into profile: $target")
    $lines.Add('echo.')
    foreach ($n in $found) {
        $srcF = Join-Path $srcRoot $n
        $dstF = Join-Path $target $n
        $lines.Add("robocopy `"$srcF`" `"$dstF`" /E /COPY:DAT /R:1 /W:1 /XJ /NFL /NDL")
        $lines.Add("if %errorlevel% GEQ 8 (echo   Note: some files could not be restored for $n) else (echo   OK: restored $n)")
        $lines.Add('echo.')
    }
    $lines.Add('echo  Done. Sign into the new profile to see your files.')
    $lines.Add('echo  Press any key to close...')
    $lines.Add('pause')
    [System.IO.File]::WriteAllText($tmp, ($lines -join "`r`n"), [System.Text.Encoding]::ASCII)
    try {
        Start-Process $tmp -Verb RunAs
    } catch {
        Show-Msg "Could not start the restore (admin may be required).`n$($_.Exception.Message)"
    }
}

function Fix-State {
    $r = Get-SelectedRow
    if (-not $r) { Show-Msg 'Please select a profile in the list first.'; return }
    if ($r.State -ne 1) {
        [System.Windows.Forms.MessageBox]::Show(
            "This profile is not a 'temporary profile' (State = $($r.State)).`nThis fix is only for State 1.", 
            'Fix temporary profile', 'OK', 'Information') | Out-Null
        return
    }
    $yes = [System.Windows.Forms.MessageBox]::Show(
        "Fix profile: $($r.Account)  (SID $($r.SID))`n`nThis sets its registry State from 1 (temporary) back to 0 (normal).`n`nImportant:`n- You must NOT be signed into this profile right now.`n- A restart is needed afterward.`n`nContinue?", 
        'Fix temporary profile', 'YesNo', 'Warning')
    if ($yes -ne 'Yes') { return }
    $regPath = "$script:ProfileKey\$($r.SID)"
    $tmp = Join-Path $env:TEMP ("profile-fix-" + $env:COMPUTERNAME + ".ps1")
    $body = @(
        "Set-ItemProperty -Path '$regPath' -Name State -Value 0",
        "Write-Host ''",
        "Write-Host 'State set to 0 (normal). Restart the PC and sign in again.'",
        "Write-Host 'Press any key to close...'",
        '[void][System.Console]::ReadKey($true)'
    )
    [System.IO.File]::WriteAllText($tmp, ($body -join "`r`n"), [System.Text.Encoding]::ASCII)
    try {
        Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tmp)
    } catch {
        Show-Msg "Could not run the fix (admin is required).`n$($_.Exception.Message)"
    }
}

# --- build the form ---------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Profile Repair Utility'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(980, 680)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'Windows User Profile Repair'
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(12, 10); $lblTitle.AutoSize = $true
$form.Controls.Add($lblTitle) | Out-Null

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = 'Lists every profile and its health. Select one, then Back up (safe) before any fix. Read the guide first.'
$lblHint.ForeColor = [System.Drawing.Color]::FromArgb(80,80,80)
$lblHint.Location = New-Object System.Drawing.Point(12, 44); $lblHint.AutoSize = $true
$form.Controls.Add($lblHint) | Out-Null

# --- Recommended workflow panel -------------------------------------------------
$grpWork = New-Object System.Windows.Forms.GroupBox
$grpWork.Text = 'Recommended safe workflow  -  follow these steps in order'
$grpWork.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$grpWork.ForeColor = [System.Drawing.Color]::FromArgb(40,90,140)
$grpWork.Location = New-Object System.Drawing.Point(12, 62)
$grpWork.Size = New-Object System.Drawing.Size(956, 156)

function Add-Step($desc, $y, $btnText, $handler) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $desc
    $lbl.Location = New-Object System.Drawing.Point(10, $y)
    $lbl.Size = New-Object System.Drawing.Size(680, 22)
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $grpWork.Controls.Add($lbl) | Out-Null
    if ($btnText) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $btnText
        $by = [int]$y - 2
        $b.Location = New-Object System.Drawing.Point(800, $by)
        $b.Size = New-Object System.Drawing.Size(130, 24)
        $b.Font = New-Object System.Drawing.Font('Segoe UI', 8)
        $b.Add_Click($handler)
        $grpWork.Controls.Add($b) | Out-Null
    }
}
Add-Step 'Step 1 -  Back up your old profile to this USB (safe first)' 30 'Back up' { Backup-Profile }
Add-Step 'Step 2 -  Create a NEW user profile (add a local user)' 58 'Open settings' { Start-Process 'ms-settings:otherusers' }
Add-Step 'Step 3 -  Restore your files into the NEW profile' 86 'Restore' { Restore-Profile }
Add-Step 'Step 4 -  Sign in to the NEW profile and check your files' 114 $null $null
Add-Step 'Step 5 -  Remove the old profile (only after step 4 works)' 142 'How to' {
    Show-Msg "Removing the old profile:`n`nOnly do this AFTER the new profile works and has your files.`n`n1. Sign in as the NEW profile.`n2. Control Panel > System > Advanced system settings >`n   Advanced tab > User Profiles > Settings.`n3. Select the OLD profile and click Delete.`n`nThis deletes the old profile folder. Keep your USB backup`nas a safety net until you are 100% sure."
}
$form.Controls.Add($grpWork) | Out-Null

$lst = New-Object System.Windows.Forms.ListView
$lst.Location = New-Object System.Drawing.Point(12, 226)
$lst.Size = New-Object System.Drawing.Size(956, 300)
$lst.View = 'Details'
$lst.FullRowSelect = $true
$lst.GridLines = $true
$lst.MultiSelect = $false
$lst.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$col = @(
    @('Status', 110), @('Account', 160), @('SID', 210),
    @('State', 55), @('Folder Exists', 90), @('Profile Folder', 320)
)
foreach ($c in $col) {
    $lst.Columns.Add($c[0], $c[1]) | Out-Null
}
$form.Controls.Add($lst) | Out-Null

$btnHealth = New-Object System.Windows.Forms.Button
$btnHealth.Text = 'Check profile health'
$btnHealth.Location = New-Object System.Drawing.Point(12, 534); $btnHealth.Size = New-Object System.Drawing.Size(150, 36)
$btnHealth.Add_Click({ Show-Msg 'Green = OK. Orange = temporary (fix it). Red = inactive / missing folder (back it up, then rebuild a new profile).' })
$form.Controls.Add($btnHealth) | Out-Null

$btnBackup = New-Object System.Windows.Forms.Button
$btnBackup.Text = 'Back up selected profile'
$btnBackup.Location = New-Object System.Drawing.Point(172, 534); $btnBackup.Size = New-Object System.Drawing.Size(170, 36)
$btnBackup.BackColor = [System.Drawing.Color]::FromArgb(223,240,216)
$btnBackup.Add_Click({ Backup-Profile })
$form.Controls.Add($btnBackup) | Out-Null

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = 'Restore into selected profile'
$btnRestore.Location = New-Object System.Drawing.Point(352, 534); $btnRestore.Size = New-Object System.Drawing.Size(180, 36)
$btnRestore.BackColor = [System.Drawing.Color]::FromArgb(207,232,252)
$btnRestore.Add_Click({ Restore-Profile })
$form.Controls.Add($btnRestore) | Out-Null

$btnFix = New-Object System.Windows.Forms.Button
$btnFix.Text = 'Fix temporary profile'
$btnFix.Location = New-Object System.Drawing.Point(12, 578); $btnFix.Size = New-Object System.Drawing.Size(160, 36)
$btnFix.BackColor = [System.Drawing.Color]::FromArgb(255,235,205)
$btnFix.Add_Click({ Fix-State })
$form.Controls.Add($btnFix) | Out-Null

$btnGuide = New-Object System.Windows.Forms.Button
$btnGuide.Text = 'Open step-by-step guide'
$btnGuide.Location = New-Object System.Drawing.Point(182, 578); $btnGuide.Size = New-Object System.Drawing.Size(170, 36)
$btnGuide.Add_Click({ if (Test-Path $script:GuideFile) { Start-Process notepad $script:GuideFile } else { Show-Msg 'Guide file not found next to this utility.' } })
$form.Controls.Add($btnGuide) | Out-Null

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Refresh list'
$btnRefresh.Location = New-Object System.Drawing.Point(362, 578); $btnRefresh.Size = New-Object System.Drawing.Size(120, 36)
$btnRefresh.Add_Click({ Load-List })
$form.Controls.Add($btnRefresh) | Out-Null

$lblFoot = New-Object System.Windows.Forms.Label
$lblFoot.Text = 'Nothing is changed unless you click a fix, and every repair asks you first. Back up before you fix.'
$lblFoot.ForeColor = [System.Drawing.Color]::FromArgb(120,120,120)
$lblFoot.Location = New-Object System.Drawing.Point(12, 626); $lblFoot.AutoSize = $true
$form.Controls.Add($lblFoot) | Out-Null

$script:lblStatus = New-Object System.Windows.Forms.Label
$script:lblStatus.Location = New-Object System.Drawing.Point(12, 650); $script:lblStatus.AutoSize = $true
$script:lblStatus.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$script:lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(60,120,60)
$form.Controls.Add($script:lblStatus) | Out-Null

Load-List
[void]$form.ShowDialog()
