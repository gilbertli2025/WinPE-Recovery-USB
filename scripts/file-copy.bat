@echo off
setlocal EnableDelayedExpansion
rem ============================================================
rem   COPY FILES  -  guided data recovery
rem   Detects your Windows drive + user profile, then copies your
rem   Documents, Desktop, Downloads, Pictures, Music and Videos
rem   to the drive you choose.
rem ============================================================
set "WD="
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist "%%d:\Windows\System32\config\SAM" set "WD=%%d:"
if not defined WD ( echo  [ERROR] Could not find the Windows drive. & pause & exit /b )

cls
echo ============================================================
echo   COPY FILES  -  recover your data
echo ============================================================
echo   Windows drive: %WD%
echo.
rem Find the first real user profile (skip system folders)
set "PROFILE="
for /d %%U in ("%WD%\Users\*") do (
  set "NAME=%%~nxU"
  if /i not "!NAME!"=="Public" if /i not "!NAME!"=="Default" if /i not "!NAME!"=="Default User" if /i not "!NAME!"=="All Users" (
    if not defined PROFILE set "PROFILE=%%U"
  )
)
if not defined PROFILE ( echo  [ERROR] No user profile found under %WD%\Users & pause & exit /b )
echo   User profile: %PROFILE%
echo.
echo   Drives on this PC:
echo     X:  is this recovery system  (do not use)
echo     %WD%  is your Windows drive
echo     The rest are possible places to save to.
echo.
set /p DST=  Type the drive letter to SAVE your files to (e.g. F): 
if "%DST%"=="" ( echo  No destination. & pause & exit /b )
set "DEST=%DST%:\RecoveredData"
if not exist "%DEST%" mkdir "%DEST%"
echo.
echo  Copying your data folders to: %DEST%
echo  This can take a while - please wait...
echo.
for %%F in (Documents Desktop Downloads Pictures Music Videos) do (
  if exist "%PROFILE%\%%F" (
    echo   - Copying %%F ...
    robocopy "%PROFILE%\%%F" "%DEST%\%%F" /E /R:1 /W:1 /XJ
  )
)
echo.
echo  Done. Your files are now in: %DEST%
echo  Keep this USB safe.
echo.
pause