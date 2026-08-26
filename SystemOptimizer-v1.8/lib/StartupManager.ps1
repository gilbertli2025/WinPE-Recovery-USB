<#
.SYNOPSIS
  Startup Manager for V1.7. Lists what runs at Windows logon (registry Run/RunOnce
  keys + the Startup folders) and lets the user enable/disable each entry safely
  and reversibly using Windows' StartupApproved mechanism (the same one Task
  Manager uses) - so nothing is deleted, just hidden until re-enabled.
#>

$ErrorActionPreference = 'Stop'

# Map a Run key or Startup folder to its StartupApproved registry path.
function Get-StartupApprovedPath([string]$Location, [string]$Type) {
    if ($Type -eq 'Folder') {
        if ($Location.StartsWith($env:APPDATA)) {
            return 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
        } else {
            return 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
        }
    }
    if ($Location.StartsWith('HKCU')) {
        return 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
    }
    return 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
}

# Enabled/Disabled for an entry by inspecting its StartupApproved blob first byte.
function Get-StartupStatus([string]$Name, [string]$Location, [string]$Type) {
    $apPath = Get-StartupApprovedPath $Location $Type
    $key = Get-Item -Path $apPath -ErrorAction SilentlyContinue
    if (-not $key) { return 'Enabled' }
    $val = $key.GetValue($Name, $null)
    if ($null -eq $val) { return 'Enabled' }
    if ($val -is [byte[]] -and $val.Length -gt 0 -and $val[0] -eq 2) { return 'Disabled' }
    return 'Enabled'
}

# List all startup entries (registry Run keys + Startup folders).
function Get-StartupEntries {
    $results = New-Object System.Collections.Generic.List[object]
    $runKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($key in $runKeys) {
        $v = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if (-not $v) { continue }
        $v.PSObject.Properties | Where-Object { $_.Name -notmatch '^(PSPath|PSParentPath|PSChildName|PSDrive|PSProvider|PSIsContainer)$' } | ForEach-Object {
            $results.Add([pscustomobject]@{
                Name = $_.Name; Command = [string]$_.Value; Location = $key; Type = 'Registry'
                Status = (Get-StartupStatus $_.Name $key 'Registry')
            })
        }
    }
    $folders = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup')
    )
    foreach ($folder in $folders) {
        Get-ChildItem -LiteralPath $folder -Filter *.lnk -ErrorAction SilentlyContinue | ForEach-Object {
            $results.Add([pscustomobject]@{
                Name = $_.Name; Command = $_.FullName; Location = $folder; Type = 'Folder'
                Status = (Get-StartupStatus $_.Name $folder 'Folder')
            })
        }
    }
    return ,$results
}

# Disable a startup entry (StartupApproved blob -> first byte 2). Reversible.
function Disable-StartupEntry([string]$Name, [string]$Location, [string]$Type) {
    $apPath = Get-StartupApprovedPath $Location $Type
    if (-not (Test-Path $apPath)) { New-Item -ItemType Directory -Path $apPath -Force | Out-Null }
    $blob = [byte[]]@(2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    Set-ItemProperty -Path $apPath -Name $Name -Value $blob -Type Binary -ErrorAction Stop | Out-Null
    Write-Log "Disabled startup entry: $Name"
}

# Re-enable a startup entry (StartupApproved blob -> first byte 6).
function Enable-StartupEntry([string]$Name, [string]$Location, [string]$Type) {
    $apPath = Get-StartupApprovedPath $Location $Type
    $blob = [byte[]]@(6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    if (Test-Path $apPath) { Set-ItemProperty -Path $apPath -Name $Name -Value $blob -Type Binary -ErrorAction Stop | Out-Null }
    Write-Log "Enabled startup entry: $Name"
}

$script:LibStartupManagerLoaded = $true