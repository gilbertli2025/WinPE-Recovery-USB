@echo off
setlocal EnableDelayedExpansion
set "WD="
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist "%%d:\Windows\System32\config\SAM" set "WD=%%d:"
if not defined WD ( echo  [ERROR] Windows drive not found. & pause & exit /b )
cls
echo ============================================================
echo   SYSTEM FILE CHECKER  (sfc /scannow)
echo ============================================================
echo   Windows drive: %WD%
echo   This checks and repairs Windows system files.
echo   It can take several minutes. Please wait...
echo.
sfc /scannow /offbootdir=%WD%\ /offwindir=%WD%\Windows
echo.
echo  Done. Press any key to return to the menu.
pause