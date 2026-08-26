@echo off
cls
echo ============================================================
echo   LIST DRIVES
echo ============================================================
echo   Drives that exist on this PC:
echo.
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist "%%d:\" echo    %%d:\  (exists)
echo.
echo   Tip: the drive that has a "Windows" folder is your Windows drive.
echo   X:\ is the WinPE recovery drive itself - ignore it.
echo.
pause