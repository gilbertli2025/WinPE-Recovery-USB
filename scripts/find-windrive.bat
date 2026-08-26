@echo off
setlocal EnableDelayedExpansion
rem Find the drive that contains Windows (varies in WinPE).
set "WD="
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist "%%d:\Windows\System32\config\SAM" set "WD=%%d:"
if not defined WD (
  echo  [ERROR] Could not find the Windows drive.
  echo  The hard drive may not be detected. Use option 7 to list drives.
  echo.
  pause
  exit /b
)
echo  Windows drive: %WD%
endlocal & set "WD=%WD%"