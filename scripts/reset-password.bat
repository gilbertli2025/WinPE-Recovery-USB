@echo off
setlocal EnableDelayedExpansion
set "WD="
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist "%%d:\Windows\System32\config\SAM" set "WD=%%d:"
if not defined WD ( echo  [ERROR] Windows drive not found. & pause & exit /b )
cls
echo ============================================================
echo   RESET WINDOWS PASSWORD  (local account)
echo ============================================================
echo.
echo   Windows drive: %WD%
echo.
echo   This uses the 'Ease of Access' trick so you can set a
echo   password at the Windows login screen.
echo.
echo   HOW IT WORKS:
echo   1. This copies cmd.exe over Utilman.exe on your Windows drive.
echo   2. You reboot and start Windows NORMALLY (not WinPE).
echo   3. On the login screen, click the "Ease of Access" icon
echo      (Accessibility). A command prompt will open.
echo   4. Type:      net user  USERNAME  NEWPASSWORD
echo      (replace with the real user name and a new password)
echo   5. Close the window and sign in with the new password.
echo   6. To undo this, boot this USB again and re-run option 2
echo      (it restores the original Utilman.exe first).
echo.
echo   This is safe and reversible. Continue?
echo.
set /p c=  Continue? (y/n): 
if /i not "%c%"=="y" exit /b
echo.
echo  Taking ownership of Utilman.exe...
takeown /f "%WD%\Windows\System32\Utilman.exe" /a >nul 2>&1
icacls "%WD%\Windows\System32\Utilman.exe" /grant administrators:F >nul 2>&1
if exist "%WD%\Windows\System32\Utilman.exe.bak" (
  echo  Restoring original Utilman.exe...
  copy /y "%WD%\Windows\System32\Utilman.exe.bak" "%WD%\Windows\System32\Utilman.exe" >nul
)
copy /y "%WD%\Windows\System32\Utilman.exe" "%WD%\Windows\System32\Utilman.exe.bak" >nul
copy /y "%WD%\Windows\System32\cmd.exe" "%WD%\Windows\System32\Utilman.exe" >nul
echo.
echo  Done. Reboot and start Windows to set your password.
echo.
pause