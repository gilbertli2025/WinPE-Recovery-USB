<#
.SYNOPSIS
  System Optimizer - the unified GUI. Thin shim over lib/*.ps1.
  Tab 1 Performance + Services, Tab 2 Security, Tab 3 Maintenance, Tab 4 Repair.

.DESCRIPTION
  This script is intentionally a UI shell. All real logic lives in lib/
  (Common.ps1, ServiceCatalog.ps1, SecurityItems.ps1, MaintenanceItems.ps1,
  Repair.ps1, Review.ps1). Read those for behaviour details.
#>
[CmdletBinding()]
param(
    [switch]$SmokeTest,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ScriptRoot = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
. (Join-Path $ScriptRoot 'lib\Common.ps1')
. (Join-Path $ScriptRoot 'lib\ServiceCatalog.ps1')
. (Join-Path $ScriptRoot 'lib\SecurityItems.ps1')
. (Join-Path $ScriptRoot 'lib\MaintenanceItems.ps1')
. (Join-Path $ScriptRoot 'lib\Repair.ps1')
. (Join-Path $ScriptRoot 'lib\Review.ps1')
. (Join-Path $ScriptRoot 'lib\BackupRestore.ps1')
. (Join-Path $ScriptRoot 'lib\FolderBackup.ps1')
. (Join-Path $ScriptRoot 'lib\Utilities.ps1')
. (Join-Path $ScriptRoot 'lib\StartupManager.ps1')

$script:LogFile = $script:Paths.UnifiedLog

# Per-run log on the USB drive (kept to the last 7 runs). Helps troubleshooting.
$script:RunLog = $null
try {
    $rootDrive = $ScriptRoot.Substring(0, 2)
    if ([System.IO.DriveInfo]::new($rootDrive).DriveType -eq 'Removable') {
        $logDir = Join-Path $ScriptRoot 'logs'
        try { if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null } } catch {}
        # Rotate BEFORE creating this run's log: keep the newest 6 old ones
        # (so with this run we keep 7 in total). Never deletes this run's log.
        try {
            $old = @(Get-ChildItem $logDir -Filter 'run-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
            if ($old.Count -gt 6) { $old | Select-Object -Skip 6 | Remove-Item -Force -ErrorAction SilentlyContinue }
        } catch {}
        $runLog = Join-Path $logDir ("run-$env:COMPUTERNAME-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")
        $script:RunLog = $runLog
        Write-Log "Per-run log: $runLog"
    }
} catch { $script:RunLog = $null }
$script:LogSink = $null

if (-not (Test-Admin) -and -not $NoElevate) {
    [void][System.Windows.Forms.MessageBox]::Show(
        'System Optimizer needs administrator rights.' + [Environment]::NewLine + [Environment]::NewLine + 'Click OK to restart with elevation.',
        'Admin required', 'OK', 'Information')
    Restart-Admin
}

# If launched directly (not via the .cmd launcher), make sure this tool's own
# signing certificate is trusted, so the signed exe runs even with Smart App
# Control on. (Safe: it is this tool's own cert; fails silently if not admin.)
$soCert = Join-Path $ScriptRoot 'WSO-Trust.cer'
if (Test-Path -LiteralPath $soCert) {
    try { & certutil.exe -addstore -f Root $soCert 2>&1 | Out-Null } catch { }
}

# --------------------------------------------------------------------------
# Form
# --------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'System Optimizer - Performance + Security'
$form.ClientSize = New-Object System.Drawing.Size(900, 700)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

# --------------------------------------------------------------------------
# V1.6 Mode toggle (Easy / Advanced) + Easy panel + backup-reminder banner
# --------------------------------------------------------------------------
# --- V1.6: 3 top-level tabs: Easy | Advanced | Utilities ---
$script:mainTabs = New-Object System.Windows.Forms.TabControl
$script:mainTabs.Location = New-Object System.Drawing.Point(10, 10)
$script:mainTabs.Size = New-Object System.Drawing.Size(880, 580)
$form.Controls.Add($script:mainTabs) | Out-Null

$pageEasy = New-Object System.Windows.Forms.TabPage
$pageEasy.Text = 'Easy'
$pageEasy.Padding = New-Object System.Windows.Forms.Padding(8)
$script:mainTabs.TabPages.Add($pageEasy) | Out-Null

$pageAdv = New-Object System.Windows.Forms.TabPage
$pageAdv.Text = 'Advanced'
$pageAdv.Padding = New-Object System.Windows.Forms.Padding(6)
$script:mainTabs.TabPages.Add($pageAdv) | Out-Null

# --- Version / What's New tab ---
$script:AppVersion = '1.8.0'
$script:AppBuildDate = '2026-08-25'
$script:Changelog = @(
    @{ V='v1.8.0'; D='2026-08-25'; N=@(
        'Profile Repair: a full utility to list every user profile and its health',
        'Guided safe workflow: Back up -> Create a new profile -> Restore -> Verify -> Remove old',
        'Back up user data (or data + app settings) to your USB with robocopy',
        'Restore backed-up files into a newly created profile (never NTUSER.DAT)',
        'Fix a temporary profile (State 1 -> 0) with one click',
        'Openable from Utilities tab; ships with its own step-by-step guide' ) },
    @{ V='v1.7.0'; D='2026-08-21'; N=@(
        'PERFORMANCE',
        '- PC Health Score (0-100) shown on the home screen: see at a glance how healthy your PC is',
        '- Performance Boost: apply safe, reversible speed tweaks - and restore everything to defaults anytime',
        '- System Report: full hardware + software + health report, saved to your USB and opened in Notepad',
        '- Drive Health: check disk temperature / wear / SMART status to catch a failing drive early',
        'SECURITY',
        '- Security & Hardening (10 items), all reversible - everything can be undone',
        '- USB safety: shows USB status, refuses One-Click Optimize without a USB, and checks free space first',
        '- Network Repair: flush DNS + reset Winsock to fix common connection problems',
        'MAINTENANCE & CLEANUP',
        '- App updates guide: keep all your software current with winget',
        '- Working indicator + progress bar during every scan and One-Click Optimize',
        'TOOLS & DIAGNOSTICS',
        '- Startup Manager: see what runs at boot and safely enable/disable it',
        '- Broken Shortcuts finder: find and remove dead shortcuts (Recycle-Bin safe)',
        '- System Health Check: read-only summary with tips',
        '- Hardware info: CPU, RAM, storage and operating system details',
        '- Network test: check latency and connectivity',
        '- Battery report: detailed battery health report for laptops',
        '- Commands reference: a handy list of useful commands for advanced users',
        'BACKUP (timestamped history)',
        '- Back up personal folders to your USB with timestamped, per-PC backup history (keeps the last 7)',
        '- Restore files/settings, pick which folders to restore, restore specific files, or restore another PC backup',
        '- Per-run log saved on the USB (keeps the last 7 runs)' ) },
    @{ V='v1.6.0'; D='2026-08-21'; N=@(
        'Foundation: 3 tabs (Easy, Advanced, Utilities)',
        'Folder backup to USB, utilities (duplicate finder, disk analyzer, large files, programs list)' ) }
)
$pageVer = New-Object System.Windows.Forms.TabPage
$pageVer.Text = 'Version'
$pageVer.Padding = New-Object System.Windows.Forms.Padding(8)
$script:mainTabs.TabPages.Add($pageVer) | Out-Null

$lblVerTitle = New-Object System.Windows.Forms.Label
$lblVerTitle.Text = "System Optimizer   v$($script:AppVersion)   (built $($script:AppBuildDate))"
$lblVerTitle.AutoSize = $true; $lblVerTitle.Location = New-Object System.Drawing.Point(8, 8)
$lblVerTitle.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$pageVer.Controls.Add($lblVerTitle) | Out-Null

$lblVerWhat = New-Object System.Windows.Forms.Label
$lblVerWhat.Text = "What's new in this version:"
$lblVerWhat.AutoSize = $true; $lblVerWhat.Location = New-Object System.Drawing.Point(8, 50)
$lblVerWhat.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$pageVer.Controls.Add($lblVerWhat) | Out-Null

$txtChangelog = New-Object System.Windows.Forms.TextBox
$txtChangelog.Multiline = $true; $txtChangelog.ReadOnly = $true; $txtChangelog.ScrollBars = 'Vertical'
$txtChangelog.BackColor = [System.Drawing.Color]::White
$txtChangelog.Location = New-Object System.Drawing.Point(8, 76); $txtChangelog.Size = New-Object System.Drawing.Size(860, 470)
$txtChangelog.Font = New-Object System.Drawing.Font('Consolas', 9)
$clLines = New-Object System.Collections.Generic.List[string]
foreach ($v in $script:Changelog) {
    $clLines.Add('')
    $clLines.Add("=== $($v.V)  ($($v.D)) ===")
    foreach ($n in $v.N) { $clLines.Add("  - $n") }
}
$txtChangelog.Text = ($clLines -join [Environment]::NewLine)
$pageVer.Controls.Add($txtChangelog) | Out-Null

$lblVerSafe = New-Object System.Windows.Forms.Label
$lblVerSafe.Text = "IMPORTANT: Always run this program from the USB drive, and keep the USB drive safe.`nIt holds your settings backup and your recovery key - do not use this USB for anything else."
$lblVerSafe.Location = New-Object System.Drawing.Point(8, 446); $lblVerSafe.Size = New-Object System.Drawing.Size(860, 60)
$lblVerSafe.ForeColor = [System.Drawing.Color]::FromArgb(180, 60, 0)
$lblVerSafe.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$pageVer.Controls.Add($lblVerSafe) | Out-Null

$lblVerCredit = New-Object System.Windows.Forms.Label
$lblVerCredit.Text = 'Developed with DeepSeek V4'
$lblVerCredit.Location = New-Object System.Drawing.Point(8, 516); $lblVerCredit.AutoSize = $true
$lblVerCredit.ForeColor = [System.Drawing.Color]::FromArgb(110, 110, 110)
$lblVerCredit.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$pageVer.Controls.Add($lblVerCredit) | Out-Null

# Native, proportionate tabs (Windows-themed) - they auto-size to the text
$script:mainTabs.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
foreach ($tp in $script:mainTabs.TabPages) { $tp.BackColor = [System.Drawing.Color]::White }

$lblVersion = New-Object System.Windows.Forms.Label
$lblVersion.Text = "v$($script:AppVersion)"; $lblVersion.AutoSize = $true; $lblVersion.Location = New-Object System.Drawing.Point(830, 12)
$lblVersion.ForeColor = [System.Drawing.Color]::FromArgb(0, 102, 204)
$lblVersion.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($lblVersion) | Out-Null

# Backup-reminder banner (shown in Advanced mode)
$script:lblBackupNote = New-Object System.Windows.Forms.Label
$script:lblBackupNote.Text = 'TIP: Back up your settings & files first (recommended before making changes).'
$script:lblBackupNote.Location = New-Object System.Drawing.Point(6, 8); $script:lblBackupNote.Size = New-Object System.Drawing.Size(700, 20)
$script:lblBackupNote.ForeColor = [System.Drawing.Color]::FromArgb(150, 110, 0)
$pageAdv.Controls.Add($script:lblBackupNote) | Out-Null
$script:btnBannerBackup = New-Object System.Windows.Forms.Button
$script:btnBannerBackup.Text = 'Back up now'; $script:btnBannerBackup.Size = New-Object System.Drawing.Size(120, 26); $script:btnBannerBackup.Location = New-Object System.Drawing.Point(742, 4)
$pageAdv.Controls.Add($script:btnBannerBackup) | Out-Null

# Easy-mode panel (inside the Easy top-level tab)
$script:easyPanel = New-Object System.Windows.Forms.Panel
$script:easyPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$pageEasy.Controls.Add($script:easyPanel) | Out-Null

$lblEasyTitle = New-Object System.Windows.Forms.Label
$lblEasyTitle.Text = 'EASY MODE - we will take care of it'
$lblEasyTitle.AutoSize = $true; $lblEasyTitle.Location = New-Object System.Drawing.Point(0, 0)
$lblEasyTitle.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$script:easyPanel.Controls.Add($lblEasyTitle) | Out-Null

# Health card
$gbHealth = New-Object System.Windows.Forms.GroupBox
$gbHealth.Text = 'Your PC health'; $gbHealth.Location = New-Object System.Drawing.Point(0, 36); $gbHealth.Size = New-Object System.Drawing.Size(430, 150)
$script:easyPanel.Controls.Add($gbHealth) | Out-Null
$lblHealthCaption = New-Object System.Windows.Forms.Label
$lblHealthCaption.Text = 'PC Health:'; $lblHealthCaption.AutoSize = $true; $lblHealthCaption.Location = New-Object System.Drawing.Point(16, 20); $lblHealthCaption.ForeColor = [System.Drawing.Color]::FromArgb(90,90,90)
$gbHealth.Controls.Add($lblHealthCaption) | Out-Null
$script:lblHealthScore = New-Object System.Windows.Forms.Label
$script:lblHealthScore.Text = '...'; $script:lblHealthScore.AutoSize = $true; $script:lblHealthScore.Location = New-Object System.Drawing.Point(92, 16); $script:lblHealthScore.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$gbHealth.Controls.Add($script:lblHealthScore) | Out-Null
$script:lblHealthFree = New-Object System.Windows.Forms.Label
$script:lblHealthFree.Text = 'C: free space: ...'; $script:lblHealthFree.AutoSize = $true; $script:lblHealthFree.Location = New-Object System.Drawing.Point(16, 50)
$gbHealth.Controls.Add($script:lblHealthFree) | Out-Null
$script:lblHealthBackup = New-Object System.Windows.Forms.Label
$script:lblHealthBackup.Text = 'Last backup: none yet'; $script:lblHealthBackup.AutoSize = $true; $script:lblHealthBackup.Location = New-Object System.Drawing.Point(16, 74)
$gbHealth.Controls.Add($script:lblHealthBackup) | Out-Null
$script:lblHealthDefender = New-Object System.Windows.Forms.Label
$script:lblHealthDefender.Text = 'Windows Defender: ...'; $script:lblHealthDefender.AutoSize = $true; $script:lblHealthDefender.Location = New-Object System.Drawing.Point(16, 98)
$gbHealth.Controls.Add($script:lblHealthDefender) | Out-Null
$script:lblHealthUsb = New-Object System.Windows.Forms.Label
$script:lblHealthUsb.Text = 'USB drive: ...'; $script:lblHealthUsb.AutoSize = $true; $script:lblHealthUsb.Location = New-Object System.Drawing.Point(16, 122)
$gbHealth.Controls.Add($script:lblHealthUsb) | Out-Null
$btnRefreshHealth = New-Object System.Windows.Forms.Button
$btnRefreshHealth.Text = 'Refresh'; $btnRefreshHealth.Size = New-Object System.Drawing.Size(80, 26); $btnRefreshHealth.Location = New-Object System.Drawing.Point(330, 122)
$gbHealth.Controls.Add($btnRefreshHealth) | Out-Null

# Big One-Click Optimize button (moved to the right)
$script:btnEasyOptimize = New-Object System.Windows.Forms.Button
$script:btnEasyOptimize.Text = "ONE-CLICK`nOPTIMIZE"
$script:btnEasyOptimize.Size = New-Object System.Drawing.Size(250, 150); $script:btnEasyOptimize.Location = New-Object System.Drawing.Point(620, 36)
$script:btnEasyOptimize.BackColor = [System.Drawing.Color]::FromArgb(0, 102, 204)
$script:btnEasyOptimize.ForeColor = [System.Drawing.Color]::White
$script:btnEasyOptimize.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$script:easyPanel.Controls.Add($script:btnEasyOptimize) | Out-Null

# Progress + stage indicator for One-Click Optimize
$script:lblEasyStage = New-Object System.Windows.Forms.Label
$script:lblEasyStage.Text = 'Ready'
$script:lblEasyStage.AutoSize = $true; $script:lblEasyStage.Location = New-Object System.Drawing.Point(0, 196)
$script:lblEasyStage.ForeColor = [System.Drawing.Color]::FromArgb(0, 102, 204); $script:lblEasyStage.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$script:easyPanel.Controls.Add($script:lblEasyStage) | Out-Null
$script:prgEasy = New-Object System.Windows.Forms.ProgressBar
$script:prgEasy.Location = New-Object System.Drawing.Point(0, 216); $script:prgEasy.Size = New-Object System.Drawing.Size(880, 18)
$script:prgEasy.Minimum = 0; $script:prgEasy.Maximum = 100; $script:prgEasy.Style = 'Continuous'
$script:easyPanel.Controls.Add($script:prgEasy) | Out-Null

# What One-Click will apply (interactive - user can untick anything)
$gbEasyItems = New-Object System.Windows.Forms.GroupBox
$gbEasyItems.Text = 'What One-Click Optimize will apply  (untick anything you do NOT want)'
$gbEasyItems.Location = New-Object System.Drawing.Point(0, 240); $gbEasyItems.Size = New-Object System.Drawing.Size(880, 160)
$script:easyPanel.Controls.Add($gbEasyItems) | Out-Null
$lblEasyPick = New-Object System.Windows.Forms.Label
$lblEasyPick.Text = 'Recommended items are already ticked - untick any you do not want:'
$lblEasyPick.AutoSize = $true; $lblEasyPick.Location = New-Object System.Drawing.Point(8, 16)
$lblEasyPick.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$gbEasyItems.Controls.Add($lblEasyPick) | Out-Null
$script:clbEasy = New-Object System.Windows.Forms.CheckedListBox
$script:clbEasy.Location = New-Object System.Drawing.Point(8, 38); $script:clbEasy.Size = New-Object System.Drawing.Size(864, 112)
$script:clbEasy.CheckOnClick = $true; $script:clbEasy.BackColor = [System.Drawing.Color]::White
$script:clbEasy.add_ItemCheck({ param($s, $e)
    if ($script:easyItemsList -and $e.Index -lt $script:easyItemsList.Count -and $script:easyItemsList[$e.Index].Category -eq 'header') { $e.NewValue = 'Unchecked' }
})
$gbEasyItems.Controls.Add($script:clbEasy) | Out-Null
$lblEasySafe = New-Object System.Windows.Forms.Label
$lblEasySafe.Text = "It will NOT enable BitLocker, disable Office macros, or set account lockout - those are Advanced mode only."
$lblEasySafe.AutoSize = $false; $lblEasySafe.Size = New-Object System.Drawing.Size(880, 18)
$lblEasySafe.Location = New-Object System.Drawing.Point(0, 406)
$lblEasySafe.ForeColor = [System.Drawing.Color]::FromArgb(150, 110, 0)
$script:easyPanel.Controls.Add($lblEasySafe) | Out-Null

# Restore button
$script:btnEasyRestore = New-Object System.Windows.Forms.Button
$script:btnEasyRestore.Text = 'Restore my files & settings'
$script:btnEasyRestore.Size = New-Object System.Drawing.Size(240, 40); $script:btnEasyRestore.Location = New-Object System.Drawing.Point(0, 428)
$script:easyPanel.Controls.Add($script:btnEasyRestore) | Out-Null

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(6, 32)
$tabs.Size = New-Object System.Drawing.Size(868, 460)
$pageAdv.Controls.Add($tabs) | Out-Null

# --------------------------------------------------------------------------
# Tab 1 - Performance & Services
# --------------------------------------------------------------------------
$script:svcChecks = [System.Collections.ArrayList]::new()

$tabPerf = New-Object System.Windows.Forms.TabPage
$tabPerf.Text = 'Performance & Services'
$tabPerf.Padding = New-Object System.Windows.Forms.Padding(6)
$tabPerf.AutoScroll = $true

$gbSafe = New-Object System.Windows.Forms.GroupBox
$gbSafe.Text = 'SAFE services (recommended)'
$gbSafe.Location = New-Object System.Drawing.Point(6, 6)
$gbSafe.Size = New-Object System.Drawing.Size(420, 320)
$flowSafe = New-Object System.Windows.Forms.FlowLayoutPanel
$flowSafe.Location = New-Object System.Drawing.Point(10, 22)
$flowSafe.Size = New-Object System.Drawing.Size(400, 290)
$flowSafe.AutoScroll = $true; $flowSafe.WrapContents = $false; $flowSafe.FlowDirection = 'TopDown'
$gbSafe.Controls.Add($flowSafe) | Out-Null

$gbOpt = New-Object System.Windows.Forms.GroupBox
$gbOpt.Text = 'OPTIONAL services (may affect features)'
$gbOpt.Location = New-Object System.Drawing.Point(434, 6)
$gbOpt.Size = New-Object System.Drawing.Size(420, 320)
$flowOpt = New-Object System.Windows.Forms.FlowLayoutPanel
$flowOpt.Location = New-Object System.Drawing.Point(10, 22)
$flowOpt.Size = New-Object System.Drawing.Size(400, 290)
$flowOpt.AutoScroll = $true; $flowOpt.WrapContents = $false; $flowOpt.FlowDirection = 'TopDown'
$gbOpt.Controls.Add($flowOpt) | Out-Null

foreach ($n in $script:ServiceGroups.Safe) {
    $svc  = Get-Service -Name $n -ErrorAction SilentlyContinue
    $disp = if ($svc) { $svc.DisplayName } else { $null }
    $label = if ($disp) { "$n  ($disp)" } else { $n }
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $label; $cb.Font = New-Object System.Drawing.Font('Consolas', 9)
    $cb.AutoSize = $true; $cb.Checked = $true; $cb.Tag = $n
    [void]$script:svcChecks.Add($cb); $flowSafe.Controls.Add($cb)
}
foreach ($n in $script:ServiceGroups.Optional) {
    $svc  = Get-Service -Name $n -ErrorAction SilentlyContinue
    $disp = if ($svc) { $svc.DisplayName } else { $null }
    $label = if ($disp) { "$n  ($disp)" } else { $n }
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $label; $cb.Font = New-Object System.Drawing.Font('Consolas', 9)
    $cb.AutoSize = $true; $cb.Checked = $false; $cb.Tag = $n
    [void]$script:svcChecks.Add($cb); $flowOpt.Controls.Add($cb)
}

$tabPerf.Controls.Add($gbSafe) | Out-Null
$tabPerf.Controls.Add($gbOpt) | Out-Null

$btnDisable = New-Object System.Windows.Forms.Button; $btnDisable.Text = 'Disable services (selected)'; $btnDisable.Size = New-Object System.Drawing.Size(175,30); $btnDisable.Location = New-Object System.Drawing.Point(6, 336)
$btnRestoreSvc = New-Object System.Windows.Forms.Button; $btnRestoreSvc.Text = 'Restore services'; $btnRestoreSvc.Size = New-Object System.Drawing.Size(130,30); $btnRestoreSvc.Location = New-Object System.Drawing.Point(186, 336)
$btnVerifySvc = New-Object System.Windows.Forms.Button; $btnVerifySvc.Text = 'Verify services'; $btnVerifySvc.Size = New-Object System.Drawing.Size(130,30); $btnVerifySvc.Location = New-Object System.Drawing.Point(322, 336)
$btnRestoreOpt = New-Object System.Windows.Forms.Button; $btnRestoreOpt.Text = 'Restore optional only'; $btnRestoreOpt.Size = New-Object System.Drawing.Size(170,30); $btnRestoreOpt.Location = New-Object System.Drawing.Point(458, 336)
$tabPerf.Controls.Add($btnDisable) | Out-Null
$tabPerf.Controls.Add($btnRestoreSvc) | Out-Null
$tabPerf.Controls.Add($btnVerifySvc) | Out-Null
$tabPerf.Controls.Add($btnRestoreOpt) | Out-Null

$lblOptHint = New-Object System.Windows.Forms.Label
$lblOptHint.Text = "TIP: OPTIONAL services can disable printing, Remote Desktop, Bluetooth, search or scanners. If a feature stops working, use 'Restore optional only'."
$lblOptHint.Location = New-Object System.Drawing.Point(8, 374)
$lblOptHint.Size = New-Object System.Drawing.Size(860, 40)
$lblOptHint.ForeColor = [System.Drawing.Color]::FromArgb(150,110,0)
$tabPerf.Controls.Add($lblOptHint) | Out-Null

$tabs.TabPages.Add($tabPerf) | Out-Null

# --------------------------------------------------------------------------
# Tab 2 - Security
# --------------------------------------------------------------------------
$script:secChecks = [System.Collections.ArrayList]::new()

$tabSec = New-Object System.Windows.Forms.TabPage
$tabSec.Text = 'Security & Hardening'
$tabSec.Padding = New-Object System.Windows.Forms.Padding(6)
$tabSec.AutoScroll = $true

$gbSec = New-Object System.Windows.Forms.GroupBox
$gbSec.Text = 'Hardening items (tick to apply)'
$gbSec.Location = New-Object System.Drawing.Point(6, 6)
$gbSec.Size = New-Object System.Drawing.Size(852, 320)
$flowSec = New-Object System.Windows.Forms.FlowLayoutPanel
$flowSec.Location = New-Object System.Drawing.Point(10, 22)
$flowSec.Size = New-Object System.Drawing.Size(830, 290)
$flowSec.AutoScroll = $true; $flowSec.WrapContents = $false; $flowSec.FlowDirection = 'TopDown'

$n = 0
foreach ($it in $script:SecurityItems) {
    $n++
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = "$n.  $($it.text)"; $cb.AutoSize = $true; $cb.Checked = $true; $cb.Tag = $it.id
    [void]$script:secChecks.Add($cb); $flowSec.Controls.Add($cb)
}
$gbSec.Controls.Add($flowSec) | Out-Null
$tabSec.Controls.Add($gbSec) | Out-Null

$btnApplySec = New-Object System.Windows.Forms.Button; $btnApplySec.Text = 'Apply security (selected)'; $btnApplySec.Size = New-Object System.Drawing.Size(150,30); $btnApplySec.Location = New-Object System.Drawing.Point(6, 336)
$btnRestoreSec = New-Object System.Windows.Forms.Button; $btnRestoreSec.Text = 'Restore security'; $btnRestoreSec.Size = New-Object System.Drawing.Size(130,30); $btnRestoreSec.Location = New-Object System.Drawing.Point(164, 336)
$btnReviewSec = New-Object System.Windows.Forms.Button; $btnReviewSec.Text = 'Security review'; $btnReviewSec.Size = New-Object System.Drawing.Size(130,30); $btnReviewSec.Location = New-Object System.Drawing.Point(302, 336)
$btnRestoreCheckedSec = New-Object System.Windows.Forms.Button; $btnRestoreCheckedSec.Text = 'Restore checked'; $btnRestoreCheckedSec.Size = New-Object System.Drawing.Size(150,30); $btnRestoreCheckedSec.Location = New-Object System.Drawing.Point(440, 336)
$btnExplainSec = New-Object System.Windows.Forms.Button; $btnExplainSec.Text = 'Explain this'; $btnExplainSec.Size = New-Object System.Drawing.Size(120,30); $btnExplainSec.Location = New-Object System.Drawing.Point(598, 336)
$tabSec.Controls.Add($btnApplySec) | Out-Null
$tabSec.Controls.Add($btnRestoreSec) | Out-Null
$tabSec.Controls.Add($btnReviewSec) | Out-Null
$tabSec.Controls.Add($btnRestoreCheckedSec) | Out-Null
$tabSec.Controls.Add($btnExplainSec) | Out-Null

$tabs.TabPages.Add($tabSec) | Out-Null

# --------------------------------------------------------------------------
# Tab 3 - Maintenance
# --------------------------------------------------------------------------
$script:maintChecks = [System.Collections.ArrayList]::new()

$tabMaint = New-Object System.Windows.Forms.TabPage
$tabMaint.Text = 'Maintenance & Cleanup'
$tabMaint.Padding = New-Object System.Windows.Forms.Padding(6)
$tabMaint.AutoScroll = $true

$gbMaint = New-Object System.Windows.Forms.GroupBox
$gbMaint.Text = 'Cleanup & maintenance items (tick to run)'
$gbMaint.Location = New-Object System.Drawing.Point(6, 6)
$gbMaint.Size = New-Object System.Drawing.Size(852, 320)
$flowMaint = New-Object System.Windows.Forms.FlowLayoutPanel
$flowMaint.Location = New-Object System.Drawing.Point(10, 22)
$flowMaint.Size = New-Object System.Drawing.Size(830, 290)
$flowMaint.AutoScroll = $true; $flowMaint.WrapContents = $false; $flowMaint.FlowDirection = 'TopDown'
$preChecked = 'cleantemp','wucleanup','trimssd','flushdns','gamedvr','faststartup','tips'
$n = 0
foreach ($it in $script:MaintenanceItems) {
    $n++
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = "$n.  $($it.text)"; $cb.AutoSize = $true
    $cb.Checked = ($preChecked -contains $it.id); $cb.Tag = $it.id
    [void]$script:maintChecks.Add($cb); $flowMaint.Controls.Add($cb)
}
$gbMaint.Controls.Add($flowMaint) | Out-Null
$tabMaint.Controls.Add($gbMaint) | Out-Null

$btnMaintRun = New-Object System.Windows.Forms.Button; $btnMaintRun.Text = 'Run selected cleanup'; $btnMaintRun.Size = New-Object System.Drawing.Size(150,30); $btnMaintRun.Location = New-Object System.Drawing.Point(6, 336)
$btnMaintRestore = New-Object System.Windows.Forms.Button; $btnMaintRestore.Text = 'Restore settings'; $btnMaintRestore.Size = New-Object System.Drawing.Size(140,30); $btnMaintRestore.Location = New-Object System.Drawing.Point(164, 336)
$btnMaintReport = New-Object System.Windows.Forms.Button; $btnMaintReport.Text = 'Cleanup report'; $btnMaintReport.Size = New-Object System.Drawing.Size(130,30); $btnMaintReport.Location = New-Object System.Drawing.Point(312, 336)
$btnExplainMaint = New-Object System.Windows.Forms.Button; $btnExplainMaint.Text = 'Explain this'; $btnExplainMaint.Size = New-Object System.Drawing.Size(120,30); $btnExplainMaint.Location = New-Object System.Drawing.Point(450, 336)
$btnScheduleMaint = New-Object System.Windows.Forms.Button; $btnScheduleMaint.Text = 'Schedule auto-maintenance'; $btnScheduleMaint.Size = New-Object System.Drawing.Size(180,30); $btnScheduleMaint.Location = New-Object System.Drawing.Point(578, 336)
$tabMaint.Controls.Add($btnMaintRun) | Out-Null
$tabMaint.Controls.Add($btnMaintRestore) | Out-Null
$tabMaint.Controls.Add($btnMaintReport) | Out-Null
$tabMaint.Controls.Add($btnExplainMaint) | Out-Null
$tabMaint.Controls.Add($btnScheduleMaint) | Out-Null

$lblMaintHint = New-Object System.Windows.Forms.Label
$lblMaintHint.Text = "TIP: items 1-5 and 11-12 are safe and pre-ticked. Items 6-10 and 13 are optional/off (may delete recoverable files, change visuals/power, or auto-clean restore points). Reversible settings can be undone with 'Restore settings'."
$lblMaintHint.Location = New-Object System.Drawing.Point(8, 374)
$lblMaintHint.Size = New-Object System.Drawing.Size(860, 40)
$lblMaintHint.ForeColor = [System.Drawing.Color]::FromArgb(150,110,0)
$tabMaint.Controls.Add($lblMaintHint) | Out-Null

$tabs.TabPages.Add($tabMaint) | Out-Null

# --------------------------------------------------------------------------
# Tab 4 - System Repair
# --------------------------------------------------------------------------
$script:repairChecks = [System.Collections.ArrayList]::new()
$repairItems = @(
    @{ id='sfc';    text='Verify and repair system files (sfc /scannow)' },
    @{ id='dism';   text='Repair the Windows image (DISM /restorehealth)' },
    @{ id='chkdsk'; text='Check disk for errors (chkdsk C: /f) - REQUIRES RESTART' }
)

$tabRepair = New-Object System.Windows.Forms.TabPage
$tabRepair.Text = 'System Repair'
$tabRepair.Padding = New-Object System.Windows.Forms.Padding(6)
$tabRepair.AutoScroll = $true

$gbRepair = New-Object System.Windows.Forms.GroupBox
$gbRepair.Text = 'Repair tools (tick to run)'
$gbRepair.Location = New-Object System.Drawing.Point(6, 6)
$gbRepair.Size = New-Object System.Drawing.Size(852, 200)
$flowRepair = New-Object System.Windows.Forms.FlowLayoutPanel
$flowRepair.Location = New-Object System.Drawing.Point(10, 22)
$flowRepair.Size = New-Object System.Drawing.Size(830, 170)
$flowRepair.AutoScroll = $true; $flowRepair.WrapContents = $false; $flowRepair.FlowDirection = 'TopDown'

foreach ($it in $repairItems) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $it.text; $cb.AutoSize = $true
    $cb.Checked = ($it.id -ne 'chkdsk'); $cb.Tag = $it.id
    [void]$script:repairChecks.Add($cb); $flowRepair.Controls.Add($cb)
}
$gbRepair.Controls.Add($flowRepair) | Out-Null
$tabRepair.Controls.Add($gbRepair) | Out-Null

$btnRepairRun = New-Object System.Windows.Forms.Button; $btnRepairRun.Text = 'Run selected repairs'; $btnRepairRun.Size = New-Object System.Drawing.Size(160,30); $btnRepairRun.Location = New-Object System.Drawing.Point(6, 214)
$tabRepair.Controls.Add($btnRepairRun) | Out-Null

$lblRepairHint = New-Object System.Windows.Forms.Label
$lblRepairHint.Text = "NOTE: repairs can take a long time (sfc 5-10 min, DISM 10-20+ min). chkdsk needs a restart. Repairs are NOT part of 'Apply ALL' - run them here when needed."
$lblRepairHint.Location = New-Object System.Drawing.Point(8, 252)
$lblRepairHint.Size = New-Object System.Drawing.Size(860, 40)
$lblRepairHint.ForeColor = [System.Drawing.Color]::FromArgb(150,110,0)
$tabRepair.Controls.Add($lblRepairHint) | Out-Null
$tabs.TabPages.Add($tabRepair) | Out-Null

# --------------------------------------------------------------------------
# Tab 5 - Backup & Restore
# --------------------------------------------------------------------------
$tabBk = New-Object System.Windows.Forms.TabPage
$tabBk.Text = 'Backup & Restore'
$tabBk.Padding = New-Object System.Windows.Forms.Padding(6)
$tabBk.AutoScroll = $true

$gbBk = New-Object System.Windows.Forms.GroupBox
$gbBk.Text = 'Back up / restore your user settings (to a USB drive)'
$gbBk.Location = New-Object System.Drawing.Point(6, 6)
$gbBk.Size = New-Object System.Drawing.Size(852, 160)
$lblBk = New-Object System.Windows.Forms.Label
$lblBk.Text = "Backs up safe, portable items: browser bookmarks, Wi-Fi profiles, user registry settings, and this tool's profile.`nPasswords are NOT backed up (security) - use a password manager for those."
$lblBk.Location = New-Object System.Drawing.Point(12, 24)
$lblBk.Size = New-Object System.Drawing.Size(820, 60)
$lblBk.ForeColor = [System.Drawing.Color]::FromArgb(60,60,60)
$gbBk.Controls.Add($lblBk) | Out-Null

$btnBackup = New-Object System.Windows.Forms.Button; $btnBackup.Text = 'Backup settings to USB'; $btnBackup.Size = New-Object System.Drawing.Size(180,30); $btnBackup.Location = New-Object System.Drawing.Point(12, 100)
$btnRestoreBk = New-Object System.Windows.Forms.Button; $btnRestoreBk.Text = 'Restore from USB'; $btnRestoreBk.Size = New-Object System.Drawing.Size(150,30); $btnRestoreBk.Location = New-Object System.Drawing.Point(200, 100)
$btnPreflight = New-Object System.Windows.Forms.Button; $btnPreflight.Text = 'Pre-flight check'; $btnPreflight.Size = New-Object System.Drawing.Size(130,30); $btnPreflight.Location = New-Object System.Drawing.Point(358, 100)
$btnVerifyBk = New-Object System.Windows.Forms.Button; $btnVerifyBk.Text = 'Verify backup'; $btnVerifyBk.Size = New-Object System.Drawing.Size(120,30); $btnVerifyBk.Location = New-Object System.Drawing.Point(496, 100)
$gbBk.Controls.Add($btnBackup) | Out-Null
$gbBk.Controls.Add($btnRestoreBk) | Out-Null
$gbBk.Controls.Add($btnPreflight) | Out-Null
$gbBk.Controls.Add($btnVerifyBk) | Out-Null

$lblBkNote = New-Object System.Windows.Forms.Label
$lblBkNote.Text = "TIP: plug in a USB drive, then Backup settings to USB. Keep the USB safe. On a new/problem PC, Restore from USB brings back bookmarks, Wi-Fi and settings.`nEach button shows a small pop-up to confirm - click OK on it, then you can switch to any tab."
$lblBkNote.Location = New-Object System.Drawing.Point(8, 178)
$lblBkNote.Size = New-Object System.Drawing.Size(860, 30)
$lblBkNote.ForeColor = [System.Drawing.Color]::FromArgb(150,110,0)
$tabBk.Controls.Add($gbBk) | Out-Null
$tabBk.Controls.Add($lblBkNote) | Out-Null

$tabs.TabPages.Add($tabBk) | Out-Null

# --------------------------------------------------------------------------
# Tab 6 (Advanced) - Commands reference for advanced users
# --------------------------------------------------------------------------
$tabCmd = New-Object System.Windows.Forms.TabPage
$tabCmd.Text = 'Commands'
$tabCmd.Padding = New-Object System.Windows.Forms.Padding(8)
$cmdRef = @"
WINDOWS COMMAND REFERENCE  (for advanced users)
Use these in Windows Terminal / PowerShell. Many need admin (open Terminal as Administrator).

=== APP & PACKAGE (winget) ===
  winget update --all        Update ALL installed apps at once (great - keep software current).
  winget list                List installed apps.
  winget search <name>       Search for an app to install.
  winget install <name>      Install an app (e.g. winget install 7zip.7zip).
  winget upgrade <name>      Update one app.
  winget uninstall <name>    Uninstall an app.
  winget --version           Check winget version.

=== DISK & REPAIR ===
  sfc /scannow               Scan & repair protected Windows system files (safe, 5-10 min).
  DISM /Online /Cleanup-Image /RestoreHealth   Repair the Windows image (10-20 min).
  chkdsk C: /o              Quick disk repair (offline, usually no restart - try this first).
  chkdsk C: /f              Thorough disk repair (locks drive; may ask to check at restart).
  chkdsk C: /r              Deep scan - finds bad sectors + recovers readable data (implies /f).
  cleanmgr                  Disk Cleanup tool (safe).
  defrag C: /O              Optimize drives (defrag HDD / trim SSD).

=== NETWORK ===
  ipconfig /flushdns        Clear the DNS cache (fixes some connection issues).
  ipconfig /release         Release the current IP.
  ipconfig /renew           Get a new IP from the router.
  ping google.com           Test if you can reach a site (4 pings).
  tracert google.com        Show the route / where a connection is slow.
  nslookup google.com       Look up a website's IP address.
  netsh winsock reset       Reset network/Winsock (needs a restart).
  Get-NetAdapter            List your network adapters (PowerShell).

=== SYSTEM & POWER ===
  systeminfo                Show detailed system info.
  powercfg /batteryreport   Generate a battery health report (laptops).
  shutdown /r /t 0          Restart now.
  shutdown /s /t 0          Shut down now.
  powercfg /a               Show available sleep states.

=== PROCESSES & STARTUP ===
  tasklist                  List running processes.
  taskkill /F /IM <name>    Force-close a program (e.g. taskkill /F /IM notepad.exe).
  Get-Process               List processes (PowerShell).
  Get-Service               List services (PowerShell).

=== FILES ===
  robocopy <src> <dst> /E   Copy a folder including subfolders (incremental).
  del /s /q <path>          Delete files (careful - permanent).
"@
$lblCmdTitle = New-Object System.Windows.Forms.Label
$lblCmdTitle.Text = 'Commands reference - for advanced users (open Terminal, paste a command, press Enter):'
$lblCmdTitle.AutoSize = $true; $lblCmdTitle.Location = New-Object System.Drawing.Point(8, 8)
$lblCmdTitle.ForeColor = [System.Drawing.Color]::FromArgb(60,60,60)
$tabCmd.Controls.Add($lblCmdTitle) | Out-Null
$txtCmd = New-Object System.Windows.Forms.TextBox
$txtCmd.Multiline = $true; $txtCmd.ReadOnly = $true; $txtCmd.ScrollBars = 'Both'
$txtCmd.BackColor = [System.Drawing.Color]::White; $txtCmd.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtCmd.Location = New-Object System.Drawing.Point(8, 30); $txtCmd.Size = New-Object System.Drawing.Size(846, 400)
$txtCmd.Text = $cmdRef
$tabCmd.Controls.Add($txtCmd) | Out-Null
$tabs.TabPages.Add($tabCmd) | Out-Null

# --------------------------------------------------------------------------
# Tab 6 - Utilities (hard-drive health & space tools, safe)
# --------------------------------------------------------------------------
$tabUtil = New-Object System.Windows.Forms.TabPage
$tabUtil.Text = 'Utilities'
$tabUtil.Padding = New-Object System.Windows.Forms.Padding(6)
$tabUtil.AutoScroll = $true

$gbUtil = New-Object System.Windows.Forms.GroupBox
$gbUtil.Text = 'Hard-drive health & space tools (all safe - deletes go to the Recycle Bin)'
$gbUtil.Location = New-Object System.Drawing.Point(6, 6); $gbUtil.Size = New-Object System.Drawing.Size(850, 152)

$btnUtilDup   = New-Object System.Windows.Forms.Button; $btnUtilDup.Text   = 'Duplicate finder';   $btnUtilDup.Size   = New-Object System.Drawing.Size(130,32); $btnUtilDup.Location   = New-Object System.Drawing.Point(12, 24)
$btnUtilDisk  = New-Object System.Windows.Forms.Button; $btnUtilDisk.Text  = 'Disk analyzer';      $btnUtilDisk.Size  = New-Object System.Drawing.Size(120,32); $btnUtilDisk.Location  = New-Object System.Drawing.Point(150, 24)
$btnUtilLarge = New-Object System.Windows.Forms.Button; $btnUtilLarge.Text = 'Large-file finder';  $btnUtilLarge.Size = New-Object System.Drawing.Size(130,32); $btnUtilLarge.Location = New-Object System.Drawing.Point(278, 24)
$btnUtilProg  = New-Object System.Windows.Forms.Button; $btnUtilProg.Text  = 'Export programs list'; $btnUtilProg.Size = New-Object System.Drawing.Size(195,32); $btnUtilProg.Location = New-Object System.Drawing.Point(416, 24)
$btnUtilStartup = New-Object System.Windows.Forms.Button; $btnUtilStartup.Text = 'Startup Manager'; $btnUtilStartup.Size = New-Object System.Drawing.Size(140, 26); $btnUtilStartup.Location = New-Object System.Drawing.Point(12, 92)
$btnUtilShort = New-Object System.Windows.Forms.Button; $btnUtilShort.Text = 'Broken shortcuts'; $btnUtilShort.Size = New-Object System.Drawing.Size(140, 26); $btnUtilShort.Location = New-Object System.Drawing.Point(160, 92)
$btnUtilDrive = New-Object System.Windows.Forms.Button; $btnUtilDrive.Text = 'Drive health'; $btnUtilDrive.Size = New-Object System.Drawing.Size(110, 26); $btnUtilDrive.Location = New-Object System.Drawing.Point(308, 92)
$btnUtilNet   = New-Object System.Windows.Forms.Button; $btnUtilNet.Text   = 'Network repair'; $btnUtilNet.Size   = New-Object System.Drawing.Size(130, 26); $btnUtilNet.Location   = New-Object System.Drawing.Point(426, 92)
$btnUtilHealth= New-Object System.Windows.Forms.Button; $btnUtilHealth.Text= 'Health check';   $btnUtilHealth.Size  = New-Object System.Drawing.Size(110, 26); $btnUtilHealth.Location  = New-Object System.Drawing.Point(564, 92)

# Row 3 - diagnostics & system tools
$btnUtilHardware = New-Object System.Windows.Forms.Button; $btnUtilHardware.Text = 'Hardware info';  $btnUtilHardware.Size = New-Object System.Drawing.Size(130, 26); $btnUtilHardware.Location = New-Object System.Drawing.Point(12, 120)
$btnUtilNetwork  = New-Object System.Windows.Forms.Button; $btnUtilNetwork.Text  = 'Network test';   $btnUtilNetwork.Size  = New-Object System.Drawing.Size(130, 26); $btnUtilNetwork.Location  = New-Object System.Drawing.Point(150, 120)
$btnUtilBattery  = New-Object System.Windows.Forms.Button; $btnUtilBattery.Text  = 'Battery report'; $btnUtilBattery.Size  = New-Object System.Drawing.Size(130, 26); $btnUtilBattery.Location  = New-Object System.Drawing.Point(288, 120)
$btnUtilApps     = New-Object System.Windows.Forms.Button; $btnUtilApps.Text     = 'App updates';    $btnUtilApps.Size     = New-Object System.Drawing.Size(130, 26); $btnUtilApps.Location     = New-Object System.Drawing.Point(426, 120)
$gbUtil.Controls.Add($btnUtilHardware) | Out-Null; $gbUtil.Controls.Add($btnUtilNetwork) | Out-Null; $gbUtil.Controls.Add($btnUtilBattery) | Out-Null; $gbUtil.Controls.Add($btnUtilApps) | Out-Null

# v1.8: Profile Repair utility button
$btnUtilProfile = New-Object System.Windows.Forms.Button; $btnUtilProfile.Text = 'Profile Repair'; $btnUtilProfile.Size = New-Object System.Drawing.Size(140,26); $btnUtilProfile.Location = New-Object System.Drawing.Point(564,120)
$btnUtilProfile.BackColor = [System.Drawing.Color]::FromArgb(223,240,216)
$btnUtilProfile.Add_Click({
    $pr = Join-Path $ScriptRoot 'profile-repair\ProfileRepair-Utility.ps1'
    if (-not (Test-Path -LiteralPath $pr)) {
        [void][System.Windows.Forms.MessageBox]::Show("Profile Repair utility was not found:`n$pr", 'Profile Repair', 'OK', 'Warning')
        return
    }
    try {
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$pr`""
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show("Could not open Profile Repair.`n$($_.Exception.Message)", 'Profile Repair', 'OK', 'Warning')
    }
})
$gbUtil.Controls.Add($btnUtilProfile) | Out-Null

$lblUtilPath = New-Object System.Windows.Forms.Label; $lblUtilPath.Text = 'Folder/drive to scan:'; $lblUtilPath.AutoSize = $true; $lblUtilPath.Location = New-Object System.Drawing.Point(12, 66)
$script:txtUtilPath = New-Object System.Windows.Forms.TextBox; $script:txtUtilPath.Text = $env:USERPROFILE; $script:txtUtilPath.Size = New-Object System.Drawing.Size(400,22); $script:txtUtilPath.Location = New-Object System.Drawing.Point(140, 64)
$btnUtilBrowse = New-Object System.Windows.Forms.Button; $btnUtilBrowse.Text = 'Browse...'; $btnUtilBrowse.Size = New-Object System.Drawing.Size(80,26); $btnUtilBrowse.Location = New-Object System.Drawing.Point(548, 62)

$gbUtil.Controls.Add($btnUtilDup) | Out-Null; $gbUtil.Controls.Add($btnUtilDisk) | Out-Null; $gbUtil.Controls.Add($btnUtilLarge) | Out-Null; $gbUtil.Controls.Add($btnUtilProg) | Out-Null
$gbUtil.Controls.Add($lblUtilPath) | Out-Null; $gbUtil.Controls.Add($script:txtUtilPath) | Out-Null; $gbUtil.Controls.Add($btnUtilBrowse) | Out-Null
$gbUtil.Controls.Add($btnUtilStartup) | Out-Null
$gbUtil.Controls.Add($btnUtilShort) | Out-Null
$gbUtil.Controls.Add($btnUtilDrive) | Out-Null
$gbUtil.Controls.Add($btnUtilNet) | Out-Null
$gbUtil.Controls.Add($btnUtilHealth) | Out-Null

$script:dgUtil = New-Object System.Windows.Forms.DataGridView
$script:dgUtil.Location = New-Object System.Drawing.Point(6, 162); $script:dgUtil.Size = New-Object System.Drawing.Size(850, 190)
$script:dgUtil.AllowUserToAddRows = $false; $script:dgUtil.ReadOnly = $true; $script:dgUtil.SelectionMode = 'FullRowSelect'; $script:dgUtil.AutoSizeColumnsMode = 'Fill'; $script:dgUtil.BackgroundColor = [System.Drawing.Color]::White

$btnUtilKeepNewest = New-Object System.Windows.Forms.Button; $btnUtilKeepNewest.Text = 'Keep newest (auto-select older copies)'; $btnUtilKeepNewest.Size = New-Object System.Drawing.Size(222,32); $btnUtilKeepNewest.Location = New-Object System.Drawing.Point(6, 358)
$btnUtilDelete = New-Object System.Windows.Forms.Button; $btnUtilDelete.Text = 'Send selected to Recycle Bin'; $btnUtilDelete.Size = New-Object System.Drawing.Size(228,32); $btnUtilDelete.Location = New-Object System.Drawing.Point(234, 358)
$btnUtilDelete.BackColor = [System.Drawing.Color]::FromArgb(0, 102, 204); $btnUtilDelete.ForeColor = [System.Drawing.Color]::White
$btnUtilOpen = New-Object System.Windows.Forms.Button; $btnUtilOpen.Text = 'Open file folder'; $btnUtilOpen.Size = New-Object System.Drawing.Size(150,30); $btnUtilOpen.Location = New-Object System.Drawing.Point(6, 396)
$btnPerfBoost = New-Object System.Windows.Forms.Button; $btnPerfBoost.Text = 'Performance boost'; $btnPerfBoost.Size = New-Object System.Drawing.Size(150,30); $btnPerfBoost.Location = New-Object System.Drawing.Point(164, 396)
$btnPerfRestore = New-Object System.Windows.Forms.Button; $btnPerfRestore.Text = 'Restore performance'; $btnPerfRestore.Size = New-Object System.Drawing.Size(150,30); $btnPerfRestore.Location = New-Object System.Drawing.Point(322, 396)
$btnSysReport = New-Object System.Windows.Forms.Button; $btnSysReport.Text = 'System report'; $btnSysReport.Size = New-Object System.Drawing.Size(150,30); $btnSysReport.Location = New-Object System.Drawing.Point(480, 396)
$lblUtilHint = New-Object System.Windows.Forms.Label
$lblUtilHint.Text = "Duplicates: click 'Keep newest' then 'Send selected to Recycle Bin' (safe - Recycle Bin only). Tip: double-click a file (or 'Open file folder') to jump to its folder. Scan your own data (e.g. Documents / Pictures)."
$lblUtilHint.Location = New-Object System.Drawing.Point(6, 428); $lblUtilHint.Size = New-Object System.Drawing.Size(850, 42); $lblUtilHint.ForeColor = [System.Drawing.Color]::FromArgb(150,110,0)
# Working indicator (shown while a scan/task runs)
$script:lblWork = New-Object System.Windows.Forms.Label
$script:lblWork.Text = 'Ready'
$script:lblWork.AutoSize = $true; $script:lblWork.Location = New-Object System.Drawing.Point(6, 472)
$script:lblWork.ForeColor = [System.Drawing.Color]::FromArgb(0, 102, 204); $script:lblWork.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$script:prgWork = New-Object System.Windows.Forms.ProgressBar
$script:prgWork.Location = New-Object System.Drawing.Point(6, 494); $script:prgWork.Size = New-Object System.Drawing.Size(850, 16)
$script:prgWork.Style = 'Marquee'; $script:prgWork.MarqueeAnimationSpeed = 25; $script:prgWork.Visible = $false
$tabUtil.Controls.Add($gbUtil) | Out-Null; $tabUtil.Controls.Add($script:dgUtil) | Out-Null; $tabUtil.Controls.Add($btnUtilKeepNewest) | Out-Null; $tabUtil.Controls.Add($btnUtilDelete) | Out-Null; $tabUtil.Controls.Add($btnUtilOpen) | Out-Null; $tabUtil.Controls.Add($lblUtilHint) | Out-Null; $tabUtil.Controls.Add($script:lblWork) | Out-Null; $tabUtil.Controls.Add($script:prgWork) | Out-Null; $tabUtil.Controls.Add($btnPerfBoost) | Out-Null; $tabUtil.Controls.Add($btnPerfRestore) | Out-Null; $tabUtil.Controls.Add($btnSysReport) | Out-Null
$script:dupMeta = @()
$script:mainTabs.TabPages.Add($tabUtil) | Out-Null
$script:utilMode = ''

# --------------------------------------------------------------------------
# Health Check tab (v1.8) - read-only health score + breakdown, so the user
# can check health before applying any mode and again afterwards to compare.
# --------------------------------------------------------------------------
$tabHealth = New-Object System.Windows.Forms.TabPage
$tabHealth.Text = 'Health'
$tabHealth.Padding = New-Object System.Windows.Forms.Padding(8)

$lblHealthTitle = New-Object System.Windows.Forms.Label
$lblHealthTitle.Text = 'PC Health Check'
$lblHealthTitle.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lblHealthTitle.Location = New-Object System.Drawing.Point(12, 10); $lblHealthTitle.AutoSize = $true
$tabHealth.Controls.Add($lblHealthTitle) | Out-Null

$script:lblHealthScoreBig = New-Object System.Windows.Forms.Label
$script:lblHealthScoreBig.Text = '...'; $script:lblHealthScoreBig.AutoSize = $true
$script:lblHealthScoreBig.Location = New-Object System.Drawing.Point(12, 44)
$script:lblHealthScoreBig.Font = New-Object System.Drawing.Font('Segoe UI', 26, [System.Drawing.FontStyle]::Bold)
$tabHealth.Controls.Add($script:lblHealthScoreBig) | Out-Null

$script:lblHealthChecked = New-Object System.Windows.Forms.Label
$script:lblHealthChecked.Text = 'Checked: -'
$script:lblHealthChecked.AutoSize = $true
$script:lblHealthChecked.Location = New-Object System.Drawing.Point(160, 58)
$script:lblHealthChecked.ForeColor = [System.Drawing.Color]::FromArgb(110,110,110)
$tabHealth.Controls.Add($script:lblHealthChecked) | Out-Null

$script:lvHealth = New-Object System.Windows.Forms.ListView
$script:lvHealth.Location = New-Object System.Drawing.Point(12, 100)
$script:lvHealth.Size = New-Object System.Drawing.Size(850, 360)
$script:lvHealth.View = 'Details'; $script:lvHealth.FullRowSelect = $true; $script:lvHealth.GridLines = $true
$script:lvHealth.Columns.Add('Item', 200) | Out-Null
$script:lvHealth.Columns.Add('Status', 90) | Out-Null
$script:lvHealth.Columns.Add('Detail', 520) | Out-Null
$tabHealth.Controls.Add($script:lvHealth) | Out-Null

$btnHealthCheck = New-Object System.Windows.Forms.Button
$btnHealthCheck.Text = 'Check health now'
$btnHealthCheck.Size = New-Object System.Drawing.Size(160, 36)
$btnHealthCheck.Location = New-Object System.Drawing.Point(12, 470)
$btnHealthCheck.BackColor = [System.Drawing.Color]::FromArgb(223,240,216)
$btnHealthCheck.Add_Click({ Update-HealthCheckTab })
$tabHealth.Controls.Add($btnHealthCheck) | Out-Null

$lblHealthHint = New-Object System.Windows.Forms.Label
$lblHealthHint.Text = "Run 'Check health now' BEFORE you apply any mode, then run it AGAIN afterwards to compare." + [Environment]::NewLine + "Green = OK, orange = warning, red = needs attention. This check is read-only - it changes nothing."
$lblHealthHint.Location = New-Object System.Drawing.Point(12, 516); $lblHealthHint.Size = New-Object System.Drawing.Size(850, 40)
$lblHealthHint.ForeColor = [System.Drawing.Color]::FromArgb(80,80,80)
$tabHealth.Controls.Add($lblHealthHint) | Out-Null

function Update-HealthCheckTab {
    $h = Get-HealthCheck
    $script:lblHealthScoreBig.Text = "$($h.Score)/100"
    if ($h.Score -ge 80) { $script:lblHealthScoreBig.ForeColor = [System.Drawing.Color]::FromArgb(0,140,0) }
    elseif ($h.Score -ge 50) { $script:lblHealthScoreBig.ForeColor = [System.Drawing.Color]::FromArgb(200,150,0) }
    else { $script:lblHealthScoreBig.ForeColor = [System.Drawing.Color]::FromArgb(190,30,30) }
    $script:lblHealthChecked.Text = 'Checked: ' + $h.Checked
    $script:lvHealth.Items.Clear()
    foreach ($r in $h.Rows) {
        $item = New-Object System.Windows.Forms.ListViewItem($r.Name)
        [void]$item.SubItems.Add($r.Status)
        [void]$item.SubItems.Add($r.Detail)
        if ($r.Status -eq 'OK') { $item.ForeColor = [System.Drawing.Color]::Green }
        elseif ($r.Status -eq 'Warn') { $item.ForeColor = [System.Drawing.Color]::FromArgb(200,150,0) }
        elseif ($r.Status -eq 'Fail') { $item.ForeColor = [System.Drawing.Color]::Red }
        $script:lvHealth.Items.Add($item) | Out-Null
    }
}

# Add the Health tab and place it second (after Easy). Note: TabPages.Insert()
# silently fails in PowerShell, so we rebuild the tab order with Add().
$script:mainTabs.TabPages.Add($tabHealth) | Out-Null
$tpOrder = @($pageEasy, $tabHealth, $pageAdv, $pageVer, $tabUtil)
foreach ($tp in $tpOrder) { if ($script:mainTabs.TabPages.Contains($tp)) { $script:mainTabs.TabPages.Remove($tp) | Out-Null } }
foreach ($tp in $tpOrder) { $script:mainTabs.TabPages.Add($tp) | Out-Null }

# Blue tab strip + light page background so the tabs are easy to read.
foreach ($tp in $tabs.TabPages) { $tp.BackColor = [System.Drawing.Color]::White }
$tabs.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)

# --------------------------------------------------------------------------
# Bottom master controls
# --------------------------------------------------------------------------
$btnApplyAll = New-Object System.Windows.Forms.Button; $btnApplyAll.Text = 'Apply ALL selected'; $btnApplyAll.Size = New-Object System.Drawing.Size(150,34); $btnApplyAll.Location = New-Object System.Drawing.Point(10, 500)
$btnRestoreAll = New-Object System.Windows.Forms.Button; $btnRestoreAll.Text = 'Restore ALL'; $btnRestoreAll.Size = New-Object System.Drawing.Size(120,34); $btnRestoreAll.Location = New-Object System.Drawing.Point(168, 500)
$btnReviewAll = New-Object System.Windows.Forms.Button; $btnReviewAll.Text = 'Full review'; $btnReviewAll.Size = New-Object System.Drawing.Size(120,34); $btnReviewAll.Location = New-Object System.Drawing.Point(296, 500)
$btnHelp = New-Object System.Windows.Forms.Button; $btnHelp.Text = 'Help'; $btnHelp.Size = New-Object System.Drawing.Size(80,34); $btnHelp.Location = New-Object System.Drawing.Point(424, 500)
$btnExport = New-Object System.Windows.Forms.Button; $btnExport.Text = 'Export'; $btnExport.Size = New-Object System.Drawing.Size(80,34); $btnExport.Location = New-Object System.Drawing.Point(512, 500)
$btnImport = New-Object System.Windows.Forms.Button; $btnImport.Text = 'Import'; $btnImport.Size = New-Object System.Drawing.Size(80,34); $btnImport.Location = New-Object System.Drawing.Point(600, 500)
$btnUndoLast = New-Object System.Windows.Forms.Button; $btnUndoLast.Text = 'Undo last'; $btnUndoLast.Size = New-Object System.Drawing.Size(90,34); $btnUndoLast.Location = New-Object System.Drawing.Point(690, 500)
$pageAdv.Controls.Add($btnApplyAll) | Out-Null
$pageAdv.Controls.Add($btnRestoreAll) | Out-Null
$pageAdv.Controls.Add($btnReviewAll) | Out-Null
$pageAdv.Controls.Add($btnHelp) | Out-Null
$pageAdv.Controls.Add($btnExport) | Out-Null
$pageAdv.Controls.Add($btnImport) | Out-Null
$pageAdv.Controls.Add($btnUndoLast) | Out-Null

$lblLog = New-Object System.Windows.Forms.Label; $lblLog.Text = 'Log:'; $lblLog.Location = New-Object System.Drawing.Point(10, 596)
$form.Controls.Add($lblLog) | Out-Null

$script:logBox = New-Object System.Windows.Forms.TextBox
$script:logBox.Multiline = $true; $script:logBox.ReadOnly = $true; $script:logBox.ScrollBars = 'Vertical'
$script:logBox.BackColor = [System.Drawing.Color]::FromArgb(32,32,32); $script:logBox.ForeColor = [System.Drawing.Color]::White
$script:logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:logBox.Location = New-Object System.Drawing.Point(10, 616); $script:logBox.Size = New-Object System.Drawing.Size(880, 76)
$form.Controls.Add($script:logBox) | Out-Null

# Wire the sink AFTER the TextBox exists.
$script:LogSink = {
    param([string]$line)
    if ($script:logBox -and -not $script:logBox.IsDisposed) {
        try {
            if ($script:logBox.InvokeRequired) {
                $script:logBox.Invoke([System.Action]{ $script:logBox.AppendText($line + [Environment]::NewLine) }) | Out-Null
            } else {
                $script:logBox.AppendText($line + [Environment]::NewLine)
            }
        } catch { }
    }
}

# --------------------------------------------------------------------------
# v1.4 helpers: Explain this, Export/Import settings
# --------------------------------------------------------------------------
function Show-ItemExplanations {
    param($Items, $Checks)
    $checked = @($Checks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($checked.Count -eq 0) { Show-Message 'Tick the items you want to learn about.' 'Explain' Warn; return }
    $lines = @()
    foreach ($it in $Items) {
        if ($checked -contains $it.id) {
            $d = if ($it.desc) { $it.desc } else { '(no description)' }
            $lines += ($it.text + "`n    " + $d)
        }
    }
    Show-Message ($lines -join "`n`n") 'What these do' Info
}

function Export-Settings {
    $data = @{
        services = @($script:svcChecks  | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        security = @($script:secChecks   | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        maint    = @($script:maintChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        repair   = @($script:repairChecks| Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = 'JSON settings|*.json'
    $dlg.FileName = 'System-Optimizer-profile.json'
    if ($dlg.ShowDialog() -eq 'OK') {
        try { $data | ConvertTo-Json | Set-Content -LiteralPath $dlg.FileName -Encoding UTF8; Show-Message ("Settings saved to " + $dlg.FileName) 'Export' Info }
        catch { Show-Message ("Export failed: " + $_.Exception.Message) 'Error' }
    }
}

function Import-Settings {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'JSON settings|*.json'
    if ($dlg.ShowDialog() -eq 'OK') {
        try {
            $d = Get-Content -LiteralPath $dlg.FileName -Raw | ConvertFrom-Json
            foreach ($cb in $script:svcChecks)   { $cb.Checked = @($d.services) -contains $cb.Tag }
            foreach ($cb in $script:secChecks)   { $cb.Checked = @($d.security) -contains $cb.Tag }
            foreach ($cb in $script:maintChecks) { $cb.Checked = @($d.maint)    -contains $cb.Tag }
            foreach ($cb in $script:repairChecks){ $cb.Checked = @($d.repair)   -contains $cb.Tag }
            Show-Message 'Settings imported. Review the checkboxes before applying.' 'Import' Info
        } catch { Show-Message ("Import failed: " + $_.Exception.Message) 'Error' }
    }
}

function Save-LastRun {
    param([string[]]$services = @(), [string[]]$security = @(), [string[]]$maint = @())
    $data = @{ time = (Get-Date).ToString('o'); services = @($services); security = @($security); maint = @($maint) }
    New-Item -ItemType Directory -Path $script:Paths.SystemBackup -Force | Out-Null
    $data | ConvertTo-Json | Set-Content -LiteralPath $script:Paths.LastRunFile -Encoding UTF8
}

function Undo-LastRun {
    $p = $script:Paths.LastRunFile
    if (-not (Test-Path -LiteralPath $p)) { Show-Message 'No last run recorded to undo.' 'Undo last' Warn; return }
    try {
        $d = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
        Write-Log '=== Undo last run ==='
        $svc = @($d.services); $sec = @($d.security); $mt = @($d.maint)
        if ($svc.Count -gt 0) {
            $rows = @(Read-CsvRows -Path $script:Paths.ServicesBackupFile | Where-Object { $svc -contains $_.Name })
            Restore-ServicesRows -Rows $rows
        }
        if ($sec.Count -gt 0) { Restore-SecurityItems -Ids $sec }
        if ($mt.Count -gt 0)  { Restore-MaintenanceItems -Ids $mt }
        Write-Log '=== Undo last run finished ==='
        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        Show-Message 'Last run undone.' 'Undo last' Info
    } catch {
        Write-Log "ERROR undo last: $($_.Exception.Message)"
        Show-Message ("Undo failed: " + $_.Exception.Message) 'Error'
    }
}

# --------------------------------------------------------------------------
# Click handlers
# --------------------------------------------------------------------------
$btnDisable.add_Click({
    try {
        $names = @($script:svcChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        if ($names.Count -eq 0) { Show-Message 'Select at least one service.' 'Nothing selected' Warn; return }
        Write-Log '=== Services optimize started ==='
        Backup-ServicesSnapshot
        Disable-Services -Names $names
        Write-Log '=== Services optimize finished ==='
        Save-LastRun -services $names
        Show-Message "Done. $($names.Count) services processed. Reboot recommended." 'Finished' Info
    } catch {
        Write-Log "ERROR: $($_.Exception.Message)"
        Show-Message ("Could not complete: " + $_.Exception.Message) 'Error'
    }
})

$btnRestoreSvc.add_Click({
    Write-Log '=== Services restore ==='
    Restore-Services
    Write-Log '=== finished ==='
    Show-Message 'Services restore complete.' 'Finished' Info
})

$btnVerifySvc.add_Click({
    Write-Log '--- Verify services ---'
    Test-ServicesDisabled
})

$btnRestoreOpt.add_Click({
    Write-Log '--- Restore optional services ---'
    Restore-OptionalServices
    Show-Message 'Optional services restored (print, Remote Desktop, Bluetooth, etc.).' 'Finished' Info
})

$btnApplySec.add_Click({
    $ids = @($script:secChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { Show-Message 'Tick at least one hardening item.' 'Nothing selected' Warn; return }
    # Confirm before any irreversible setting (BitLocker encrypts the drive;
    # Script Host disable breaks .vbs/.js system-wide; lockout locks you out).
    $needsConfirm = $ids -contains 'bitlocker' -or $ids -contains 'officewsh' -or $ids -contains 'lockout'
    if ($needsConfirm) {
        $items = ($ids | Where-Object { $_ -in @('bitlocker','officewsh','lockout') }) -join ', '
        if (-not (Show-YesNo "These checked items can be hard to undo: $items.`n`nContinue?" 'Confirm' Warn)) { return }
    }
    Write-Log '=== Security hardening started ==='
    foreach ($id in $ids) { Apply-SecurityItem -Id $id }
    Write-Log '=== Security hardening finished ==='
    Save-LastRun -security $ids
    Show-Message 'Hardening applied. A reboot is recommended.' 'Finished' Info
})

$btnRestoreSec.add_Click({
    Write-Log '--- Restore security ---'
    Restore-Security
    Show-Message 'Security restore complete.' 'Finished' Info
})

$btnReviewSec.add_Click({ Write-Log '--- Security review ---'; Save-SecurityReview })

$btnRestoreCheckedSec.add_Click({
    $ids = @($script:secChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { Show-Message 'Tick the hardening items you want to restore.' 'Nothing selected' Warn; return }
    Write-Log '--- Restore checked (security) ---'
    Restore-SecurityItems -Ids $ids
    Show-Message 'Checked items restored to their previous settings.' 'Finished' Info
})

$btnApplyAll.add_Click({
    try {
        # Pre-flight check: admin, disk space, restore point, USB-for-BitLocker
        $secIds = @($script:secChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        if (-not (Test-PreFlight -SecurityIds $secIds)) { return }
        # Backup first: System Restore point + (if USB present) settings backup
        Invoke-PreApplyBackup
        # Confirm before destructive / risky items even when run via "Apply ALL".
        $maintIds = @($script:maintChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        if ($secIds -contains 'bitlocker' -or $secIds -contains 'officewsh' -or $secIds -contains 'lockout' `
            -or $maintIds -contains 'recyclebin' -or $maintIds -contains 'cleantemp' -or $maintIds -contains 'browscache') {
            if (-not (Show-YesNo 'Apply ALL will also: enable BitLocker, disable Script Host + macros, set account lockout, empty the recycle bin, clear temp + browser caches.`n`nProceed?' 'Confirm' Warn)) { return }
        }
        $svc = @($script:svcChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        Write-Log '===== APPLY ALL ====='
        if ($svc.Count -gt 0) { Backup-ServicesSnapshot; Disable-Services -Names $svc }
        foreach ($id in $secIds)   { Apply-SecurityItem -Id $id }
        foreach ($id in $maintIds) { Invoke-MaintenanceItem -Id $id }
        Write-Log '===== APPLY ALL finished ====='
        Save-LastRun -services $svc -security $secIds -maint $maintIds
        Show-Message 'All selected items applied. A reboot is recommended.' 'Finished' Info
    } catch {
        Write-Log "ERROR: $($_.Exception.Message)"
        Show-Message ("Could not complete: " + $_.Exception.Message) 'Error'
    }
})

$btnRestoreAll.add_Click({
    Write-Log '===== RESTORE ALL ====='
    Restore-Services
    Restore-Security
    Restore-Maintenance
    Write-Log '===== RESTORE ALL finished ====='
    Show-Message 'All settings restored to defaults.' 'Finished' Info
})

$btnReviewAll.add_Click({
    Write-Log '--- Full review ---'
    Test-ServicesDisabled
    Save-SecurityReview
    Get-MaintenanceReport
    Get-DiagnosticsReport
})

$btnHelp.add_Click({ Show-SoHelpWindow })
$btnExplainSec.add_Click({ Show-ItemExplanations -Items $script:SecurityItems -Checks $script:secChecks })
$btnExplainMaint.add_Click({ Show-ItemExplanations -Items $script:MaintenanceItems -Checks $script:maintChecks })
$btnExport.add_Click({ Export-Settings })
$btnImport.add_Click({ Import-Settings })
$btnUndoLast.add_Click({ Undo-LastRun })
$btnBackup.add_Click({ Backup-UserSettings })
$btnRestoreBk.add_Click({ Restore-UserSettings })
$btnPreflight.add_Click({
    $secIds = @($script:secChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    Test-PreFlight -SecurityIds $secIds
})
$btnVerifyBk.add_Click({ Test-BackupIntegrity })
$btnScheduleMaint.add_Click({ Schedule-AutoMaintenance })

$btnMaintRun.add_Click({
    $ids = @($script:maintChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { Show-Message 'Tick at least one cleanup item.' 'Nothing selected' Warn; return }
    if ($ids -contains 'recyclebin') {
        if (-not (Show-YesNo 'Empty the Recycle Bin permanently?' 'Confirm' Warn)) { return }
    }
    Write-Log '=== Maintenance started ==='
    foreach ($id in $ids) { Invoke-MaintenanceItem -Id $id }
    Write-Log '=== Maintenance finished ==='
    Save-LastRun -maint $ids
    Show-Message 'Cleanup finished.' 'Finished' Info
})

$btnMaintRestore.add_Click({
    Write-Log '--- Restore maintenance ---'
    Restore-Maintenance
    Show-Message 'Maintenance settings restored.' 'Finished' Info
})

$btnMaintReport.add_Click({ Write-Log '--- Maintenance report ---'; Get-MaintenanceReport })

$btnRepairRun.add_Click({
    $ids = @($script:repairChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { Show-Message 'Tick at least one repair tool.' 'Nothing selected' Warn; return }
    if ($ids -contains 'chkdsk') {
        if (-not (Show-YesNo 'chkdsk will run at the next restart. Continue?' 'Confirm' Warn)) { return }
    }
    Write-Log '=== System repair started (this can take a while) ==='
    foreach ($id in $ids) { Invoke-RepairItem -Id $id }
    Write-Log '=== System repair finished ==='
    Show-Message 'Repair finished.' 'Finished' Info
})

# --------------------------------------------------------------------------
# Help window (RichTextBox; built from HELP.md-ish text)
# --------------------------------------------------------------------------
function Show-SoHelpWindow {
    $helpPath = Join-Path $ScriptRoot 'HELP.md'
    if (-not (Test-Path -LiteralPath $helpPath)) {
        $helpText = 'No HELP.md found beside this script. Please reinstall the package.'
    } else {
        $helpText = Get-Content -LiteralPath $helpPath -Raw -ErrorAction SilentlyContinue
    }
    $hf = New-Object System.Windows.Forms.Form
    $hf.Text = 'System Optimizer - Help / settings guide'
    $hf.ClientSize = New-Object System.Drawing.Size(860, 760)
    $hf.StartPosition = 'CenterParent'
    $hf.MinimizeBox = $false
    $hf.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.ReadOnly = $true; $rtb.WordWrap = $true; $rtb.ScrollBars = 'Vertical'
    $rtb.Dock = 'Fill'; $rtb.BackColor = [System.Drawing.Color]::White
    $rtb.ForeColor = [System.Drawing.Color]::Black
    $rtb.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $rtb.BorderStyle = 'None'
    $hf.Controls.Add($rtb) | Out-Null
    $cTitle = [System.Drawing.Color]::FromArgb(31,78,121)
    $cHead  = [System.Drawing.Color]::FromArgb(0,90,158)
    $cSub   = [System.Drawing.Color]::FromArgb(31,78,121)
    $cItem  = [System.Drawing.Color]::FromArgb(40,40,40)
    $cBody  = [System.Drawing.Color]::FromArgb(60,60,60)
    $cNote  = [System.Drawing.Color]::FromArgb(150,110,0)
    $cBullet= [System.Drawing.Color]::FromArgb(0,120,0)
    function Emit([string]$text, [string]$style) {
        $rtb.SelectionStart = $rtb.TextLength
        $rtb.SelectionLength = 0
        $b = [System.Drawing.FontStyle]::Bold
        $r = [System.Drawing.FontStyle]::Regular
        $i = [System.Drawing.FontStyle]::Italic
        switch ($style) {
            'h1'    { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI',15,$b); $rtb.SelectionColor = $cTitle }
            'h2'    { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI',12,$b); $rtb.SelectionColor = $cHead }
            'h3'    { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI',11,$b); $rtb.SelectionColor = $cSub }
            'item'  { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI',10,$b); $rtb.SelectionColor = $cItem }
            'note'  { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI',10,$i); $rtb.SelectionColor = $cNote }
            'bullet'{ $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI',10,$r); $rtb.SelectionColor = $cBullet }
            default { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI',10,$r); $rtb.SelectionColor = $cBody }
        }
        $rtb.AppendText($text + [Environment]::NewLine)
    }
    foreach ($raw in ($helpText -split "`r?`n")) {
        $line = $raw.TrimEnd()
        if      ($line -match '^=+\s*$')                  { Emit '' 'body'; continue }
        if      ($line -match '^#\s+(.+)$')                { Emit ($line -replace '^#\s+','') 'h1'; continue }
        if      ($line -match '^##\s+(.+)$')               { Emit ($line -replace '^##\s+','') 'h2'; continue }
        if      ($line -match '^###\s+(.+)$')              { Emit ($line -replace '^###\s+','') 'h3'; continue }
        if      ($line -match '^(\d+\.\s+|-\s+|\*\s+)')    { Emit $line 'bullet'; continue }
        if      ($line -match '^(IMPORTANT|Note|Tradeoff|Restore does NOT|Warning|TIP:|NOTE:)') { Emit $line 'note'; continue }
        Emit $line 'body'
    }
    [void]$hf.ShowDialog()
}

# --------------------------------------------------------------------------
# Open
# --------------------------------------------------------------------------
Write-Log 'Ready. Pick items on the tabs, then Apply. Restore ALL returns everything to defaults.'
Write-Log ("Backups: " + $script:Paths.ServiceBackup + "  and  " + $script:Paths.SecurityBackup)

if ($SmokeTest) {
    $marker = Join-Path $env:TEMP 'so_smoke.txt'
    New-Item -ItemType Directory -Path (Split-Path $marker) -Force | Out-Null
    Set-Content -Path $marker -Value 'SmokeTest bound = TRUE'
    $cb = [System.Threading.TimerCallback]{ param($state)
        try { $script:smokeTimer.Dispose() } catch { }
        try { $form.Invoke([System.Action]{ $form.Close() }) | Out-Null } catch { }
    }
    $script:smokeTimer = New-Object System.Threading.Timer($cb, $null, 3000, -1)
}

# --------------------------------------------------------------------------
# V1.6 Easy/Advanced handlers
# --------------------------------------------------------------------------
# Items One-Click Optimize never touches (Advanced mode only).
$script:EasyRisky = @('bitlocker','officewsh','lockout','recyclebin','cleantemp','browscache')

# Build the interactive list of items One-Click will apply (user can untick).
function Update-EasyItems {
    if (-not $script:clbEasy) { return }
    $script:clbEasy.Items.Clear()
    $script:easyItemsList = New-Object System.Collections.Generic.List[object]
    $script:clbEasy.BeginUpdate()
    try {
        # Folders to back up (all ticked by default; user can untick)
        $folderNames = @('Desktop','Documents','Downloads','Pictures','Videos','Music')
        $script:clbEasy.Items.Add('-- FOLDERS TO BACK UP --', $false) | Out-Null
        $script:easyItemsList.Add([pscustomobject]@{ Id=$null; Category='header'; Text='FOLDERS' })
        foreach ($fn in $folderNames) { $script:clbEasy.Items.Add($fn, $true) | Out-Null; $script:easyItemsList.Add([pscustomobject]@{ Id=$fn; Category='folder'; Text=$fn }) }
        $svc = @($script:svcChecks   | Where-Object { $_.Checked -and ($_.Tag -notin $script:EasyRisky) })
        if ($svc.Count -gt 0) {
            $script:clbEasy.Items.Add('-- SERVICES TO DISABLE --', $false) | Out-Null
            $script:easyItemsList.Add([pscustomobject]@{ Id=$null; Category='header'; Text='SERVICES' })
            foreach ($c in $svc) { $script:clbEasy.Items.Add($c.Text, $true) | Out-Null; $script:easyItemsList.Add([pscustomobject]@{ Id=$c.Tag; Category='svc'; Text=$c.Text }) }
        }
        $sec = @($script:secChecks   | Where-Object { $_.Checked -and ($_.Tag -notin $script:EasyRisky) })
        if ($sec.Count -gt 0) {
            $script:clbEasy.Items.Add('-- SECURITY TO APPLY --', $false) | Out-Null
            $script:easyItemsList.Add([pscustomobject]@{ Id=$null; Category='header'; Text='SECURITY' })
            foreach ($c in $sec) { $script:clbEasy.Items.Add($c.Text, $true) | Out-Null; $script:easyItemsList.Add([pscustomobject]@{ Id=$c.Tag; Category='sec'; Text=$c.Text }) }
        }
        $mt = @($script:maintChecks | Where-Object { $_.Checked -and ($_.Tag -notin $script:EasyRisky) })
        if ($mt.Count -gt 0) {
            $script:clbEasy.Items.Add('-- MAINTENANCE --', $false) | Out-Null
            $script:easyItemsList.Add([pscustomobject]@{ Id=$null; Category='header'; Text='MAINTENANCE' })
            foreach ($c in $mt) { $script:clbEasy.Items.Add($c.Text, $true) | Out-Null; $script:easyItemsList.Add([pscustomobject]@{ Id=$c.Tag; Category='maint'; Text=$c.Text }) }
        }
    } finally { $script:clbEasy.EndUpdate() }
}

# Update the Easy progress bar + stage label (and repaint so it shows).
function Set-EasyProgress([int]$Pct, [string]$Stage) {
    if ($script:prgEasy) { $script:prgEasy.Value = [math]::Min(100, [math]::Max(0, $Pct)) }
    if ($script:lblEasyStage) { $script:lblEasyStage.Text = $Stage }
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-EasyHealth {
    try { $c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"; $script:lblHealthFree.Text = "C: free space: $([math]::Round($c.FreeSpace/1GB,1)) GB" } catch { $script:lblHealthFree.Text = 'C: free space: ?' }
    try {
        $info = Get-LastBackupInfo
        if ($info) {
            $ts = $null; try { $ts = [datetime]::Parse($info.LastBackup) } catch {}
            if ($ts) { $d = [math]::Round(((Get-Date) - $ts).TotalDays, 1); $script:lblHealthBackup.Text = "Last backup: $d day(s) ago" } else { $script:lblHealthBackup.Text = 'Last backup: unknown' }
        } else { $script:lblHealthBackup.Text = 'Last backup: none yet' }
    } catch { $script:lblHealthBackup.Text = 'Last backup: ?' }
    $avn = Get-ActiveAntivirus; $script:lblHealthDefender.Text = 'Antivirus: ' + $(if ($avn.Count -ge 1) { ($avn -join ', ') } else { 'none detected' })
    if (Test-UsbPresent) { $script:lblHealthUsb.Text = 'USB drive: present'; $script:lblHealthUsb.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 0) }
    else { $script:lblHealthUsb.Text = 'USB drive: NOT detected - plug one in for backup'; $script:lblHealthUsb.ForeColor = [System.Drawing.Color]::FromArgb(190, 30, 30) }
    # PC Health score (0-100)
    try {
        $h = Get-PcHealthScore
        $script:lblHealthScore.Text = "$($h.Score)/100"
        if ($h.Score -ge 80) { $script:lblHealthScore.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 0) }
        elseif ($h.Score -ge 50) { $script:lblHealthScore.ForeColor = [System.Drawing.Color]::FromArgb(200, 150, 0) }
        else { $script:lblHealthScore.ForeColor = [System.Drawing.Color]::FromArgb(190, 30, 30) }
        $script:healthRec = $h.Recommendations
    } catch { $script:lblHealthScore.Text = '...' }
}

# Banner "Back up now" button (Advanced tab)
$script:btnBannerBackup.add_Click({
    Write-Log '=== Backup now (banner) ==='
    $script:BackupSession = New-BackupSession
    Backup-UserSettings
    Backup-UserFolders | Out-Null
    Update-EasyHealth
    Show-Message 'Backup complete. Your settings and files are safe on the USB.' 'Backup' Info
})
$btnRefreshHealth.add_Click({ Update-EasyHealth })

# --- Easy: One-Click Optimize ---
$script:btnEasyOptimize.add_Click({
    if (-not (Test-UsbPresent)) {
        Show-Message "One-Click Optimize needs a USB drive so it can back up your settings & files FIRST (safety).`n`nPlease plug in a USB drive, then run One-Click Optimize again." 'USB required' Warn
        return
    }
    # Read what the user chose: folders to back up + items to apply.
    $checked = @()
    for ($i = 0; $i -lt $script:clbEasy.Items.Count; $i++) {
        if ($script:clbEasy.GetItemChecked($i) -and $script:easyItemsList[$i].Id) { $checked += $script:easyItemsList[$i] }
    }
    $folderIds = @($checked | Where-Object { $_.Category -eq 'folder' } | ForEach-Object { $_.Id })
    # Check the USB has enough free space for the selected folders.
    Set-EasyProgress 3 'Checking USB space...'
    try {
        $backupGB = Get-BackupSizeGB -Folders $folderIds
        $usbFreeGB = Get-UsbFreeSpaceGB
        if ($usbFreeGB -ne $null -and $backupGB -gt $usbFreeGB) {
            Set-EasyProgress 0 'Ready'
            Show-Message ("Your backup needs about $backupGB GB, but the USB drive only has $usbFreeGB GB free.`n`nPlease free up space on the USB (or use a larger USB drive), then run One-Click Optimize again.") 'USB too small' Warn
            return
        }
    } catch { Write-Log "WARN could not check USB space: $($_.Exception.Message)" }
    Set-EasyProgress 0 'Ready'
    if (-not (Show-YesNo "One-Click Optimize will:`n`n  1. Back up your settings & files to this USB`n  2. Create a restore point (so you can undo)`n  3. Disable safe background services (telemetry, Xbox, Fax, etc.)`n  4. Turn on recommended security (Defender, firewall, screen lock)`n  5. Do safe cleanup`n`nIt will NOT enable BitLocker, disable Office macros, or set account lockout - those are Advanced mode only.`n`nContinue?" 'One-Click Optimize' Question)) { Set-EasyProgress 0 'Ready'; return }
    try {
        $script:btnEasyOptimize.Enabled = $false
        Set-EasyProgress 2 'Starting - back up your settings & files first...'
        Write-Log '===== EASY ONE-CLICK OPTIMIZE ====='
        $script:BackupSession = New-BackupSession
        Set-EasyProgress 5 'Backing up your settings...'
        Backup-UserSettings
        Set-EasyProgress 25 'Backing up your folders...'
        Backup-UserFolders -Folders $folderIds | Out-Null
        Set-EasyProgress 45 'Creating a restore point...'
        try { Checkpoint-Computer -Description 'System Optimizer Easy - before changes' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop | Out-Null; Write-Log 'Restore point created.' } catch { Write-Log "WARN could not create restore point: $($_.Exception.Message)" }
        $svcIds   = @($checked | Where-Object { $_.Category -eq 'svc' } | ForEach-Object { $_.Id })
        $secIds   = @($checked | Where-Object { $_.Category -eq 'sec' } | ForEach-Object { $_.Id })
        $maintIds = @($checked | Where-Object { $_.Category -eq 'maint' } | ForEach-Object { $_.Id })
        Set-EasyProgress 60 'Disabling safe services...'
        if ($svcIds.Count -gt 0) { Backup-ServicesSnapshot; Disable-Services -Names $svcIds }
        Set-EasyProgress 75 'Applying security...'
        $si = 0; foreach ($id in $secIds) { Apply-SecurityItem -Id $id; $si++; Set-EasyProgress (75 + ($si * 10)) ("Applying security: " + $si + "/" + $secIds.Count) }
        Set-EasyProgress 95 'Running maintenance...'
        $mi = 0; foreach ($id in $maintIds) { Invoke-MaintenanceItem -Id $id; $mi++; Set-EasyProgress (95 + ($mi * 5)) ("Running maintenance: " + $mi + "/" + $maintIds.Count) }
        Save-LastRun -services $svcIds -security $secIds -maint $maintIds
        Set-EasyProgress 100 'Done'
Update-EasyHealth
        Update-EasyItems
        $script:btnEasyOptimize.Enabled = $true
        Set-EasyProgress 100 'Done'
Write-Log '===== EASY OPTIMIZE DONE ====='
Show-Message ("Done! Your PC was optimized safely.`n`n  - " + $svcIds.Count + " safe service(s) disabled`n  - " + $secIds.Count + " security item(s) applied`n  - " + $maintIds.Count + " maintenance item(s) done`n`nDetails are in the log below. A restart is recommended so everything takes effect.`n`nClick OK to continue.") 'Finished' Info
    } catch {
        $script:btnEasyOptimize.Enabled = $true
        Write-Log "ERROR: $($_.Exception.Message)"
        Show-Message ("Could not finish: " + $_.Exception.Message) 'Error'
    }
})

# --- Easy: Restore wizard ---
function Show-RestorePick {
    param([string]$Source)
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Restore your files & settings'
    $dlg.ClientSize = New-Object System.Drawing.Size(620, 540)
    $dlg.FormBorderStyle = 'FixedDialog'; $dlg.StartPosition = 'CenterParent'; $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = [System.Drawing.Color]::White

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = 'Restore your files & settings'
    $lblTitle.AutoSize = $true; $lblTitle.Location = New-Object System.Drawing.Point(20, 16)
    $lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $dlg.Controls.Add($lblTitle)

    $lblFrom = New-Object System.Windows.Forms.Label
    $lblFrom.Text = "From this backup:  $Source"
    $lblFrom.AutoSize = $true; $lblFrom.Location = New-Object System.Drawing.Point(20, 48)
    $lblFrom.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 90)
    $dlg.Controls.Add($lblFrom)

    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = 'Tick what you want to bring back to this PC - it will be restored to the same folders.'
    $lblDesc.AutoSize = $false; $lblDesc.Location = New-Object System.Drawing.Point(20, 74); $lblDesc.Size = New-Object System.Drawing.Size(580, 22)
    $dlg.Controls.Add($lblDesc)

    $gbSettings = New-Object System.Windows.Forms.GroupBox
    $gbSettings.Text = 'Settings'; $gbSettings.Location = New-Object System.Drawing.Point(20, 104); $gbSettings.Size = New-Object System.Drawing.Size(580, 52)
    $dlg.Controls.Add($gbSettings)
    $chkSettings = New-Object System.Windows.Forms.CheckBox
    $chkSettings.Text = 'Settings (browser bookmarks, Wi-Fi, profile)'; $chkSettings.Checked = $true
    $chkSettings.AutoSize = $true; $chkSettings.Location = New-Object System.Drawing.Point(14, 20)
    $gbSettings.Controls.Add($chkSettings)

    $gbFolders = New-Object System.Windows.Forms.GroupBox
    $gbFolders.Text = 'My folders'; $gbFolders.Location = New-Object System.Drawing.Point(20, 166); $gbFolders.Size = New-Object System.Drawing.Size(580, 240)
    $dlg.Controls.Add($gbFolders)
    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.Location = New-Object System.Drawing.Point(12, 24); $clb.Size = New-Object System.Drawing.Size(556, 155); $clb.CheckOnClick = $true; $clb.BackColor = [System.Drawing.Color]::White
    foreach ($n in (Get-UserFolderMap).Keys) { $null = $clb.Items.Add($n, $true) }
    $gbFolders.Controls.Add($clb)
    $chkFiles = New-Object System.Windows.Forms.CheckBox
    $chkFiles.Text = 'Restore only specific files (not whole folders)'
    $chkFiles.AutoSize = $true; $chkFiles.Location = New-Object System.Drawing.Point(12, 190)
    $gbFolders.Controls.Add($chkFiles)

    $lblNote = New-Object System.Windows.Forms.Label
    $lblNote.Text = "Tip: after restoring, sign out and back in (or restart) so everything takes effect."
    $lblNote.AutoSize = $false; $lblNote.Location = New-Object System.Drawing.Point(20, 414); $lblNote.Size = New-Object System.Drawing.Size(580, 22)
    $lblNote.ForeColor = [System.Drawing.Color]::FromArgb(150, 110, 0)
    $dlg.Controls.Add($lblNote)

    $btnCancel = New-Object System.Windows.Forms.Button; $btnCancel.Text = 'Cancel'; $btnCancel.Size = New-Object System.Drawing.Size(100, 34); $btnCancel.Location = New-Object System.Drawing.Point(380, 480)
    $btnCancel.add_Click({ $dlg.DialogResult = 'Cancel'; $dlg.Close() })
    $dlg.Controls.Add($btnCancel)
    $btnOK = New-Object System.Windows.Forms.Button; $btnOK.Text = 'Restore'; $btnOK.Size = New-Object System.Drawing.Size(120, 34); $btnOK.Location = New-Object System.Drawing.Point(488, 480)
    $btnOK.BackColor = [System.Drawing.Color]::FromArgb(0, 102, 204); $btnOK.ForeColor = [System.Drawing.Color]::White
    $btnOK.add_Click({ $dlg.DialogResult = 'OK'; $dlg.Close() })
    $dlg.Controls.Add($btnOK)

    if ($dlg.ShowDialog() -eq 'OK') {
        return @{ Source = $Source; Folders = @($clb.CheckedItems); Settings = $chkSettings.Checked; SpecificFiles = $chkFiles.Checked }
    }
    return $null
}

function Show-FilePick {
    param([string]$Source, [string[]]$Folders)
    $filesRoot = Join-Path $Source 'files'
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($f in $Folders) {
        $bk = Join-Path $filesRoot $f
        if (-not (Test-Path $bk)) { continue }
        Get-ChildItem -LiteralPath $bk -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = $_.FullName.Substring($bk.Length).TrimStart('\')
            $items.Add([pscustomobject]@{ Folder = $f; Rel = $rel; Full = $_.FullName })
        }
    }
    if ($items.Count -eq 0) { Show-Message 'No files found in the backup.' 'Restore' Warn; return $null }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Choose specific files to restore'
    $dlg.ClientSize = New-Object System.Drawing.Size(620, 480)
    $dlg.FormBorderStyle = 'FixedDialog'; $dlg.StartPosition = 'CenterParent'; $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.Location = New-Object System.Drawing.Point(12,12); $clb.Size = New-Object System.Drawing.Size(590,400); $clb.CheckOnClick = $true
    foreach ($i in $items) { $null = $clb.Items.Add($i.Folder + ' \ ' + $i.Rel, $false) }
    $dlg.Controls.Add($clb)
    $btnOK = New-Object System.Windows.Forms.Button; $btnOK.Text = 'Restore selected'; $btnOK.Size = New-Object System.Drawing.Size(140,30); $btnOK.Location = New-Object System.Drawing.Point(460,430)
    $btnOK.add_Click({ $dlg.DialogResult = 'OK'; $dlg.Close() })
    $dlg.Controls.Add($btnOK)
    if ($dlg.ShowDialog() -eq 'OK') {
        $picked = @()
        for ($i = 0; $i -lt $clb.Items.Count; $i++) { if ($clb.GetItemChecked($i)) { $picked += $items[$i] } }
        return $picked
    }
    return $null
}

$script:btnEasyRestore.add_Click({
    if (-not (Show-YesNo "Restore your files & settings from the USB backup.`n`nContinue?" 'Restore' Question)) { return }
    $src = Get-LatestBackupSession
    if (-not $src) {
        $cands = Get-UsbBackupFolders
        if ($cands.Count -eq 0) { Show-Message "No USB backup found.`nPlug in the USB drive and try again." 'Restore' Warn; return }
        if ($cands.Count -eq 1) { $src = $cands[0] }
        else {
            $dlg = New-Object System.Windows.Forms.Form
            $dlg.Text = 'Choose which PC backup'; $dlg.ClientSize = New-Object System.Drawing.Size(420,300); $dlg.StartPosition = 'CenterParent'
            $lb = New-Object System.Windows.Forms.ListBox; $lb.Location = New-Object System.Drawing.Point(12,12); $lb.Size = New-Object System.Drawing.Size(390,220)
            $lb.Items.AddRange([string[]]$cands); $dlg.Controls.Add($lb)
            $btn = New-Object System.Windows.Forms.Button; $btn.Text = 'Use this'; $btn.Location = New-Object System.Drawing.Point(300,250); $btn.Size = New-Object System.Drawing.Size(90,30)
            $btn.add_Click({ $dlg.DialogResult = 'OK'; $dlg.Close() }); $dlg.Controls.Add($btn)
            if ($dlg.ShowDialog() -eq 'OK' -and $lb.SelectedItem) { $src = $lb.SelectedItem } else { return }
        }
    }
    $pick = Show-RestorePick -Source $src
    if (-not $pick) { return }
    Write-Log "=== Easy restore from $src ==="
    if ($pick.SpecificFiles) {
        $picked = Show-FilePick -Source $src -Folders $pick.Folders
        if (-not $picked) { return }
        $sel = @{}
        foreach ($p in $picked) {
            if (-not $sel.ContainsKey($p.Folder)) { $sel[$p.Folder] = New-Object System.Collections.Generic.List[string] }
            $sel[$p.Folder].Add($p.Rel)
        }
        $conv = @{}; foreach ($k in $sel.Keys) { $conv[$k] = @($sel[$k]) }
        Restore-UserFolders -Source $src -Selections $conv
    } else {
        $sel = @{}
        foreach ($n in $pick.Folders) { $sel[$n] = $true }
        if ($sel.Count -gt 0) { Restore-UserFolders -Source $src -Selections $sel }
        if ($pick.Settings) { Restore-UserSettings -Source $src }
    }
    Update-EasyHealth
    Show-Message "Restore finished.`n`nSome settings need you to sign out/in or restart to take effect.`n`nClick OK to continue." 'Restore done' Info
})

# --- Utilities handlers ---
function Set-UtilsGrid {
    param($rows, [string[]]$cols)
    $dt = New-Object System.Data.DataTable
    foreach ($c in $cols) { [void]$dt.Columns.Add($c) }
    foreach ($r in $rows) { [void]$dt.Rows.Add([object[]]$r) }
    $script:dgUtil.AutoGenerateColumns = $true
    $script:dgUtil.DataSource = $null
    $script:dgUtil.DataSource = $dt
}
# Run a scan in a background runspace so the animated "working" bar shows,
# then call OnDone with the result on the UI thread.
# Show a clear "working" indicator, run a task, then hide it.
function Show-Working([string]$Text) {
    $script:utilButtons = @($btnUtilDup,$btnUtilDisk,$btnUtilLarge,$btnUtilProg,$btnUtilStartup,$btnUtilShort,$btnUtilDrive,$btnUtilNet,$btnUtilHealth,$btnUtilKeepNewest,$btnUtilDelete,$btnUtilOpen,$btnPerfBoost,$btnPerfRestore,$btnSysReport,$btnUtilHardware,$btnUtilNetwork,$btnUtilBattery,$btnUtilApps)
    $script:lblWork.Text = $Text; $script:lblWork.Visible = $true
    $script:prgWork.Visible = $true
    foreach ($b in $script:utilButtons) { $b.Enabled = $false }
    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
    [System.Windows.Forms.Application]::DoEvents()
}
function Hide-Working {
    $script:prgWork.Visible = $false
    $script:lblWork.Text = 'Done'
    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
    foreach ($b in $script:utilButtons) { $b.Enabled = $true }
}
function Start-BackgroundScan {
    param([string]$WorkingText, [scriptblock]$Action, [scriptblock]$OnDone = $null)
    Show-Working $WorkingText
    try { & $Action } catch { Write-Log "Task error: $($_.Exception.Message)"; Show-Message ("Could not finish: " + $_.Exception.Message) 'Error' }
    Hide-Working
    if ($OnDone) { & $OnDone }
}
function Run-DupScan([string]$Path) {
    $script:utilMode = 'dup'; Write-Log "Scanning for duplicate files: $Path"
    try {
        $groups = Find-DuplicateFiles -Path $Path
        $rows = @(); $script:dupMeta = @()
        for ($gi = 0; $gi -lt $groups.Count; $gi++) {
            foreach ($f in $groups[$gi].Files) {
                $rows += ,@('Duplicate', $f.Path, "$($f.SizeMB) MB")
                $lm = $null; try { $lm = (Get-Item -LiteralPath $f.Path -ErrorAction Stop).LastWriteTime } catch { $lm = $null }
                $script:dupMeta += [pscustomobject]@{ Group = $gi; Path = $f.Path; LastWriteTime = $lm }
            }
        }
        Set-UtilsGrid $rows @('Type','Path','Size')
        Write-Log ("Duplicates: " + $rows.Count + " files in " + $groups.Count + " group(s)")
        if ($rows.Count -eq 0) { Show-Message 'No duplicate files found.' 'Duplicate finder' Info }
    } catch { Write-Log "ERROR scanning: $($_.Exception.Message)"; Show-Message ("Scan could not finish: " + $_.Exception.Message) 'Error' }
}
function Run-LargeScan([string]$Path) {
    $script:utilMode = 'large'; Write-Log "Finding large files: $Path"
    try {
        $rows = @(Find-LargeFiles -Path $Path -MinimumMB 100 | ForEach-Object { ,@('Large file', $_.Path, "$($_.SizeMB) MB") })
        Set-UtilsGrid $rows @('Type','Path','Size')
        Write-Log ("Large files: " + $rows.Count)
        if ($rows.Count -eq 0) { Show-Message 'No large files (over 100 MB) found.' 'Large-file finder' Info }
    } catch { Write-Log "ERROR scanning: $($_.Exception.Message)"; Show-Message ("Scan could not finish: " + $_.Exception.Message) 'Error' }
}
$btnUtilDup.add_Click({
    $script:utilMode = 'dup'
    Start-BackgroundScan -WorkingText 'Scanning for duplicate files - please wait...' -Action {
        $groups = Find-DuplicateFiles -Path $script:txtUtilPath.Text
        $rows = @(); $script:dupMeta = @()
        for ($gi = 0; $gi -lt $groups.Count; $gi++) {
            foreach ($f in $groups[$gi].Files) {
                $rows += ,@('Duplicate', $f.Path, "$($f.SizeMB) MB")
                $lm = $null; try { $lm = (Get-Item -LiteralPath $f.Path -ErrorAction Stop).LastWriteTime } catch { $lm = $null }
                $script:dupMeta += [pscustomobject]@{ Group = $gi; Path = $f.Path; LastWriteTime = $lm }
            }
        }
        Set-UtilsGrid $rows @('Type','Path','Size')
        Write-Log ("Duplicates: " + $rows.Count + " files")
    } -OnDone { if ($script:dgUtil.Rows.Count -eq 0) { Show-Message 'No duplicate files found.' 'Duplicate finder' Info } }
})
$btnUtilKeepNewest.add_Click({
    if ($script:utilMode -ne 'dup' -or $script:dupMeta.Count -eq 0) { Show-Message 'Run Duplicate finder first, then click Keep newest.' 'Keep newest' Warn; return }
    $byGroup = @{}
    for ($i = 0; $i -lt $script:dupMeta.Count; $i++) {
        $g = $script:dupMeta[$i].Group
        if (-not $byGroup.ContainsKey($g)) { $byGroup[$g] = New-Object System.Collections.ArrayList }
        [void]$byGroup[$g].Add($i)
    }
    $selected = 0
    foreach ($g in $byGroup.Keys) {
        $idx = @($byGroup[$g])
        if ($idx.Count -lt 2) { continue }
        $newest = $null; $newestI = -1
        foreach ($i in $idx) {
            $t = $script:dupMeta[$i].LastWriteTime
            if ($null -eq $newest -or ($t -and $t -gt $newest)) { $newest = $t; $newestI = $i }
        }
        foreach ($i in $idx) { if ($i -ne $newestI) { $script:dgUtil.Rows[$i].Selected = $true; $selected++ } }
    }
    Write-Log ("Keep newest: selected " + $selected + " older copy(s) to remove")
    Show-Message ("Selected $selected older duplicate copy(s) to remove (kept the newest of each group).`n`nNow click 'Send selected to Recycle Bin'.") 'Keep newest' Info
})
$btnUtilDisk.add_Click({
    $script:utilMode = 'disk'
    Start-BackgroundScan -WorkingText 'Analyzing disk usage - please wait...' -Action {
        $rows = @()
        foreach ($item in (Get-DiskUsage -Path $script:txtUtilPath.Text)) { $rows += ,@('Folder', $item.Name, "$($item.SizeMB) MB", $item.Path) }
        Set-UtilsGrid $rows @('Type','Folder','Size','Path')
        Write-Log ("Disk usage: " + $rows.Count + " top folders")
    }
})
$btnUtilLarge.add_Click({
    $script:utilMode = 'large'
    Start-BackgroundScan -WorkingText 'Finding large files - please wait...' -Action {
        $rows = @(Find-LargeFiles -Path $script:txtUtilPath.Text -MinimumMB 100 | ForEach-Object { ,@('Large file', $_.Path, "$($_.SizeMB) MB") })
        Set-UtilsGrid $rows @('Type','Path','Size')
        Write-Log ("Large files: " + $rows.Count)
    } -OnDone { if ($script:dgUtil.Rows.Count -eq 0) { Show-Message 'No large files (over 100 MB) found.' 'Large-file finder' Info } }
})
$btnUtilProg.add_Click({
    Start-BackgroundScan -WorkingText 'Exporting programs list - please wait...' -Action {
        $script:progExport = Export-InstalledPrograms
    } -OnDone { if ($script:progExport) { Show-Message "Installed programs list saved to:`n$script:progExport" 'Export done' Info } }
})
$btnUtilBrowse.add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description = 'Choose a folder or drive to scan'
    if ($d.ShowDialog() -eq 'OK') { $script:txtUtilPath.Text = $d.SelectedPath }
})
$btnUtilDelete.add_Click({
    if ($script:utilMode -notin @('dup','large','shortcut')) { Show-Message 'This list has nothing to delete. Run Duplicate finder or Large-file finder first, then select a row.' 'Utilities' Warn; return }
    $paths = @(); foreach ($row in $script:dgUtil.SelectedRows) { $v = $row.Cells['Path'].Value; if ($v -and -not [string]::IsNullOrWhiteSpace([string]$v)) { $paths += [string]$v } }
    if ($paths.Count -eq 0) { Show-Message "No row is selected.`n`nClick on a duplicate row first (so it is highlighted), then click 'Send selected to Recycle Bin' again." 'Delete' Warn; return }
    if (-not (Show-YesNo ("Send " + $paths.Count + " item(s) to the Recycle Bin?`nYou can undo this from the Recycle Bin.") 'Confirm' Warn)) { return }
    $n = Remove-ToRecycleBin -Paths $paths
    Write-Log ("Sent " + $n + " item(s) to Recycle Bin")
    if ($n -gt 0) {
        if ($script:utilMode -eq 'dup') { Run-DupScan $script:txtUtilPath.Text }
        elseif ($script:utilMode -eq 'large') { Run-LargeScan $script:txtUtilPath.Text }
    }
    Show-Message ("Sent " + $n + " item(s) to the Recycle Bin.`nThe list has been refreshed.`nIf you change your mind, restore them from the Recycle Bin.") 'Done' Info
})
# Open the folder (or select the file) in File Explorer for the given path.
function Open-InExplorer([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer) { Start-Process explorer.exe -ArgumentList "`"$Path`"" | Out-Null }
    else { Start-Process explorer.exe -ArgumentList "/select,`"$Path`"" | Out-Null }
}
# Startup Manager dialog (V1.7): list boot entries + safe enable/disable.
function Show-StartupManager {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Startup Manager'
    $dlg.ClientSize = New-Object System.Drawing.Size(720, 520)
    $dlg.StartPosition = 'CenterParent'; $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Programs that run when Windows starts. Select one, then Disable or Enable - it is SAFE, nothing is deleted and you can change it back anytime."
    $lbl.Location = New-Object System.Drawing.Point(12, 8); $lbl.Size = New-Object System.Drawing.Size(696, 40)
    $dlg.Controls.Add($lbl)
    $dg = New-Object System.Windows.Forms.DataGridView
    $dg.Location = New-Object System.Drawing.Point(12, 54); $dg.Size = New-Object System.Drawing.Size(696, 360)
    $dg.AllowUserToAddRows = $false; $dg.ReadOnly = $true; $dg.SelectionMode = 'FullRowSelect'; $dg.AutoSizeColumnsMode = 'Fill'; $dg.BackgroundColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($dg)
    $script:startupEntries = @(Get-StartupEntries)
    $dt = New-Object System.Data.DataTable
    foreach ($c in @('Name','Status','Type','Command')) { [void]$dt.Columns.Add($c) }
    foreach ($e in $script:startupEntries) { [void]$dt.Rows.Add([object[]]@($e.Name, $e.Status, $e.Type, $e.Command)) }
    $dg.AutoGenerateColumns = $true; $dg.DataSource = $dt
    $btnDis = New-Object System.Windows.Forms.Button; $btnDis.Text = 'Disable selected'; $btnDis.Location = New-Object System.Drawing.Point(12, 428); $btnDis.Size = New-Object System.Drawing.Size(130, 30)
    $btnEn  = New-Object System.Windows.Forms.Button; $btnEn.Text  = 'Enable selected';   $btnEn.Location  = New-Object System.Drawing.Point(150, 428); $btnEn.Size  = New-Object System.Drawing.Size(130, 30)
    $btnOpen = New-Object System.Windows.Forms.Button; $btnOpen.Text = 'Open location';   $btnOpen.Location = New-Object System.Drawing.Point(290, 428); $btnOpen.Size = New-Object System.Drawing.Size(120, 30)
    $btnClose = New-Object System.Windows.Forms.Button; $btnClose.Text = 'Close';         $btnClose.Location = New-Object System.Drawing.Point(628, 428); $btnClose.Size = New-Object System.Drawing.Size(80, 30)
    $dlg.Controls.Add($btnDis); $dlg.Controls.Add($btnEn); $dlg.Controls.Add($btnOpen); $dlg.Controls.Add($btnClose)
    $btnDis.add_Click({
        if ($dg.SelectedRows.Count -eq 0) { Show-Message 'Select a startup item first.' 'Startup Manager' Warn; return }
        $idx = $dg.SelectedRows[0].Index; $e = $script:startupEntries[$idx]
        if (-not (Show-YesNo ("Disable '" + $e.Name + "' from starting with Windows?`nYou can enable it again anytime.") 'Startup Manager' Question)) { return }
        try { Disable-StartupEntry $e.Name $e.Location $e.Type; Write-Log "Disabled startup: $($e.Name)"; Show-Message ("Disabled '" + $e.Name + "'. It will no longer start with Windows.`nYou can enable it again from here anytime.") 'Startup Manager' Info; $dg.DataSource = $null; $script:startupEntries = @(Get-StartupEntries); $d2 = New-Object System.Data.DataTable; foreach ($c in @('Name','Status','Type','Command')) { [void]$d2.Columns.Add($c) }; foreach ($en in $script:startupEntries) { [void]$d2.Rows.Add([object[]]@($en.Name, $en.Status, $en.Type, $en.Command)) }; $dg.DataSource = $d2 } catch { Show-Message ("Could not disable: " + $_.Exception.Message) 'Startup Manager' Error }
    })
    $btnEn.add_Click({
        if ($dg.SelectedRows.Count -eq 0) { Show-Message 'Select a startup item first.' 'Startup Manager' Warn; return }
        $idx = $dg.SelectedRows[0].Index; $e = $script:startupEntries[$idx]
        try { Enable-StartupEntry $e.Name $e.Location $e.Type; Write-Log "Enabled startup: $($e.Name)"; Show-Message ("Enabled '" + $e.Name + "' again.") 'Startup Manager' Info; $dg.DataSource = $null; $script:startupEntries = @(Get-StartupEntries); $d2 = New-Object System.Data.DataTable; foreach ($c in @('Name','Status','Type','Command')) { [void]$d2.Columns.Add($c) }; foreach ($en in $script:startupEntries) { [void]$d2.Rows.Add([object[]]@($en.Name, $en.Status, $en.Type, $en.Command)) }; $dg.DataSource = $d2 } catch { Show-Message ("Could not enable: " + $_.Exception.Message) 'Startup Manager' Error }
    })
    $btnOpen.add_Click({
        if ($dg.SelectedRows.Count -eq 0) { Show-Message 'Select a startup item first.' 'Startup Manager' Warn; return }
        $idx = $dg.SelectedRows[0].Index; $e = $script:startupEntries[$idx]
        if ($e.Command) { Open-InExplorer $e.Command }
    })
    $btnClose.add_Click({ $dlg.Close() })
    [void]$dlg.ShowDialog()
}
$btnUtilStartup.add_Click({ Show-StartupManager })
$btnUtilShort.add_Click({
    $script:utilMode = 'shortcut'
    Start-BackgroundScan -WorkingText 'Scanning for broken shortcuts - please wait...' -Action {
        $rows = @(Find-BrokenShortcuts | ForEach-Object { ,@('Broken', $_.Path, "$($_.SizeMB) MB") })
        Set-UtilsGrid $rows @('Type','Path','Size')
        Write-Log ("Broken shortcuts: " + $rows.Count)
    } -OnDone { if ($script:dgUtil.Rows.Count -eq 0) { Show-Message 'No broken shortcuts found (your shortcuts all point to existing files).' 'Broken shortcuts' Info } }
})
$btnUtilDrive.add_Click({
    $script:utilMode = 'drive'
    Start-BackgroundScan -WorkingText 'Reading drive health - please wait...' -Action {
        $rows = @(Get-DriveHealth | ForEach-Object { ,@('Drive', $_.Name, $_.Status, "$($_.SizeGB) GB", $(if($null -ne $_.TempC){"$($_.TempC) C"}else{'-'}), $(if($null -ne $_.WearPct){"$($_.WearPct) %"}else{'-'})) })
        Set-UtilsGrid $rows @('Type','Name','Status','Size','Temp','Wear')
        Write-Log ("Drive health: " + $rows.Count + " disk(s)")
    }
})
$btnUtilNet.add_Click({
    if (-not (Show-YesNo "Network repair will flush DNS and reset Winsock (fixes many connection issues).`nYour network may briefly drop and a restart may be needed.`n`nContinue?" 'Network repair' Question)) { return }
    Start-BackgroundScan -WorkingText 'Repairing network - please wait...' -Action {
        $out = Invoke-NetworkRepair
        foreach ($l in $out) { Write-Log $l }
    } -OnDone { Show-Message "Network repair done.`n`nIf a restart is needed, please restart to finish.`n`nClick OK to continue." 'Network repair' Info }
})
$btnUtilHealth.add_Click({
    Start-BackgroundScan -WorkingText 'Running health check - please wait...' -Action {
        $script:healthReport = ((Get-SystemHealthReport) -join [Environment]::NewLine)
        Write-Log ('Health check: ' + $script:healthReport)
    } -OnDone { Show-Message $script:healthReport 'Health check' Info }
})
# Double-click a result row to jump to its folder
$script:dgUtil.add_CellDoubleClick({
    param($sender, $e)
    if ($e.RowIndex -ge 0 -and $e.RowIndex -lt $script:dgUtil.Rows.Count) {
        $v = $script:dgUtil.Rows[$e.RowIndex].Cells['Path'].Value
        if ($v) { Open-InExplorer ([string]$v) }
    }
})
$btnUtilOpen.add_Click({
    if ($script:utilMode -notin @('dup','large','shortcut')) { Show-Message 'This list has no file path to open. Run Duplicate finder, Large-file finder, or Broken shortcuts first.' 'Utilities' Warn; return }
    $done = $false
    foreach ($row in $script:dgUtil.SelectedRows) { if ($row.Cells['Path'].Value) { Open-InExplorer ([string]$row.Cells['Path'].Value); $done = $true; break } }
    if (-not $done) { Show-Message "No row is selected.`nClick on a file row first, then click 'Open file folder'." 'Open folder' Warn }
})
$btnPerfBoost.add_Click({
    if (-not (Show-YesNo "Performance boost will switch to the High Performance power plan, turn off Game DVR, and use performance visual effects.`n`nIt is safe and reversible ('Restore performance').`n`nContinue?" 'Performance boost' Question)) { return }
    Start-BackgroundScan -WorkingText 'Applying performance boost - please wait...' -Action { Invoke-PerformanceBoost } -OnDone { Show-Message "Performance boost applied.`nYour PC is set for better performance.`nYou can revert anytime with 'Restore performance'." 'Performance boost' Info }
})
$btnPerfRestore.add_Click({
    if (-not (Show-YesNo "Restore the performance settings back to Windows defaults?`n`nContinue?" 'Restore performance' Question)) { return }
    Start-BackgroundScan -WorkingText 'Restoring performance settings - please wait...' -Action { Invoke-PerformanceRestore } -OnDone { Show-Message "Performance settings restored to Windows defaults." 'Restore performance' Info }
})
$btnSysReport.add_Click({
    Start-BackgroundScan -WorkingText 'Building system report - please wait...' -Action {
        $script:sysReport = ((Get-SystemReport) -join [Environment]::NewLine)
    } -OnDone {
        $out = $null
        $usbBase = Get-LatestBackupSession
        if ($usbBase) { $out = Join-Path $usbBase 'SystemReport.txt'; try { $script:sysReport | Set-Content $out -Encoding UTF8 } catch { $out = $null } }
        if ($out -and (Test-Path $out)) { Show-Message ("System report saved to:`n$out") 'System report' Info; try { Start-Process notepad.exe -ArgumentList "`"$out`"" | Out-Null } catch { } }
        else { Show-Message $script:sysReport 'System report' Info }
    }
})
$btnUtilHardware.add_Click({
    Start-BackgroundScan -WorkingText 'Reading hardware info - please wait...' -Action {
        $script:hardInfo = ((Get-HardwareInfo) -join [Environment]::NewLine)
    } -OnDone { Show-Message $script:hardInfo 'Hardware info' Info }
})
$btnUtilNetwork.add_Click({
    Start-BackgroundScan -WorkingText 'Testing network - please wait...' -Action {
        $script:netDiag = ((Invoke-NetworkDiagnostics) -join [Environment]::NewLine)
        Write-Log $script:netDiag
    } -OnDone { Show-Message $script:netDiag 'Network test' Info }
})
$btnUtilBattery.add_Click({
    Start-BackgroundScan -WorkingText 'Generating battery report - please wait...' -Action {
        $script:hasBattery = $false
        try { $script:hasBattery = [bool](Get-CimInstance Win32_Battery -ErrorAction Stop) } catch { $script:hasBattery = $false }
        $script:batPath = $null
        if ($script:hasBattery) { $script:batPath = New-BatteryReport }
    } -OnDone {
        if ($script:hasBattery -and $script:batPath -and (Test-Path $script:batPath)) { Show-Message "Battery report opened in your browser.`nFile: $script:batPath" 'Battery report' Info }
        elseif (-not $script:hasBattery) { Show-Message 'No battery found - this appears to be a desktop PC, not a laptop, so there is no battery report.' 'Battery report' Warn }
        else { Show-Message 'Battery report could not be generated.' 'Battery report' Warn }
    }
})
$btnUtilApps.add_Click({
    Start-BackgroundScan -WorkingText 'Checking for app updates - please wait...' -Action {
        $script:appUpdates = ((Get-AppUpdates) -join [Environment]::NewLine)
    } -OnDone {
        if ($script:appUpdates) { Show-Message ("Available updates:`n`n" + $script:appUpdates) 'App updates' Info } else { Show-Message 'No app updates found, or winget unavailable.' 'App updates' Info }
    }
})

# Refresh the Easy health card whenever the Easy tab is shown
$script:mainTabs.add_SelectedIndexChanged({
    if ($script:mainTabs.SelectedTab.Text -eq 'Easy') { Update-EasyHealth; Update-EasyItems }
    elseif ($script:mainTabs.SelectedTab.Text -eq 'Health') { Update-HealthCheckTab }
})
$lblVersion.add_Click({
    for ($i = 0; $i -lt $script:mainTabs.TabPages.Count; $i++) {
        if ($script:mainTabs.TabPages[$i].Text -eq 'Version') { $script:mainTabs.SelectedIndex = $i; break }
    }
})
Update-EasyHealth
Update-EasyItems

[void]$form.ShowDialog()
if ($SmokeTest) { Write-Output 'SMOKE OK' }




