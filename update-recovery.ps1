# ============================================================================
#  update-recovery.ps1  -  Updates an EXISTING WinPE recovery USB in place
#  (adds the boot-repair tools and refreshes the recovery scripts inside
#   boot.wim). No re-format needed - it only updates boot.wim on the drive.
#  Run as Administrator:  powershell -ExecutionPolicy Bypass -File update-recovery.ps1 [-BootWim F:\sources\boot.wim]
# ============================================================================
param([string]$BootWim = '')

$ErrorActionPreference = 'Stop'
$root     = Split-Path $MyInvocation.MyCommand.Path
$scripts  = Join-Path $root 'scripts'
$mount    = Join-Path $root ("update-mount-" + (Get-Date -Format 'HHmmss'))

function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) { Write-Host 'ERROR: Run this as Administrator.' -ForegroundColor Red; exit 1 }
if (-not $BootWim) { $BootWim = Read-Host 'Path to boot.wim (default F:\sources\boot.wim)'; if (-not $BootWim) { $BootWim = 'F:\sources\boot.wim' } }
if (-not (Test-Path $BootWim)) { Write-Host "ERROR: boot.wim not found: $BootWim" -ForegroundColor Red; exit 1 }

$dism = "$env:SystemRoot\System32\Dism.exe"
New-Item -ItemType Directory -Path $mount -Force | Out-Null

Write-Host "Mounting $BootWim ..." -ForegroundColor Cyan
& $dism /Mount-Image /ImageFile:$BootWim /Index:1 /MountDir:$mount
if (-not (Test-Path (Join-Path $mount 'Windows\System32'))) { Write-Host 'ERROR: mount failed.' -ForegroundColor Red; & $dism /Unmount-Image /MountDir:$mount /Discard; exit 1 }

New-Item -ItemType Directory -Path (Join-Path $mount 'Recovery') -Force | Out-Null
Copy-Item "$scripts\*" (Join-Path $mount 'Recovery') -Force
Copy-Item (Join-Path $mount 'Recovery\startnet.cmd') (Join-Path $mount 'Windows\System32\startnet.cmd') -Force

Write-Host 'Scripts injected. Committing (can take a few minutes)...' -ForegroundColor Cyan
& $dism /Unmount-Image /MountDir:$mount /Commit
cmd /c rmdir /s /q "$mount" 2>&1 | Out-Null
Write-Host ''
Write-Host 'DONE. The recovery USB now has a working Boot Repair (bootsect/bcdboot).' -ForegroundColor Green