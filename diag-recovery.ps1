# diag-recovery.ps1 - mounts boot.wim read-only and extracts the embedded recovery scripts for inspection.
param([string]$BootWim = 'F:\sources\boot.wim')
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Write-Host 'ERROR: Run as Administrator.' -ForegroundColor Red; exit 1 }
if (-not (Test-Path $BootWim)) { Write-Host "ERROR: $BootWim not found." -ForegroundColor Red; exit 1 }
$dism = "$env:SystemRoot\System32\Dism.exe"
$mount = Join-Path $env:TEMP 'wimdiag'
$root  = Split-Path $MyInvocation.MyCommand.Path
if (Test-Path $mount) { Remove-Item $mount -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $mount -Force | Out-Null
& $dism /Mount-Image /ImageFile:$BootWim /Index:1 /MountDir:$mount /ReadOnly
Write-Host "Recovery folder contains:"
Get-ChildItem (Join-Path $mount 'Recovery') -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
foreach ($n in @('bootrec-repair.bat','file-copy.bat')) {
    $src = Join-Path $mount "Recovery\$n"
    $dst = Join-Path $root "diag-$n"
    if (Test-Path $src) { Copy-Item $src $dst -Force; Write-Host "EXTRACTED $n" } else { Write-Host "$n NOT in image" }
}
& $dism /Unmount-Image /MountDir:$mount /Discard | Out-Null
Remove-Item $mount -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'Done.'