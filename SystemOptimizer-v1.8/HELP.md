# System Optimizer — User Guide

This tool has two tabs plus master buttons. Everything you enable can be
reverted with **Restore ALL to defaults**. Every change is logged and backed up.

---

## Tab 1 — Performance & Services

Windows runs many background services you may not need. Disabling them frees
CPU, memory and disk activity. Two lists are provided:

### SAFE services (recommended, pre-checked)
Safe to stop for normal desktop use. Includes telemetry (DiagTrack), Xbox
services, Fax, Remote Registry, Error Reporting, Phone, Maps, Geolocation,
Program Compatibility Assistant, Mixed Reality, etc. Disabling these does not
break everyday work.

### OPTIONAL services (tick only if you do not use the feature)
Each one affects a feature you might use:
- `WSearch` — Windows Search indexing (slower file search if off)
- `SysMain` — Superfetch (fine to disable on SSD)
- `Spooler` — printing (disable only if you never print)
- `TermService` / `SessionEnv` / `UmRdpService` — Remote Desktop
- `WwanSvc` — cellular/4G adapters
- `bthserv` / `BTAGService` / `BthAvctpSvc` — Bluetooth
- `WbioSrvc` — fingerprint/camera logon
- `stisvc` — scanners and cameras
- `SharedAccess` — Internet Connection Sharing
- `WpcMonSvc` — parental controls
- `wlidsvc` — Microsoft account sign-in
- `NvTelemetryContainer` — NVIDIA telemetry
- `WdiServiceHost` / `WdiSystemHost` — diagnostics

### Buttons
- **Disable services (selected)** — disable the services you ticked (backed up first).
- **Restore services** — set them all back to their original startup type.
- **Restore optional only** — re-enable **only** the OPTIONAL services you
  disabled (print, Remote Desktop, Bluetooth, etc.). Handy if you over-selected
  and a feature stopped working — your safe-service tweaks stay untouched.
- **Verify services** — confirm each backed-up service is actually disabled.

> **TIP:** the OPTIONAL list can disable printing, Remote Desktop, Bluetooth,
> search or scanners. If a feature stops working, use **Restore optional only**.

> System-critical and security services are always protected and never touched,
> even if they appear on a list.

---

## Tab 2 — Security & Hardening

Tick the hardening items you want, then **Apply selected**.

### 1. Defender cloud protection (block at first sight)
Enables Microsoft's cloud-delivered protection: MAPS=2 (advanced), send safe
samples, and block level 2. Lets Defender stop new malware quickly using cloud
reputation. **Tradeoff:** sends limited malware/URL info to Microsoft.

### 2. Firewall: block all unsolicited inbound by default
Sets the Windows Firewall default inbound action to **Block** for the Domain,
Private and Public profiles. Outbound and established connections still work.
**Effect:** unsolicited incoming connections are dropped. If you use file/print
sharing or remote management, you may need to add allow rules.

### 3. Daily Defender quick scan at 03:00
Schedules a daily quick scan of the most common infection points.

### 4. Auto-lock screen after 10 minutes idle
Locks your PC automatically after 10 minutes of inactivity, requiring your
password/PIN to get back in.

### 5. Harden Edge + Chrome browsers
Applies policy registry settings to both browsers:
- **Edge:** SmartScreen + SmartScreen for downloads on, block dangerous
  downloads, block third-party cookies, block popups, strict site isolation,
  block WebUSB/WebSerial, no credit-card autofill.
- **Chrome:** Enhanced Safe Browsing, block dangerous downloads, block
  third-party cookies, block popups, strict site isolation, block
  WebUSB/WebSerial, no credit-card autofill.

> Blocking third-party cookies may break some sites that rely on them for login.
> Browsers show "Managed by your organization" while these policies are active —
> this is expected.

### 6. Enable System Restore + weekly restore points
Turns on System Protection for your fixed drives, allows more than one restore
point per day, creates a restore point now, and schedules a weekly restore
point (Sunday 04:00). Restore points undo bad system changes (drivers, updates,
registry). **Important:** restore points are **not** a backup of your personal
files.

### 7. BitLocker on C: (TPM)
Encrypts the system drive so data is unreadable if the PC is stolen. Requires
Windows **Pro/Enterprise** and a **TPM**. Encryption runs in the background.
**Restore does not decrypt the drive** (for safety); decrypt manually with the
recovery key if you want it off.

**BitLocker FAQ:**
- **Already on?** The tool detects it and **skips** — it never touches an
  already-encrypted drive.
- **Turns it on?** Only if item 7 is ticked **and** the PC has a TPM + Windows
  Pro/Enterprise. On Home or no-TPM it just warns and skips (safe).
- **Does it break Windows on a crash?** No — BitLocker is transparent and
  crash-safe. The only real risk is being asked for a **Recovery Key** after a
  BIOS update / TPM reset / hardware change.
- **Safety rule:** the tool will **NOT turn BitLocker on unless a USB/removable
  drive is connected** to store the recovery key off the PC. If no USB is present,
  BitLocker is simply left off and you are told to plug in a USB (or save the key
  to your Microsoft account) and try again. This guarantees you can never be
  locked out without a recoverable key.

### 8. Disable AutoRun on removable drives
Sets `NoDriveTypeAutoRun` so USB sticks and other removable drives can never
auto-start software. Stops a common malware delivery method.

### 9. Account lockout (5 tries / 15 min)
After 5 failed sign-in attempts the account is locked for 15 minutes. Slows
down password-guessing attacks against this PC.

### 10. Block Office macros from the internet + disable Windows Script Host
Stops Word/Excel/PowerPoint/Outlook from running macros inside files downloaded
from the internet, and disables VBS/JS scripts (Windows Script Host). Two very
common malware entry points. **Tradeoff:** legitimately scripted or
macro-enabled files may be blocked.

### Buttons
- **Apply security (selected)** — apply the ticked hardening items (backed up first).
- **Restore security** — revert ALL applied hardening to original settings.
- **Restore checked** — revert ONLY the hardening items you currently have
  ticked. Handy if one setting (e.g. browser hardening or the firewall) caused
  a problem and you want to undo just that.
- **Security review** — print a snapshot report of this PC's security state.

---

## Tab 3 — Maintenance & Cleanup

Items **1–6 are safe and recommended** (pre-ticked); **7–10 are optional** (off by default).

1. **Clear temporary files** — frees space (user + Windows temp).
2. **Windows Update cleanup** — removes old superseded update files
   (`Dism StartComponentCleanup`; can be slow).
3. **Re-trim SSD** — keeps an SSD fast (C:).
4. **Flush DNS cache** — clears stale DNS lookups.
5. **Disable Game DVR** — stops background game recording (frees RAM/GPU).
6. **Enable Storage Sense** — Windows auto-cleans temp + recycle bin.
   > **OFF by default.** When on, Windows may also auto-delete older System
   > Restore points and Downloads as part of its cleanup. Turn it on only if
   > you are OK with that.
7. **Empty Recycle Bin** — frees space but permanently deletes files.
8. **Clear Edge + Chrome cache** — frees space; first page loads slower.
9. **Disable third-party startup apps** (current user) — faster boot; reversible.
10. **Visual effects → best performance** — minor on new PCs, helps older ones.
11. **Enable Fast Startup** — faster boot (note: on laptops, shutdown uses hybrid).
12. **Disable Windows tips & suggestions** — fewer notifications; reversible.
13. **Power plan → High performance** — faster, but battery drains faster on laptops.

### Buttons
- **Run selected cleanup** — run the ticked items.
- **Restore settings** — revert the reversible items (5, 6, 9, 10).
- **Cleanup report** — show current maintenance state.

---

## Tab 4 — System Repair

Repair damaged Windows files or the disk. These can take a long time, so they
are **not** part of **Apply ALL** — run them here only when needed.

- **sfc /scannow** — verifies and repairs system files (5–10 min).
- **DISM /restorehealth** — repairs the Windows image (10–20+ min, needs internet).
- **chkdsk C: /f** — checks the disk for errors — **requires a restart**.

---

## Tab 5 - Backup & Restore

Back up your **user settings** to a USB drive so you can recover them on a new
PC or after a Windows problem.

- **Backup settings to USB** — saves, to a USB (or a folder you choose):
  - Browser bookmarks (Edge + Chrome)
  - Wi-Fi profiles (`netsh wlan export`)
  - User registry settings (`HKCU` as a `.reg` snapshot)
  - This tool's own profile (your checkbox choices)
- **Restore from USB** — brings those back from the backup folder.
- **Pre-flight check** — runs a readiness check before applying changes:
  admin rights, free disk space, a System Restore point, and a USB drive if
  BitLocker is selected.

> **Passwords are NOT backed up.** They are encrypted to your specific PC
> (not portable) and a password file on a USB is a security risk. Use a
> **password manager** (e.g., Bitwarden/1Password) for your passwords, and your
> Microsoft account to sync Windows settings.

## Master buttons (bottom)

- **Apply ALL selected** — applies ticked services, security **AND** cleanup.
- **Restore ALL to defaults** — reverts everything to its original state.
- **Full review / verify** — runs the services verify + security + cleanup check.
- **Help** — opens this guide.

> Restore intentionally does **not** undo two things (for safety):
> - BitLocker — the drive stays encrypted.
> - System Restore protection — stays enabled so you keep your safety net.
>
> Cleanup actions (1–4, 7–8) free space and are **not** reverted by Restore.

> Note: the unified **SystemOptimizer.exe** also has tabs for Maintenance
> (cleanup) and System Repair (sfc / dism / chkdsk). On those tabs Apply ALL
> does **not** include the destructive or repair items; run them on demand.

---

## Where things are stored

- Services backup: `%ProgramData%\WinServiceOpt\services-backup.csv`
- Security backup: `%ProgramData%\WinSecOpt\backup.json`
- Unified log: `%ProgramData%\SystemOptimizer\unified.log`
- Weekly restore point task: `WeeklySystemRestorePoint` (Sun 04:00)

---

## Security best practices (beyond this tool)

This tool keeps the system healthy. These habits protect you further:

1. **Accounts** — use a Standard (non-admin) account for daily work, keep
   admin for installs only. Turn on Windows Hello (PIN / biometrics) and
   two-factor authentication on your Microsoft account and email.
2. **Passwords** — use a password manager so you never reuse passwords.
3. **Software** — download only from official sites. **Never** use cracked
   software or keygens (the #1 source of infection).
4. **Email / web** — be careful clicking links or attachments, even from
   people you know. Keep your browser and Windows updated.
5. **Backups** — restore points are **not** backups. Turn on File History for
   your documents and keep an offline copy (USB/cloud) of important files.
6. **Network** — be careful on public Wi-Fi (use a VPN for sensitive work) and
   lock the screen when you step away.
7. **Updates** — let Windows update automatically, reboot to apply, and
   restart weekly.

---

## How PCs actually get hacked (and how to stop it)

A fully updated PC is rarely hacked "out of the blue" — an attack needs an
entry point. The common ways in:

1. **Phishing / stolen password or session** — a fake email or site tricks you
   into typing your Microsoft password or approving a login. **Stop it:** turn
   on two-factor authentication (MFA) and be suspicious of login prompts you
   didn't start.
2. **Malicious attachments / macros (Office)** — a Word/Excel/PDF runs a macro
   that downloads a RAT or stealer. **Stop it:** don't open unexpected
   attachments; the macro-blocking hardening in this tool helps.
3. **Unpatched software** — an outdated browser/Office/Windows lets a bad
   webpage exploit a known flaw. **Stop it:** keep everything updated.
4. **Session/cookie theft** — a stolen browser cookie lets someone into sites
   you're logged into, even with MFA. **Stop it:** password manager, avoid
   shady extensions, caution on public Wi-Fi.
5. **Malicious apps / "Sign in with Microsoft"** — granting login to a fake app
   hands over access. **Stop it:** only authorize apps you trust.
6. **Physical access** — someone using an unlocked PC. **Stop it:** auto-lock
   and BitLocker (both in this tool).

> **Bottom line:** the entry point is almost always a tricked click, a stolen
> password/session, or an unpatched bug. Account hygiene (MFA, standard
> account, cautious clicking) closes the biggest gaps.

---

## How to check for problems (detection tools)

- **Built into Windows (no install needed):**
  - **Windows Security (Defender)** — run a full scan; check "Protection
    history" and "Virus & threat protection".
  - **Offline scan** — Windows Security → Virus & threat protection → Scan
    options → Microsoft Defender Offline scan (reboots and scans deeply).
  - Check running programs: `Ctrl+Shift+Esc` → Startup + Details tabs.
- **Free, well-known scanners (run a second opinion):**
  - **Malwarebytes Free** — very effective second-opinion scanner.
  - **Microsoft Safety Scanner (MSERT)** — on-demand, single-use.
  - **HitmanPro / Kaspersky Virus Removal Tool** — quick second opinions.
- **If you have a third-party antivirus (e.g., Bitdefender, Norton, Kaspersky):**
  open that antivirus's own app and run a **full scan** from there. This app
  (System Optimizer) does **not** run antivirus scans — it only tunes, hardens
  and cleans up. Your antivirus does the scanning, and when another antivirus
  is the primary one, Windows Defender hands over to it automatically.
- **Signs something may be wrong:**
  - PC suddenly very slow; high CPU/disk with nothing open
  - new toolbars/extensions, changed homepage, random pop-ups
  - browser redirects, unknown processes, unexpected accounts/logins
  - files encrypted with `.locked` / `.crypt` (ransomware)

> **If you suspect an infection:** disconnect from the internet, run an
> offline scan, change your important passwords (from another device), and
> check recent sign-in activity on your Microsoft account.

---

## Using AI to stay safe online

AI assistants (Copilot, Claude, ChatGPT) can help spot threats — as a **helper**,
not a replacement for antivirus, updates, MFA and backups.

- **Good uses:** ask AI to review a suspicious email or link for scams, explain a
  Windows/antivirus warning, or guide you through recovery after an incident.
- **Do NOT:** paste passwords or card numbers into AI, give an AI agent admin
  access, or let it read your email/browser by default (it can be tricked).
- Keep core defenses on and use AI to think **with** you, not to hold your keys.

---

## Notes for a fresh Windows 11 PC

- **Smart App Control** (Win11) can block this self-signed tool. If the exe is
  blocked, turn it off: Windows Security → App & browser control → Smart App
  Control → Off, then reboot. (It cannot be re-enabled without resetting
  Windows.)
- The **1-Click** script installs `WSO-Trust.cer` so the signed exe is trusted.
- Reboot after applying for the full effect.
