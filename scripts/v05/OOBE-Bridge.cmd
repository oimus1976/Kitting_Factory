@echo off
setlocal DisableDelayedExpansion
rem v0.5 entry diagnostics; original Stage PowerShell remains unchanged.
set "KF_PROBE_DIR=%ProgramData%\KF-v05-Probe"
2>nul md "%KF_PROBE_DIR%"
set "KF_PROBE_LOG=%KF_PROBE_DIR%\devicecontext.log"
call :startlog 2>nul
if not errorlevel 1 goto logready
set "KF_PROBE_LOG=%SystemDrive%\KF-v05-entry-fallback.log"
call :startlog 2>nul
if not errorlevel 1 goto logready
exit /b 90
:logready
set "KF_CWD=%CD%"
set "KF_SCRIPT_DIR=%~dp0"
>>"%KF_PROBE_LOG%" echo DATE=%DATE% TIME=%TIME%
set KF_CWD >>"%KF_PROBE_LOG%"
set KF_SCRIPT_DIR >>"%KF_PROBE_LOG%"
>>"%KF_PROBE_LOG%" <nul set /p "IDENTITY="
whoami >>"%KF_PROBE_LOG%" 2>&1
whoami /user >>"%KF_PROBE_LOG%" 2>&1
set "KF_RC=93"
set "KF_MODE="
if not "%~2"=="" goto finish
if "%~1"=="" goto modeok
if /i not "%~1"=="VMEVAL" goto finish
set "KF_MODE=VMEVAL"
:modeok
>>"%KF_PROBE_LOG%" echo MODE=%KF_MODE%
set "KF_RC=91"
for %%F in (OOBE-Bridge-Core-v04.cmd OOBE-Bridge.ps1 After-First-Logon.ps1 Start-Kitting.ps1 Update-Worker.ps1) do (
  if not exist "%~dp0%%F" (
    >>"%KF_PROBE_LOG%" echo MISSING_FILE=%%F
    goto finish
  )
)
>>"%KF_PROBE_LOG%" echo COMMAND_FILES_PRESENT=5
if exist "%ProgramData%\KittingBridge\" >>"%KF_PROBE_LOG%" echo PREEXISTING_BRIDGE=1
if exist "%ProgramData%\KittingFactory\" >>"%KF_PROBE_LOG%" echo PREEXISTING_FACTORY=1
if exist "C:\ClientSoft\" >>"%KF_PROBE_LOG%" echo PREEXISTING_CLIENTSOFT=1
rem Core enforces SYSTEM, VM and existing-state guards. Suppress console output.
call "%~dp0OOBE-Bridge-Core-v04.cmd" %KF_MODE% >nul 2>&1
set "KF_RC=%ERRORLEVEL%"
:finish
>>"%KF_PROBE_LOG%" echo DATE_END=%DATE% TIME_END=%TIME%
>>"%KF_PROBE_LOG%" echo EXIT_CODE=%KF_RC%
>>"%KF_PROBE_LOG%" echo ==== KF v0.5 entry END ====
exit /b %KF_RC%
:startlog
>>"%KF_PROBE_LOG%" echo ==== KF v0.5 entry START ==== && exit /b 0
exit /b 1
