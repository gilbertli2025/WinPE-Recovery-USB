@echo off
setlocal
title System Optimizer Restore
cd /d "%~dp0"

rem --- Elevate if not already admin ---
net session >nul 2>&1
if not %errorlevel%==0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

rem --- Check if running from a USB (removable) drive ---
set DTYPE=
for /f %%a in ('powershell -NoProfile -Command "$d = (Get-Location).Path.Substring(0,2); [System.IO.DriveInfo]::new($d).DriveType"') do set DTYPE=%%a
if /I not "%DTYPE%"=="Removable" (
    echo.
    echo *** WARNING: Run this from the USB drive so the program can find
    echo your backup folder (SystemOptimizer-Backup on the USB).
    echo.
)

echo.
echo Restoring your user settings from the USB backup...
echo  - browser bookmarks
echo  - Wi-Fi profiles
echo  - user settings
echo.
echo A pop-up will tell you when it is done.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0SystemOptimizer-Restore.ps1"
echo.
echo Press any key to close this window.
pause >nul
exit /b 0