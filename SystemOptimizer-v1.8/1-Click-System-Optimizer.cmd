@echo off
setlocal
title System Optimizer Launcher
cd /d "%~dp0"

rem --- Elevate if not already admin ---
net session >nul 2>&1
if not %errorlevel%==0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

rem --- Install the signing certificate once (so signed exes are trusted) ---
if exist "%~dp0WSO-Trust.cer" (
    certutil -addstore -f Root "%~dp0WSO-Trust.cer" >nul 2>&1
)

rem --- Check if running from a USB (removable) drive ---
set DTYPE=
for /f %%a in ('powershell -NoProfile -Command "$d = (Get-Location).Path.Substring(0,2); [System.IO.DriveInfo]::new($d).DriveType"') do set DTYPE=%%a
if /I "%DTYPE%"=="Removable" (
    echo.
    echo Running from a USB drive - good.
    echo.
    echo The program will back up your User Settings to this USB drive
    echo first, before running the optimizer.
    echo.
    echo IMPORTANT: Always run this program from the USB drive, and keep
    echo this USB drive safe - it holds your settings backup and recovery key.
    echo.
    echo Press any key to start...
    pause >nul
) else (
    echo.
    echo *** WARNING: You are NOT running from a USB drive. ***
    echo This program must be run from a USB drive so it can back up
    echo your User Settings to the USB drive first, before running.
    echo.
    echo TIP: If you are running from inside a .zip file, FIRST EXTRACT
    echo the zip onto this USB drive, then run this file again from the
    echo extracted folder on the USB.
    echo.
    echo Press any key to continue anyway, or close this window.
    echo.
    pause >nul
)

rem --- Start the app (PowerShell source, Bypass) ---
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0SystemOptimizer-GUI.ps1"
exit /b 0
