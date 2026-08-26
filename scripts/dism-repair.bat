@echo off
setlocal EnableDelayedExpansion
set "WD="
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist "%%d:\Windows\System32\config\SAM" set "WD=%%d:"
if not defined WD ( echo  [ERROR] Windows drive not found. & pause & exit /b )
cls
echo ============================================================
echo   DISM  /RestoreHealth  (repairs the Windows image)
echo ============================================================
echo   Windows drive: %WD%
echo   This fixes the underlying Windows image that sfc depends on.
echo   It may need an internet connection and can take 10-20 minutes.
echo.
echo   If it fails because Windows Update cannot be reached, run:
echo     dism /Image:%WD%\ /Cleanup-Image /RestoreHealth /Source:wim:%WD%\Windows\Install.wim:1 /LimitAccess
echo.
dism /Image:%WD%\ /Cleanup-Image /RestoreHealth
echo.
echo  Done. Press any key to return to the menu.
pause