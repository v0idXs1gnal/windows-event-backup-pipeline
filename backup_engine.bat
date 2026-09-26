@echo off
setlocal EnableDelayedExpansion

REM ======================================================
REM USER CONFIGURATION (EDIT TO MATCH YOUR ENVIRONMENT)
REM ======================================================
set "TARGET_DRIVE=D:"
set "DEST_ROOT=%TARGET_DRIVE%\System_Backup"
set "SOURCE_USER=C:\Users\<YOUR_USERNAME>"
set "SOURCE_VMS=C:\Virtual Machines"

REM Exclusions (Space-separated directory/file names)
set "DIR_EXCLUSIONS=AppData Downloads .local"
set "FILE_EXCLUSIONS=desktop.ini NTUSER.DAT* UsrClass.dat* *.lock *.tmp"
REM ======================================================

REM Give OS time to unlock the file system on hotplug
timeout /t 5 /nobreak >nul

REM Verify Backup Target Exists
IF NOT EXIST "%DEST_ROOT%\" (
    exit /b 1
)

REM *** TIME & PATH SETUP ***
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd'"') do set TODAY=%%I
for /f %%W in ('powershell -NoProfile -Command "Get-Date -UFormat '%%U'"') do set WEEK_NUM=%%W
for /f %%Y in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy'"') do set YEAR=%%Y

set "DEST_MIRROR=%DEST_ROOT%\Live_Mirror"
set "DAILY_FLAG=%DEST_ROOT%\flag_%TODAY%.txt"
set "DAILY_LOG=%DEST_ROOT%\mirror_log.txt"
set "DAILY_RUN_LOG=%DEST_ROOT%\mirror_run_tmp.txt"

set "ARCHIVE_ROOT=%DEST_ROOT%\Archive"
set "WEEK_FLAG=%ARCHIVE_ROOT%\flag_week_%YEAR%_%WEEK_NUM%.txt"
set "THIS_ARCHIVE=%ARCHIVE_ROOT%\%TODAY%"
set "ARCHIVE_LOG=%ARCHIVE_ROOT%\archive_log.txt"
set "ARCHIVE_RUN_LOG=%ARCHIVE_ROOT%\archive_run_tmp.txt"

REM Ensure base directories exist
if not exist "%ARCHIVE_ROOT%" mkdir "%ARCHIVE_ROOT%" 2>nul
if not exist "%DEST_MIRROR%" mkdir "%DEST_MIRROR%" 2>nul

REM ======================================================
REM PHASE 1: DAILY MIRROR
REM ======================================================
IF EXIST "%DAILY_FLAG%" (
    goto CheckWeeklyArchive
)

call :LogDaily "Starting Daily Mirror Backup..." > "%DAILY_RUN_LOG%"

REM Dead Man's Switch: Guard against empty/unmounted user profiles
set "PROFILE_OK="
for /d %%D in ("%SOURCE_USER%\*") do set "PROFILE_OK=1"
if not defined PROFILE_OK (
    call :LogDaily "CRITICAL ERROR: Profile directory has no subfolders. Aborting." >> "%DAILY_RUN_LOG%"
    goto MergeDailyLog
)

mkdir "%DEST_MIRROR%\UserProfile" 2>nul
mkdir "%DEST_MIRROR%\VMs" 2>nul

call :LogDaily "Running Robocopy for User Profile..." >> "%DAILY_RUN_LOG%"
robocopy "%SOURCE_USER%" "%DEST_MIRROR%\UserProfile" /MIR /R:1 /W:1 /MT:8 /FFT /XD %DIR_EXCLUSIONS% /XJ /XF %FILE_EXCLUSIONS% /DCOPY:T /COPY:DAT /NP /NDL >nul

if errorlevel 8 (
    call :LogDaily "CRITICAL: User Profile backup failed with exit code !ERRORLEVEL!. Aborting." >> "%DAILY_RUN_LOG%"
    goto MergeDailyLog
)

REM Check Running Hypervisors
IF NOT EXIST "%SOURCE_VMS%" goto SkipDailyVM

set "VM_RUNNING=0"
tasklist /FI "IMAGENAME eq VirtualBoxVM.exe" 2>NUL | find /I "VirtualBoxVM.exe" >NUL
if not errorlevel 1 set "VM_RUNNING=1"
tasklist /FI "IMAGENAME eq vmware-vmx.exe" 2>NUL | find /I "vmware-vmx.exe" >NUL
if not errorlevel 1 set "VM_RUNNING=1"
tasklist /FI "IMAGENAME eq vmwp.exe" 2>NUL | find /I "vmwp.exe" >NUL
if not errorlevel 1 set "VM_RUNNING=1"

if "%VM_RUNNING%"=="1" (
    call :LogDaily "WARNING: Hypervisor process active. Skipping VM backup to prevent snapshot corruption." >> "%DAILY_RUN_LOG%"
    goto SkipDailyVM
)

call :LogDaily "Running Robocopy for VMs..." >> "%DAILY_RUN_LOG%"
robocopy "%SOURCE_VMS%" "%DEST_MIRROR%\VMs" /MIR /R:2 /W:5 /MT:8 /FFT /XJ /XF desktop.ini /COPY:DAT /J /NP /NDL >nul

if errorlevel 8 (
    call :LogDaily "CRITICAL: VM backup failed with exit code !ERRORLEVEL!. Aborting." >> "%DAILY_RUN_LOG%"
    goto MergeDailyLog
)

:SkipDailyVM
del /q "%DEST_ROOT%\flag_*.txt" 2>nul
echo SUCCESS > "%DAILY_FLAG%"
call :LogDaily "Daily Mirror Completed Successfully." >> "%DAILY_RUN_LOG%"
echo ------------------------------------------------------ >> "%DAILY_RUN_LOG%"

:MergeDailyLog
if exist "%DAILY_LOG%" type "%DAILY_LOG%" >> "%DAILY_RUN_LOG%"
move /y "%DAILY_RUN_LOG%" "%DAILY_LOG%" >nul

REM Halt if mirror failed
if not exist "%DAILY_FLAG%" exit /b 1

REM ======================================================
REM PHASE 2: WEEKLY ARCHIVE CATCH-UP
REM ======================================================
:CheckWeeklyArchive
IF EXIST "%WEEK_FLAG%" (
    exit /b 0
)

call :LogArchive "Starting Weekly Archive for %TODAY% (Week %WEEK_NUM%)..." > "%ARCHIVE_RUN_LOG%"

mkdir "%THIS_ARCHIVE%\UserProfile" 2>nul
mkdir "%THIS_ARCHIVE%\VMs" 2>nul

call :LogArchive "Archiving User Profile..." >> "%ARCHIVE_RUN_LOG%"
robocopy "%SOURCE_USER%" "%THIS_ARCHIVE%\UserProfile" /E /R:1 /W:1 /MT:8 /FFT /XD %DIR_EXCLUSIONS% /XJ /XF %FILE_EXCLUSIONS% /DCOPY:T /COPY:DAT /NP /NDL >nul

if errorlevel 8 (
    call :LogArchive "CRITICAL: Archive failed with exit code !ERRORLEVEL!. Aborting." >> "%ARCHIVE_RUN_LOG%"
    goto MergeArchiveLog
)

IF NOT EXIST "%SOURCE_VMS%" goto SkipArchiveVM
if "%VM_RUNNING%"=="1" goto SkipArchiveVM

call :LogArchive "Copying full VMs..." >> "%ARCHIVE_RUN_LOG%"
robocopy "%SOURCE_VMS%" "%THIS_ARCHIVE%\VMs" /E /R:2 /W:5 /MT:8 /FFT /XJ /XF desktop.ini /COPY:DAT /J /NP /NDL >nul

if errorlevel 8 (
    call :LogArchive "CRITICAL: VM archive failed with exit code !ERRORLEVEL!. Aborting." >> "%ARCHIVE_RUN_LOG%"
    goto MergeArchiveLog
)

:SkipArchiveVM
REM FIFO Cleanup: Keep newest 4 point-in-time archives
call :LogArchive "Trimming old archives (Retaining newest 4)..." >> "%ARCHIVE_RUN_LOG%"
for /f "skip=4 delims=" %%A in ('dir "%ARCHIVE_ROOT%" /b /ad /o-n') do (
    call :LogArchive "Deleting old archive: %%A" >> "%ARCHIVE_RUN_LOG%"
    rmdir /s /q "%ARCHIVE_ROOT%\%%A"
)

del /q "%ARCHIVE_ROOT%\flag_week_*.txt" 2>nul
echo SUCCESS > "%WEEK_FLAG%"
call :LogArchive "Weekly Archive Completed Successfully." >> "%ARCHIVE_RUN_LOG%"
echo ------------------------------------------------------ >> "%ARCHIVE_RUN_LOG%"

:MergeArchiveLog
if exist "%ARCHIVE_LOG%" type "%ARCHIVE_LOG%" >> "%ARCHIVE_RUN_LOG%"
move /y "%ARCHIVE_RUN_LOG%" "%ARCHIVE_LOG%" >nul
exit /b 0

REM ======================================================
REM LOGGING HELPERS
REM ======================================================
:LogDaily
set "T=%time: =0%"
echo [%date% %T:~0,8%] %~1
exit /b

:LogArchive
set "T=%time: =0%"
echo [%date% %T:~0,8%] %~1
exit /b