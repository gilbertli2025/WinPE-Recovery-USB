@echo off
rem WinPE Recovery USB - build launcher (run as Administrator)
rem This FORMATS the target USB drive (F:) and writes the bootable WinPE recovery image.
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator rights...
  powershell -Command "Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0build-winpe.ps1\" -DriveLetter F -Force' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-winpe.ps1" -DriveLetter F -Force
echo.
echo Done. Press any key to close.
pause > nul