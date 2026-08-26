@echo off
rem Extract the embedded bootrec-repair.bat from boot.wim for inspection (run as Administrator)
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator rights...
  powershell -Command "Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0diag-recovery.ps1\"' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0diag-recovery.ps1"
echo.
echo ---- file-copy.bat inside the image (first lines) ----
if exist "%~dp0diag-file-copy.bat" (
  type "%~dp0diag-file-copy.bat"
) else (
  echo  (file-copy.bat not extracted)
)
echo.
pause
