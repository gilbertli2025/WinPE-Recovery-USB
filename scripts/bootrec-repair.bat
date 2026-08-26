@echo off
setlocal EnableDelayedExpansion
set "WD="
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist "%%d:\Windows\System32\config\SAM" set "WD=%%d:"
if not defined WD ( echo  [ERROR] Windows drive not found. Use option 7 to list drives. & pause & exit /b )
cls
echo ============================================================
echo   BOOT REPAIR
echo ============================================================
echo   Windows drive: %WD%
echo.
echo   Step 1 - Rebuild the boot configuration (bcdboot)...
echo     bcdboot "%WD%\Windows" /s %WD% /f ALL
bcdboot "%WD%\Windows" /s %WD% /f ALL
echo.
echo   Step 2 - Repair the master boot record (bootsect)...
echo     bootsect /nt60 %WD% /mbr
bootsect /nt60 %WD% /mbr
echo.
echo   Done. Try restarting the PC normally.
echo   (If a step above says 'not recognized', the tool is missing from this
echo    WinPE - re-run the recovery USB update to add it.)
echo.
pause