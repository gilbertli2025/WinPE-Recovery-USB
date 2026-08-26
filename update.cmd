@echo off
rem Update the existing WinPE recovery USB (F:) in place - adds boot-repair
rem tools and refreshes the recovery scripts inside boot.wim. No re-format.
rem Make sure the F: USB is connected, then run this as Administrator.
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator rights...
  powershell -Command "Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0update-recovery.ps1\" -BootWim F:\sources\boot.wim' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-recovery.ps1" -BootWim "F:\sources\boot.wim"
echo.
echo Done. Press any key to close.
pause > nul