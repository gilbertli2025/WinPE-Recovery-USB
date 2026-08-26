@echo off
rem FULL CLEAN REBUILD of the WinPE recovery USB on F: (formats the drive).
rem 1) Erases and rebuilds boot.wim with the correct scripts + boot tools.
rem 2) Then extracts the boot-repair script from the NEW image to verify it uses
rem    bcdboot/bootsect (not bootrec).
rem Run as Administrator. The F: drive will be FORMATTED.
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator rights...
  powershell -Command "Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0rebuild.cmd\"' -Verb RunAs"
  exit /b
)
cd /d "%~dp0"
echo.
echo ================== STEP 1: FULL BUILD ==================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-winpe.ps1" -DriveLetter F -Force
echo.
echo ================== STEP 2: VERIFY NEW IMAGE ==================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0diag-recovery.ps1"
echo.
echo ---- boot-repair script inside the NEW image ----
if exist "%~dp0diag-bootrec.txt" (
  type "%~dp0diag-bootrec.txt"
) else (
  echo  (verification file not created)
)
echo.
echo If the lines above show  bcdboot  and  bootsect  - the fix is GOOD.
echo If they show  bootrec  - something is still wrong.
echo.
pause