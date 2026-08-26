<#
.SYNOPSIS
  System Repair tools (sfc, dism, chkdsk). No backup because there is no
  reversible registry change to undo - these either repair or do nothing.
#>

$ErrorActionPreference = 'Stop'

function Invoke-SfcScan {
    Write-Log "Running sfc /scannow - verifies and repairs system files (may take several minutes)..."
    $out = & sfc.exe /scannow 2>&1
    (($out | Out-String).Trim() -split "`r?`n" | Where-Object { $_ }) | ForEach-Object { Write-Log ("    " + $_) }
    Write-Log "sfc /scannow done."
}

function Invoke-DismRepair {
    Write-Log "Running DISM /restorehealth - repairs the Windows image (can take 10-20+ min, may need internet)..."
    $out = & dism.exe /Online /Cleanup-Image /RestoreHealth 2>&1
    (($out | Out-String).Trim() -split "`r?`n" | Where-Object { $_ }) | ForEach-Object { Write-Log ("    " + $_) }
    Write-Log "DISM /restorehealth done."
}

function Invoke-ChkdskScheduled {
    Write-Log "Scheduling disk check (chkdsk C: /f) - it will run at the next restart..."
    # Pipes 'Y' so chkdsk will schedule on next reboot rather than asking the
    # user interactively. For non-interactive use / spotfix, but we keep the
    # user's documented behaviour here.
    $out = 'Y' | chkdsk.exe C: /f 2>&1
    (($out | Out-String).Trim() -split "`r?`n" | Where-Object { $_ }) | ForEach-Object { Write-Log ("    " + $_) }
    Write-Log "chkdsk scheduled. Restart the PC to let it run."
}

function Invoke-RepairItem {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    switch ($Id) {
        'sfc'    { Invoke-SfcScan }
        'dism'   { Invoke-DismRepair }
        'chkdsk' { Invoke-ChkdskScheduled }
        default  { Write-Log "WARN: unknown repair id '$Id'" }
    }
}

$script:LibRepairLoaded = $true
