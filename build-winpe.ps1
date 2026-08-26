# ============================================================================
#  build-winpe.ps1  -  Builds a bootable WinPE recovery USB with a custom menu.
#  Requires:  Windows ADK + Windows PE add-on for ADK (installed separately),
#             and a USB drive to write to (it will be FORMATTED - all data lost).
#
#  Run as Administrator:   powershell -ExecutionPolicy Bypass -File build-winpe.ps1
# ============================================================================
param([string]$DriveLetter = '', [switch]$Force)   # e.g. -DriveLetter F -Force
$ErrorActionPreference = 'Stop'
$root   = Split-Path $MyInvocation.MyCommand.Path
$scripts = Join-Path $root 'scripts'
$build  = Join-Path $root 'build'
if (-not (Test-Path $build)) { New-Item -ItemType Directory -Path $build -Force | Out-Null }
Start-Transcript (Join-Path $root 'build.log') -Force | Out-Null

function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Find-AdkTool($name, [string]$name2 = '') {
    $base = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit'
    $hit = Get-ChildItem $base -Recurse -Filter $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $hit -and $name2) { $hit = Get-ChildItem $base -Recurse -Filter $name2 -ErrorAction SilentlyContinue | Select-Object -First 1 }
    return $hit.FullName
}

Write-Host '=== WinPE Recovery USB builder ===' -ForegroundColor Cyan
if (-not (Test-Admin)) { Write-Host 'ERROR: Run this as Administrator.' -ForegroundColor Red; exit 1 }

# 1) Locate ADK tools
$copype = Find-AdkTool 'copype.cmd'
$makemedia = Find-AdkTool 'MakeWinPEMedia.cmd' 'MakeWinPEMedia.ps1'
$dism = "$env:SystemRoot\System32\Dism.exe"

if (-not $copype -or -not $makemedia) {
    Write-Host 'ERROR: Windows ADK (with the WinPE add-on) is not installed.' -ForegroundColor Red
    Write-Host 'Download and install BOTH of these from Microsoft, then re-run:'
    Write-Host '  1) Windows Assessment and Deployment Kit (ADK)'
    Write-Host '  2) Windows PE add-on for the ADK'
    Write-Host '   https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install'
    exit 1
}
Write-Host "ADK tools found: `n  copype: $copype`n  MakeWinPEMedia: $makemedia" -ForegroundColor Green

# 2) Pick the USB drive
if (-not $DriveLetter) {
    $rem = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2")
    if ($rem.Count -eq 0) { Write-Host 'ERROR: No removable (USB) drive found. Insert the target USB and re-run.' -ForegroundColor Red; exit 1 }
    Write-Host 'Removable drives found:'
    $i = 1
    foreach ($d in $rem) { Write-Host ("  {0}) {1}:  {2}  {3} GB" -f $i, $d.DeviceID.TrimEnd(':'), $d.VolumeName, [math]::Round($d.Size/1GB,1)) }
    $n = Read-Host '  Choose the drive number to make bootable (IT WILL BE FORMATTED): '
    $DriveLetter = $rem[([int]$n - 1)].DeviceID.TrimEnd(':')
}
$dl = $DriveLetter -replace ':',''
if (-not (Test-Path "$dl`:")) { Write-Host "ERROR: Drive $dl does not exist." -ForegroundColor Red; exit 1 }
Write-Host "Target USB drive: $dl :  (will be formatted)" -ForegroundColor Yellow
if (-not $Force) {
    $go = Read-Host 'Type YES to format and build this USB: '
    if ($go -ne 'YES') { Write-Host 'Aborted.'; Stop-Transcript | Out-Null; exit 0 }
}

# 3) Create the WinPE working image
# Clean any leftover dirty mount / build dir from a previous interrupted build.
$dism = "$env:SystemRoot\System32\Dism.exe"
$oldMount = Join-Path $build 'mount'
if (Test-Path (Join-Path $oldMount 'Windows')) {
    Write-Host 'Unmounting leftover mount from a previous run...' -ForegroundColor Yellow
    & $dism /Unmount-Image /MountDir:$oldMount /Discard 2>&1 | Out-Null
    Start-Sleep -Seconds 2
}
if (Test-Path $build) { cmd /c rmdir /s /q "$build" 2>&1 | Out-Null; Start-Sleep -Seconds 2 }
$setenv = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat'
Write-Host 'Creating WinPE media (copype)...' -ForegroundColor Cyan
if (Test-Path $setenv) {
    # DandISetEnv.bat sets the Deployment Tools environment (WinPERoot, OSCDImgRoot, DISMRoot, PATH).
    & cmd.exe /c "call `"$setenv`" >nul && call `"$copype`" amd64 `"$build`""
} else {
    $env:WinPERoot   = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment'
    $env:OSCDImgRoot = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg'
    $env:DISMRoot    = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\DISM'
    & $copype amd64 $build
}
if ($LASTEXITCODE -ne 0) { Write-Host 'ERROR: copype failed.' -ForegroundColor Red; exit 1 }

# 4) Mount the boot.wim and inject our recovery scripts + menu
$wim   = Join-Path $build 'media\sources\boot.wim'
$mount = Join-Path $build 'mount'
if (-not (Test-Path $mount)) { New-Item -ItemType Directory -Path $mount -Force | Out-Null }
Write-Host 'Mounting boot.wim...' -ForegroundColor Cyan
& $dism /Mount-Image /ImageFile:$wim /Index:1 /MountDir:$mount
if (-not (Test-Path (Join-Path $mount 'Windows\System32'))) { Write-Host 'ERROR: mount failed.' -ForegroundColor Red; & $dism /Unmount-Image /MountDir:$mount /Discard; Stop-Transcript | Out-Null; exit 1 }

New-Item -ItemType Directory -Path (Join-Path $mount 'Recovery') -Force | Out-Null
Copy-Item "$scripts\*" (Join-Path $mount 'Recovery') -Force
Copy-Item (Join-Path $mount 'Recovery\startnet.cmd') (Join-Path $mount 'Windows\System32\startnet.cmd') -Force
Write-Host 'Scripts injected. Committing image (this can take a few minutes)...' -ForegroundColor Cyan
& $dism /Unmount-Image /MountDir:$mount /Commit
if ($LASTEXITCODE -ne 0) { Write-Host 'ERROR: commit failed.' -ForegroundColor Red; Stop-Transcript | Out-Null; exit 1 }

# 5) Write to the USB
Write-Host "Writing bootable WinPE to drive $dl : ..." -ForegroundColor Cyan
& $makemedia /UFD /F $build "${dl}:"
if ($LASTEXITCODE -ne 0) { Write-Host 'ERROR: MakeWinPEMedia failed.' -ForegroundColor Red; Stop-Transcript | Out-Null; exit 1 }

Write-Host ''
Write-Host 'SUCCESS! The USB is now a bootable WinPE recovery drive.' -ForegroundColor Green
Write-Host 'Boot it by selecting the USB from the boot menu (F12 / ESC / Del).'
Write-Host 'The custom menu will appear with options for command prompt,'
Write-Host 'password reset, sfc, DISM, boot repair, and file copy.'