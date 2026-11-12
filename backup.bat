@echo off
REM ==========================================================
REM  Client PC Backup  -  backup.bat
REM  Works in: Normal Windows (Run as admin), Safe Mode, WinRE
REM  Copies user folders to a USB/external drive with robocopy
REM ==========================================================
setlocal EnableExtensions DisableDelayedExpansion
title Client PC Backup

echo.
echo ==========================================
echo   CLIENT PC BACKUP
echo ==========================================
echo.

REM ---- Detect mode ----
set "MODE=WINDOWS"
if /i "%SystemDrive%"=="X:" set "MODE=WINRE"
echo Mode detected: %MODE%

REM ---- Admin check (not needed in WinRE) ----
if "%MODE%"=="WINDOWS" (
    fltmc >nul 2>&1 || (
        echo.
        echo [ERROR] Run this as Administrator: right-click ^> Run as administrator.
        pause
        exit /b 1
    )
)

REM ---- Show drives ----
echo.
echo Drives on this PC (check sizes and labels):
echo list volume > "%TEMP%\dp.txt"
diskpart /s "%TEMP%\dp.txt"
del "%TEMP%\dp.txt" >nul 2>&1
echo.

REM ---- Ask for source / destination ----
set /p "SRC=Windows drive letter (the one with \Users, e.g. C or D): "
set "SRC=%SRC::=%"
if not exist "%SRC%:\Users\" (
    echo [ERROR] %SRC%:\Users not found. Wrong drive, or it is BitLocker locked.
    echo         Check with: manage-bde -status
    pause
    exit /b 1
)

set /p "DST=Backup drive letter (your USB, e.g. E): "
set "DST=%DST::=%"
if /i "%DST%"=="%SRC%" (
    echo [ERROR] Backup drive cannot be the same as the Windows drive.
    pause
    exit /b 1
)
if not exist "%DST%:\" (
    echo [ERROR] Drive %DST%: not found.
    pause
    exit /b 1
)

set /p "CLIENT=Client name (no spaces, e.g. MariaL): "
if "%CLIENT%"=="" set "CLIENT=Client"

set /p "ONED=Include OneDrive folder? Can be large / cloud-only files (Y/N): "

REM ---- Build backup folder name ----
set "STAMP=%date%_%time%"
set "STAMP=%STAMP:/=-%"
set "STAMP=%STAMP::=-%"
set "STAMP=%STAMP:.=-%"
set "STAMP=%STAMP:,=-%"
set "STAMP=%STAMP: =_%"
set "ROOT=%DST%:\Backups\%CLIENT%_%STAMP%"
mkdir "%ROOT%\Users" 2>nul
set "LOG=%ROOT%\backup_log.txt"
set "FAILS=0"

REM ---- Pick users ----
echo.
echo User folders found on %SRC%:
echo ------------------------------
for /f "delims=" %%U in ('dir /b /ad "%SRC%:\Users"') do call :showuser "%%U"
echo ------------------------------
echo Type ALL to back up every user above,
echo or type one user folder name at a time (blank line = done).
echo.

set "FIRST="
set /p "FIRST=User (or ALL): "
if /i "%FIRST%"=="ALL" (
    for /f "delims=" %%U in ('dir /b /ad "%SRC%:\Users"') do call :maybecopy "%%U"
    goto extras
)
if "%FIRST%"=="" goto extras
call :copyuser "%FIRST%"

:askmore
set "NEXT="
set /p "NEXT=Another user (blank = done): "
if "%NEXT%"=="" goto extras
call :copyuser "%NEXT%"
goto askmore

REM ==========================================================
:extras
if "%MODE%"=="WINRE" goto summary
echo.
echo Collecting extras (program list, system info, product key)...
mkdir "%ROOT%\Extras" 2>nul
systeminfo > "%ROOT%\Extras\system_info.txt" 2>nul
powershell -NoProfile -Command "Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object DisplayName | Sort-Object DisplayName -Unique | Select-Object DisplayName, DisplayVersion, Publisher | Format-Table -AutoSize | Out-String -Width 300" > "%ROOT%\Extras\installed_programs.txt" 2>nul
powershell -NoProfile -Command "$k=(Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey; if($k){$k}else{'No key in firmware (digital license or retail key).'}" > "%ROOT%\Extras\windows_product_key.txt" 2>nul

set "WIFI="
set /p "WIFI=Export saved Wi-Fi networks WITH passwords? Stored in plain text (Y/N): "
if /i "%WIFI%"=="Y" (
    mkdir "%ROOT%\Extras\WiFi" 2>nul
    netsh wlan export profile key=clear folder="%ROOT%\Extras\WiFi" >nul 2>&1
    echo Wi-Fi profiles exported.
)

REM ==========================================================
:summary
(
echo Client: %CLIENT%
echo Date: %date% %time%
echo Mode: %MODE%
echo Source: %SRC%:\Users
echo Destination: %ROOT%
echo Users with copy errors: %FAILS%
) > "%ROOT%\job_info.txt"

echo.
echo ==========================================
if "%FAILS%"=="0" (
    echo   BACKUP FINISHED - no copy errors
) else (
    echo   BACKUP FINISHED - %FAILS% user^(s^) had errors
    echo   Open the log and search for "ERROR"
)
echo   Saved to: %ROOT%
echo   Log:      %LOG%
echo ==========================================
echo.
pause
exit /b 0

REM ==========================================================
:showuser
set "U=%~1"
for %%S in ("Public" "Default" "Default User" "All Users" "defaultuser0" "WDAGUtilityAccount") do if /i "%U%"==%%S goto :eof
echo   %U%
goto :eof

:maybecopy
set "U=%~1"
for %%S in ("Public" "Default" "Default User" "All Users" "defaultuser0" "WDAGUtilityAccount") do if /i "%U%"==%%S goto :eof
call :copyuser "%U%"
goto :eof

:copyuser
set "U=%~1"
set "S=%SRC%:\Users\%U%"
if not exist "%S%\" (
    echo [SKIP] "%S%" not found - check the spelling.
    goto :eof
)
echo.
echo ---- Backing up %U% ----
set "XOD="
if /i not "%ONED%"=="Y" set "XOD="%S%\OneDrive""

robocopy "%S%" "%ROOT%\Users\%U%" /E /ZB /COPY:DAT /DCOPY:T /XJ /R:1 /W:1 /MT:8 /NP /TEE /LOG+:"%LOG%" ^
 /XD "%S%\AppData\Local\Temp" "%S%\AppData\Local\Microsoft\Windows\INetCache" "%S%\AppData\Local\CrashDumps" "%S%\AppData\Local\Google\Chrome\User Data\Default\Cache" "%S%\AppData\Local\Microsoft\Edge\User Data\Default\Cache" %XOD% ^
 /XF NTUSER.DAT* ntuser.dat.LOG* UsrClass.dat* *.tmp

REM robocopy exit codes: 0-7 = OK, 8+ = some files failed
if errorlevel 8 (
    echo [WARNING] Some files for %U% failed to copy. See the log.
    set /a FAILS+=1
) else (
    echo [OK] %U% done.
)
goto :eof
