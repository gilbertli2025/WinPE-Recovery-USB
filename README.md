# Windows PC Swiss Knife USB

A **single bootable USB** that turns any Windows PC into something you can rescue,
repair, and maintain. Two tools on one stick:

```
┌─────────────────────────────────────────────────────────────┐
│  WINPE-RECOVERY (boot this when Windows won't start)        │
│    - custom menu: command prompt, password reset, sfc,      │
│      DISM, boot repair, file recovery, list drives          │
├─────────────────────────────────────────────────────────────┤
│  SYSTEM OPTIMIZER v1.8 (run when Windows works)             │
│    - performance, security hardening, maintenance, repair,  │
│      backup, profile repair                                 │
└─────────────────────────────────────────────────────────────┘
```

This repository contains everything needed to **build that USB yourself** from the
Windows ADK, plus the full source of the recovery scripts and the System Optimizer app.

---

## The two tools

### 1) WinPE Recovery (bootable)
A custom **Windows PE** recovery environment you boot from the USB. It shows a menu with:

| # | Option | What it does |
|---|--------|--------------|
| 1 | Command Prompt | Full command prompt in the recovery environment |
| 2 | Reset Windows password | Ease-of-Access trick to set a new local password |
| 3 | System File Checker | `sfc /scannow` on the offline Windows |
| 4 | DISM /RestoreHealth | Repairs the Windows image (needs internet) |
| 5 | Boot Repair | `bcdboot` + `bootsect` (fixes boot/MBR) |
| 6 | Copy Files | Guided recovery of Documents/Desktop/Downloads/Pictures/Music/Videos |
| 7 | List drives | Shows which drives exist |
| 8 | Restart | Reboot the PC |
| 9 | Shut down | Power off |

### 2) System Optimizer v1.8
Run it when Windows boots normally (double-click `1-Click-System-Optimizer.cmd`
in the `SystemOptimizer-v1.8` folder). It tunes performance, hardens security,
runs maintenance, repairs the system, backs up settings/files, and includes the
Profile Repair utility.

---

## What you need to BUILD the USB (one-time)

1. A spare **USB drive** (8 GB+). It will be **formatted** — all data on it is erased.
2. The **Windows ADK** + **Windows PE add-on** from Microsoft:
   - https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
   - Install both. (Large download, ~few GB.)

## Build steps

1. Insert the spare USB.
2. Run **`build.cmd`** as Administrator:
   - It finds the ADK, builds the WinPE image, injects the recovery scripts,
     adds System Optimizer v1.8, and writes the bootable drive.
3. Done — the USB is now bootable.

> For quick script tweaks later, `rebuild.cmd` does a full clean rebuild.

## How to use the USB

- **Windows won't boot** → boot the USB (F12 / ESC / Del), use the recovery menu.
- **Windows works** → run `SystemOptimizer-v1.8\1-Click-System-Optimizer.cmd`.

---

## Source structure

```
WinPE-Recovery/
├─ README.md                 This file.
├─ build-winpe.ps1           Full build automation (ADK -> bootable USB).
├─ build.cmd                 Double-click launcher for build-winpe.ps1 (self-elevates).
├─ rebuild.cmd               Full clean rebuild (erase + build + verify).
├─ update-recovery.ps1 / .cmd  In-place update of boot.wim (scripts).
├─ verify-recovery.ps1 / .cmd  Mount boot.wim and confirm the tools are present.
├─ diag-recovery.ps1 / .cmd    Extract embedded scripts for inspection.
├─ scripts/                  The recovery scripts injected into WinPE:
│   ├─ startnet.cmd            Runs at boot -> launches the menu.
│   ├─ menu.bat                The main recovery menu.
│   ├─ find-windrive.bat       Detects the Windows drive (letter varies in WinPE).
│   ├─ reset-password.bat      Ease-of-Access password reset.
│   ├─ sfc-repair.bat          sfc /scannow on the offline Windows.
│   ├─ dism-repair.bat         DISM /RestoreHealth.
│   ├─ bootrec-repair.bat      Boot repair via bcdboot + bootsect.
│   ├─ file-copy.bat           Guided data recovery (auto-detect drive + profile).
│   └─ list-drives.bat         Lists drives.
└─ SystemOptimizer-v1.8/     The System Optimizer app (runs when Windows works).
    ├─ 1-Click-System-Optimizer.cmd   Launch this.
    ├─ SystemOptimizer.exe / .msi / .ps1
    ├─ lib/                    Library modules.
    ├─ profile-repair/         Profile Repair utility.
    └─ HELP.md, COMPARISON.md
```

---

## Notes / lessons learned (for builders)

- **`bootrec` is NOT in WinPE** — boot repair must use `bcdboot` + `bootsect`
  (these ARE in base WinPE; do NOT try to copy them in, it fails with access denied).
- The recovery scripts and menu live **inside `boot.wim`** (X:\Recovery at boot),
  not as loose files on the USB.
- Batch scripts must be **CRLF** line endings.
- `build.cmd` self-elevates (UAC). The full build takes ~15-30 minutes on a
  USB 2.0 drive because it formats and writes the image.
- The in-place update (`update.cmd`) can be unreliable for script changes —
  if a script change doesn't appear, do a full `rebuild.cmd`.

## License / usage

Free to use and modify. Provided as-is, without warranty. Always keep your own
backups; this tool is a helper, not a guarantee.