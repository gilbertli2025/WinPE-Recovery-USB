# System Optimizer — Comparison & Reference

> A research-backed look at how **System Optimizer** compares to other Windows
> "optimizer / cleaner / debloater / privacy" tools (free and paid), plus a
> full feature and source-structure reference for this program.
>
> Version covered: **v1.8.0** · Updated 2026-08-25

---

## 1. What System Optimizer is

A free, open-source Windows GUI (PowerShell + WinForms) that lets a **normal user**
safely tune performance, harden security, run maintenance, repair the system,
and back up / restore user profiles — with **everything reversible**.

Design philosophy:
- **Safe by default** — no registry cleaner, no RAM "booster", no driver updater.
  (Security experts and Microsoft explicitly warn against those.)
- **Reversible** — backup-first, System Restore points, one-click Undo / Restore ALL.
- **Transparent** — open source, no telemetry, no ads, no paid upsells.
- **Portable & USB-first** — run from any PC, and back up settings/files to your own USB.
- **Beginner-friendly** — plain-language explanations, a health score, and guided workflows.

---

## 2. Feature reference (everything this program can do)

### Top tabs: Easy | Advanced | Utilities | Version

**Easy tab**
- PC Health Score (0–100), C: free space, last-backup age, Windows Defender status, USB status.
- **One-Click Optimize** — backs up settings + files, creates a restore point, then disables safe
  background services, applies recommended security, and runs safe cleanup. Refuses to run without a USB.
- Interactive checklists (folders to back up + services/security/maintenance to apply).
- **Restore my files & settings** — restore from this PC's latest backup.

**Advanced tab (sub-tabs)**
- *Performance & Services* — disable safe services (telemetry, Xbox, Fax…), restore services,
  restore optional-only, verify.
- *Security & Hardening* (10 items) — Defender cloud protection, firewall inbound block,
  daily quick scan, auto-lock, browser hardening (Edge+Chrome), System Restore + weekly points,
  BitLocker on C: (TPM), disable AutoRun, account lockout, block Office macros/WSH.
- *Maintenance & Cleanup* (13 items) — temp files, Windows Update cleanup, SSD trim, flush DNS,
  Game DVR, Storage Sense, Recycle Bin, browser cache, disable startup apps, visual effects,
  Fast Startup, disable tips, High-performance power plan.
- *System Repair* — sfc /scannow, DISM /RestoreHealth, chkdsk C: /f.
- *Backup & Restore* — backup settings to USB, restore from USB, pre-flight check, verify backup.
- *Commands* — a curated command-line reference for advanced users.

**Utilities tab**
- Duplicate finder, Disk analyzer, Large-file finder, Export programs list, Startup Manager,
  Broken shortcuts, Drive health (SMART), Network repair, Health check, Hardware info,
  Network test, Battery report, App updates (winget), Performance boost / Restore,
  System report, **Profile Repair** (v1.8).

**Version tab**
- Version + build date, categorized changelog, USB-safety reminder, "Developed with DeepSeek V4".

### Profile Repair (new in v1.8)
A dedicated utility with a guided safe workflow:
1. **Back up** the old profile (user data, or data + app settings) to your USB via robocopy.
2. **Create a NEW user profile** (opens Settings → Accounts → Other users).
3. **Restore** backed-up files into the new profile (never restores NTUSER.DAT).
4. **Sign in & verify.**
5. **Remove the old profile** (guided instructions).
Also: lists every user profile + health (Status / SID / State / folder), and **Fix temporary
profile** (State 1 → 0).

---

## 3. Source code structure reference

The actual code is the `.ps1` files in this folder (and on GitHub). Layout:

```
System-Optimizer -V1.8/
├─ SystemOptimizer-GUI.ps1     Main UI shell (WinForms): builds every tab,
│                              button, handler; version/changelog; profile-repair button.
├─ SystemOptimizer.wxs         MSI installer definition (WiX) — installs exe + lib + profile-repair.
├─ 1-Click-System-Optimizer.cmd  Launcher (runs the .ps1, bypasses execution policy).
├─ 1-Click-System-Restore.cmd    Easy-restore launcher.
├─ SystemOptimizer-Restore.ps1   Restore helper.
├─ WSO-Trust.cer                Self-signing cert installer (trusts the signed exe).
├─ lib/                          Library modules, dot-sourced by the GUI:
│   ├─ Common.ps1               Paths, logging, JSON/CSV helpers (Read/Write-JsonArray, UTF-8 no BOM).
│   ├─ ServiceCatalog.ps1       Service definitions + safe/optional lists.
│   ├─ SecurityItems.ps1        The 10 security-hardening items.
│   ├─ MaintenanceItems.ps1     The 13 maintenance/cleanup items.
│   ├─ Repair.ps1               sfc / DISM / chkdsk repair logic.
│   ├─ Review.ps1               Security report / review.
│   ├─ BackupRestore.ps1        Settings backup/restore, pre-flight, integrity, latest-session.
│   ├─ FolderBackup.ps1         robocopy folder backup + timestamped per-PC sessions.
│   ├─ Utilities.ps1            Duplicate/disk/large-file/drive-health/network/programs logic.
│   └─ StartupManager.ps1       Startup entries dialog logic.
├─ profile-repair/              Profile Repair utility (ships with the app):
│   ├─ ProfileRepair-Utility.ps1  GUI: profile health list, backup/restore/fix, guided workflow.
│   ├─ ProfileRepair.cmd          Launcher.
│   └─ UserProfile-Repair-Guide.txt  Step-by-step guide.
├─ HELP.md                      User guide (shown in-app via the Help button).
├─ COMPARISON.md                This document.
├─ README.md / INSTALL.txt / STEPS-for-end-users.txt / RESTORE.txt
└─ tests/Lib.Tests.ps1          Pester tests.
```

Notable engineering notes / known gotchas handled:
- JSON backups are UTF-8 **no BOM** and read back as **flat arrays** (nested arrays corrupt restore).
- `.cmd` launchers are **CRLF**, no BOM.
- Registry writes are guarded and require admin; pre-flight check enforces readiness.
- Elevated helper actions use temp script files (avoids `Start-Process -RunAs` argument mangling).
- Scans run synchronously on the UI thread (kept for stability — the window waits briefly).

---

## 4. Pros of System Optimizer

- **Free + open source** — auditable, no hidden telemetry (like BleachBit; unlike CCleaner).
- **Everything reversible** — backup-first, restore points, undo, Restore ALL. Few peers match this.
- **No dangerous "boosters"** — no registry cleaner, RAM booster, or driver updater, which
  experts and Microsoft recommend *against*. A real safety edge over CCleaner / System Mechanic /
  Advanced SystemCare.
- **Portable, USB-first** — run from any PC; back up settings + files to your own USB.
- **Broad all-in-one scope** — services, security, maintenance, repair, utilities, **Profile Repair**
  (rare among these tools).
- **Beginner-friendly** — explanations, guided workflow, health score (like O&O ShutUp10's guided model).

## 5. Cons / limits

- **PowerShell-based** — slower startup; self-signed cert trips SmartScreen (same as native-but-unsigned K-Win).
- **Fewer tweaks** — RegiLattice has ~7,700 tweaks, W11Hammer 430+; yours is a curated set.
  Fine for normal users; not a power-tinkerer's toolbox.
- **No bloatware/app removal** — Win11Debloat, K-Win, Win-Debloat7 remove preinstalled apps; yours doesn't.
- **No scheduled auto-reapply** after Windows updates (O&O ShutUp10 Premium does).
- **Scans briefly freeze the UI** (synchronous) — functional but not as polished as native apps.
- **No antivirus scanning** (by design — that is the antivirus's job).
- **Single developer**, less community battle-testing than CCleaner / BleachBit.

---

## 6. Comparison with other tools

| Tool | Type | Cost | Reversible? | Registry cleaner? | Notes |
|---|---|---|---|---|---|
| **System Optimizer** | All-in-one GUI | Free, open | **Strong** | None | Safe for normal users; USB-first; Profile Repair |
| **Windows built-ins** (Disk Cleanup, Storage Sense, PC Cleaner, Settings) | Built-in | Free | Yes | None | Safe baseline, but limited |
| **Chris Titus WinUtil** | Debloat script/GUI | Free, open | Yes | None | Popular, broad; more advanced/techy |
| **Sophia Script / Win11Debloat** | Debloat script | Free, open | Yes (Win11Debloat) | None | Remove bloatware + telemetry |
| **K-Win** | Optimizer (C#) | Free, open | Yes | None | Clean native GUI; similar safety ethos |
| **RegiLattice** | Tweak toolkit | Free, open | Yes | N/A (reg-tweak engine) | ~7,700 tweaks; for power users/IT |
| **W11Hammer** | Optimizer/hardener | Free, open | Yes (.reg/BCD backup) | None | 430+ changes; aggressive; advanced |
| **O&O ShutUp10++** | Privacy tweaker | Free (+Premium) | Yes | None | Guided privacy; Premium auto-reapplies |
| **WPD** | Privacy dashboard | Free | Yes | None | Powerful but assumes competence |
| **BleachBit** | Cleaner | Free, open | N/A | None by design | Best-in-class cleaner; technical |
| **Wise Disk Cleaner** | Cleaner | Free | Partial | partial | Simple; scheduled cleaning free |
| **CCleaner** | Cleaner/optimizer | Freemium | Partial | **Yes (unsafe)** | Most popular; ads/upsells; PUA-flagged; 2017 breach |
| **System Mechanic / Advanced SystemCare / Glary** | Paid "optimizer" | Paid | Partial | Yes | Aggressive, upsell-heavy; safety concerns |

### Who System Optimizer should be compared with
- **"Free, safe, all-in-one":** Chris Titus **WinUtil**, **K-Win**, **RegiLattice** (power), **O&O ShutUp10++** (guided privacy). These are the real peers.
- **Cleaning baseline:** **BleachBit** (best free) and Windows **Disk Cleanup / Storage Sense**.
- **Cautionary comparison (what *not* to be):** **CCleaner**, **System Mechanic**, **Advanced SystemCare** — they push registry cleaning / RAM boosters that reviewers and Microsoft recommend avoiding.

---

## 7. Suggested positioning

> **"The safe, fully-reversible all-in-one — no registry cleaning, no gimmicks, no ads,
> backups to your own USB, and a built-in Profile Repair."**

That is a genuinely differentiated, defensible niche supported by current market research.

---

## 8. Sources / further reading

- HowToStayPrivate — *CCleaner vs BleachBit: Which PC Cleaner is Actually Safe in 2026?*
- XDA Developers — *BleachBit is better than CCleaner, but you shouldn't be using either of them*
- MakeUseOf — *I tested every major Windows cleaner and this is the only one I trust*
- TECHBETA — *CCleaner vs BleachBit vs Wise Disk Cleaner 2026*
- Digital Citizen — *WPD vs O&O ShutUp10++*
- Neowin — *O&O ShutUp10 3.4.1124*
- Project GitHub pages: Win-Debloat7, K-Win, Win11Debloat, WinUltix, W11Hammer, ReWindows, RegiLattice