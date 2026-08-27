@echo off
setlocal EnableDelayedExpansion
:menu
cls
echo ============================================================
echo            WINPE RECOVERY MENU
echo ============================================================
echo   (Backup files will show your drives and guide you.)
echo.
echo   1.  Command Prompt
echo   2.  Reset a local Windows password
echo   3.  System File Checker  (sfc /scannow)
echo   4.  DISM  /RestoreHealth
echo   5.  Boot repair
echo   6.  Backup your files  (Documents, Pictures, etc.)
echo   7.  Restart the PC
echo   8.  Shut down
echo.
set /p c=  Type a number and press Enter: 
if "%c%"=="1" goto cmd
if "%c%"=="2" call %~dp0reset-password.bat
if "%c%"=="3" call %~dp0sfc-repair.bat
if "%c%"=="4" call %~dp0dism-repair.bat
if "%c%"=="5" call %~dp0bootrec-repair.bat
if "%c%"=="6" call %~dp0file-copy.bat
if "%c%"=="7" wpeutil reboot >nul 2>&1 & exit /b
if "%c%"=="8" wpeutil shutdown >nul 2>&1 & exit /b
goto menu
:cmd
cls
echo ============================================================
echo   COMMAND PROMPT  -  type  exit  to return to the menu
echo ============================================================
cmd
goto menu