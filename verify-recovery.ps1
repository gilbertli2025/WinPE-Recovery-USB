# verify-recovery.ps1 - mounts boot.wim read-only and checks the boot tools are present.
param([string]$BootWim = 'F:\sources\boot.wim')
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Write-Host 'ERROR: Run as Administrator.' -ForegroundColor Red; exit 1 }
if (-not (Test-Path $BootWim)) { Write-Host "ERROR: $BootWim not found." -ForegroundColor Red; exit 1 }
$dism = "$env:SystemRoot\System32\Dism.exe"
$mount = Join-Path $env:TEMP 'wimverify'
if (Test-Path $mount) { Remove-Item $mount -Recurse -Force }
New-Item -ItemType Directory -Path $mount -Force | Out-Null
Write-Host "Mounting $BootWim (read-only)..."
& $dism /Mount-Image /ImageFile:$BootWim /Index:1 /MountDir:$mount /ReadOnly
Write-Host "Boot tools in WinPE System32:"
foreach ($t in @('bootsect.exe','bcdboot.exe','bcdedit.exe','bootrec.exe')) {
    Write-Host ("  {0}: {1}" -f $t, $(if (Test-Path (Join-Path $mount "Windows\System32\$t")) { 'FOUND' } else { 'not present' }))
}
Write-Host "Recovery menu script:"
Write-Host ("  Recovery\menu.bat: {0}" -f $(if (Test-Path (Join-Path $mount 'Recovery\menu.bat')) { 'FOUND' } else { 'not present' }))
& $dism /Unmount-Image /MountDir:$mount /Discard | Out-Null
Remove-Item $mount -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'Verify done.'