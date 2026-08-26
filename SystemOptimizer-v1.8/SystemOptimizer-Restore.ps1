<#
.SYNOPSIS
  One-click restore of your user settings from the USB backup.
  Restores browser bookmarks, Wi-Fi profiles, and user settings.
  Launched by 1-Click-System-Restore.cmd (run as Administrator).
#>
Add-Type -AssemblyName System.Windows.Forms
$ScriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptRoot 'lib\Common.ps1')
. (Join-Path $ScriptRoot 'lib\BackupRestore.ps1')

$script:LogFile = Join-Path $env:ProgramData 'SystemOptimizer\restore.log'
$script:UiSink = @{
    MessageBox = {
        param($Text, $Title, $Buttons, $Icon)
        [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, $Buttons, $Icon)
        if ($Buttons -eq 'YesNo') { return 'Yes' }
    }
}

Write-Log '===== 1-CLICK RESTORE STARTED ====='
$src = Get-ChosenBackupFolder
if (-not $src) {
    [void][System.Windows.Forms.MessageBox]::Show(
        "No backup folder was found.`n`nPlug in the USB drive that holds your backup and try again.",
        'Restore', 'OK', 'Warning')
    exit 1
}
if (-not (Test-Path $src)) {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Backup folder not found:`n$src", 'Restore', 'OK', 'Warning')
    exit 1
}

Restore-UserSettings
Write-Log '===== 1-CLICK RESTORE FINISHED ====='
