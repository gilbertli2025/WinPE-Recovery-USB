@echo off
setlocal EnableDelayedExpansion
rem ============================================================
rem   COPY FILES  -  guided data backup
rem   Detects the Windows drive and the plugged-in USB drive,
rem   then copies your Documents, Desktop, Downloads, Pictures,
rem   Music and Videos to:
rem       <USB>:\RecoveredData\<ComputerName>\<UserName>\<timestamp>\
rem ============================================================

rem ---- 1. Detect the Windows (OS) drive ----
set "WD="
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist "%%d:\Windows\System32\config\SAM" set "WD=%%d:"
if not defined WD ( echo  [ERROR] Could not find the Windows drive. & pause & exit /b )

rem ---- 2. Find the first real user profile ----
set "PROFILE="
for /d %%U in ("%WD%\Users\*") do (
  set "NAME=%%~nxU"
  if /i not "!NAME!"=="Public" if /i not "!NAME!"=="Default" if /i not "!NAME!"=="Default User" if /i not "!NAME!"=="All Users" (
    if not defined PROFILE set "PROFILE=%%U"
  )
)
if not defined PROFILE ( echo  [ERROR] No user profile found under %WD%\Users & pause & exit /b )
set "UNAME="
for %%U in ("%PROFILE%") do set "UNAME=%%~nxU"

rem ---- 3. Detect the USB (removable) drive via diskpart ----
echo list volume > "%TEMP%\dp.txt"
diskpart /s "%TEMP%\dp.txt" > "%TEMP%\dp.out" 2>nul
set "USB="
for /f "tokens=3" %%L in ('findstr /i "Removable" "%TEMP%\dp.out" 2^>nul') do (
  if not defined USB if exist "%%L:\" set "USB=%%L"
)
if not defined USB (
  echo  Could not auto-detect the USB drive.
  echo  Please type the drive letter to save to ^(e.g. F^):
  set /p USB=  Drive letter: 
)
if not defined USB (
  echo  No destination drive. Run again and try again.
  pause & exit /b
)

rem ---- 4. Build a timestamp ----
set "TS=%date:/=-%"
set "TS=%TS%_%time:~0,5%"
set "TS=%TS: =%"
set "TS=%TS::=-%"

rem ---- 5. Build destination folder ----
set "DEST=%USB%:\RecoveredData\%COMPUTERNAME%\%UNAME%\%TS%"
if not exist "%DEST%" mkdir "%DEST%"

cls
echo ============================================================
echo   COPY FILES  -  backup your data
echo ============================================================
echo   Windows drive : %WD%
echo   User profile  : %UNAME%
echo   Saving to     : %DEST%
echo.
echo   Copying your Documents, Desktop, Downloads, Pictures,
echo   Music and Videos...  (this can take a while)
echo.
for %%F in (Documents Desktop Downloads Pictures Music Videos) do (
  if exist "%PROFILE%\%%F" (
    echo   - Copying %%F ...
    robocopy "%PROFILE%\%%F" "%DEST%\%%F" /E /R:1 /W:1 /XJ
  )
)
echo.
echo  Done. Your files were backed up to:
echo    %DEST%
echo  Keep this USB safe.
echo.
pause