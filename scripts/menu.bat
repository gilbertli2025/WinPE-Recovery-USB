@echo off
setlocal EnableDelayedExpansion
:menu
cls
echo ============================================================
echo            WINPE RECOVERY MENU
echo ============================================================
echo   (Your Windows is usually on a drive other than X:)
echo   Use option 7 to see which drives exist.)
echo.
echo   1.  Command Prompt
echo   2.  Reset a local Windows password
echo   3.  System File Checker  (sfc /scannow)
echo   4.  DISM  /RestoreHealth
echo   5.  Boot repair  (bootrec)
echo   6.  Copy files  (recover your data)
echo   7.  List drives
echo   8.  Restart the PC
echo   9.  Shut down
echo.
set /p c=  Type a number and press Enter: 
if "%c%"=="1" goto cmd
if "%c%"=="2" call %~dp0reset-password.bat
if "%c%"=="3" call %~dp0sfc-repair.bat
if "%c%"=="4" call %~dp0dism-repair.bat
if "%c%"=="5" call %~dp0bootrec-repair.bat
if "%c%"=="6" call %~dp0file-copy.bat
if "%c%"=="7" call %~dp0list-drives.bat
if "%c%"=="8" shutdown /r /t 0
if "%c%"=="9" shutdown /s /t 0
goto menu
:cmd
cls
echo ============================================================
echo   COMMAND PROMPT  -  type  exit  to return to the menu
echo ============================================================
cmd
goto menu