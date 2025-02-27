@echo off
setlocal EnableDelayedExpansion

:: ================================================================
:: ExpediteSERF Cybersecurity Workflow
:: ================================================================
:: This script executes a sequence of PowerShell module scripts defined
:: in your configuration file.
::
:: Usage:
::   run.bat [options]
::
:: Options:
::   -s    Run the SCC Scan module
::          (initiates the SCAP Compliance Checker scan).
::
::   -c    Run the SCC Compare module
::          (compares results from previous scans).
::
::   -b    Run the SERF Capture module
::          (captures the current baseline of system configurations).
::
::   -d    Run the Baseline Compare module
::          (compares the current system state against the baseline).
::
::   -n    Run the Port Scan module
::          (executes an intense Nmap port scan).
::
::   -i    Run the initial setup
::          (captures a baseline and an initial SCAP scan).
::
::   -h    Display detailed help and usage information.
::
:: Example:
::   run.bat -s -c -b
::     Runs SCC Scan, then SCC Compare, then SERF Capture in sequence.
:: ================================================================

:: ---- Determine if Elevation is Needed ----
:: Elevation is needed if:
::   (a) No parameters are given (default run runs all modules including SCC Scan),
::   or (b) The "-s" or "-i" flag is among the arguments.
set "NEED_ELEVATION=0"
if "%~1"=="" (
    set "NEED_ELEVATION=1"
) else (
    for %%A in (%*) do (
        if /I "%%A"=="-s" set "NEED_ELEVATION=1"
        if /I "%%A"=="-i" set "NEED_ELEVATION=1"
    )
)

if "%NEED_ELEVATION%"=="1" (
    net session >nul 2>&1
    if errorlevel 1 (
        echo Elevation required. Relaunching entire workflow in elevated mode...
        if "%*"=="" (
            powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
        ) else (
            powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs -ArgumentList '%*'"
        )
        exit /b
    )
)

:: ---- Define Base Directory and Config File ----
set "BASE_DIR=%~dp0"
set "CONFIG_FILE=%BASE_DIR%config.ini"
if not exist "%CONFIG_FILE%" (
    echo Config file not found: %CONFIG_FILE%
    pause
    exit /b 1
)

:: ---- Load Configuration File (skip lines starting with ;) ----
for /f "usebackq tokens=1,2 delims== eol=;" %%A in ("%CONFIG_FILE%") do (
    if not "%%A"=="" (
        set "%%A=%%B"
    )
)

:: ---- Construct Full Paths for Module Scripts ----
set "SCC_SCAN=%BASE_DIR%%SCC_SCAN_PATH%"
set "SCC_COMPARE=%BASE_DIR%%SCC_COMPARE_PATH%"
set "SERF_CAPTURE=%BASE_DIR%%SERF_CAPTURE_PATH%"
set "BASELINE_COMPARE=%BASE_DIR%%BASELINE_COMPARE_PATH%"
set "PORT_SCAN=%BASE_DIR%%PORT_SCAN_PATH%"

:: ---- (Optional) Debug: Display Full Paths ----
@REM echo Debug: SCC_SCAN         = %SCC_SCAN%
@REM echo Debug: SCC_COMPARE      = %SCC_COMPARE%
@REM echo Debug: SERF_CAPTURE     = %SERF_CAPTURE%
@REM echo Debug: BASELINE_COMPARE = %BASELINE_COMPARE%
@REM echo Debug: PORT_SCAN        = %PORT_SCAN%
@REM echo.

:: ---- Check for Help Flag Using a Loop ----
set "SHOWHELP=0"
for %%a in (%*) do (
    if /I "%%a"=="-h" set "SHOWHELP=1"
)
if "%SHOWHELP%"=="1" (
    call :ShowHelp
    goto :End
)

:: ---- Default Behavior: No Arguments -> Run All Modules ----
if "%~1"=="" (
    call :RunAllModules
    goto :End
)

:: ---- Process Command-Line Arguments in Order ----
for %%A in (%*) do (
    if /I "%%A"=="-s" call :RunModule "%SCC_SCAN%" "SCC Scan"
    if /I "%%A"=="-c" call :RunModule "%SCC_COMPARE%" "SCC Compare"
    if /I "%%A"=="-b" call :RunModule "%SERF_CAPTURE%" "SERF Capture"
    if /I "%%A"=="-d" call :RunModule "%BASELINE_COMPARE%" "Baseline Compare"
    if /I "%%A"=="-n" call :RunModule "%PORT_SCAN%" "Port Scan"
    if /I "%%A"=="-i" call :RunInitialSetup
)
goto :End

:: ---- Subroutine: Run All Modules in Default Order ----
:RunAllModules
call :RunModule "%SCC_SCAN%" "SCC Scan"
call :RunModule "%SCC_COMPARE%" "SCC Compare"
call :RunModule "%SERF_CAPTURE%" "SERF Capture"
call :RunModule "%BASELINE_COMPARE%" "Baseline Compare"
call :RunModule "%PORT_SCAN%" "Port Scan"
goto :EOF

:: ---- Subroutine: Run a Specific Module ----
:RunModule
if not exist "%~1" (
    echo Module not found: %~1
    exit /b 1
)
echo.
@REM echo Running module: %~2...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~1"
goto :EOF

:: ---- Subroutine: Run Initial Setup ----
:RunInitialSetup
echo Running initial setup: SCC Scan and SERF Capture...
call :RunModule "%SCC_SCAN%" "SCC Scan"
call :RunModule "%SERF_CAPTURE%" "SERF Capture"
goto :EOF

:: ---- Subroutine: Display Detailed Help ----
:ShowHelp
echo.
echo ======================================================
echo             ExpediteSERF Cybersecurity workflow
echo ======================================================
echo.
echo This script executes a sequence of PowerShell module scripts as part of
echo the ExpediteSERF cybersecurity scanning workflow. The modules to run are
echo defined in the configuration file (config.ini) located in the same folder.
echo.
echo Usage:
echo     ExpediteSERF.bat [options]
echo.
echo Options:
echo     -s    Run the SCC Scan module
echo            (initiates the SCAP Compliance Checker scan).
echo.
echo     -c    Run the SCC Compare module
echo            (compares results from previous scans).
echo.
echo     -b    Run the SERF Capture module
echo            (captures the current baseline of system configurations).
echo.
echo     -d    Run the Baseline Compare module
echo            (compares the current system state against the baseline).
echo.
echo     -n    Run the Port Scan module
echo            (executes an intense Nmap port scan).
echo.
echo     -i    Run the initial setup
echo            (captures a baseline and an initial SCAP scan).
echo.
echo     -h    Display this help and usage information.
echo.
echo Example:
echo     run.bat -s -c -b
echo         Runs SCC Scan, then SCC Compare, then SERF Capture.
echo.
goto :EOF

:End
pause
exit /b
