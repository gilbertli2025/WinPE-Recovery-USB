@echo off
rem Verify the boot tools are inside the recovery boot.wim (run as Administrator)
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator rights...
  powershell -Command "Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0verify-recovery.ps1\"' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify-recovery.ps1"
echo.
echo Press any key to close.
pause > nul