@echo off
:: =============================================================================
:: aws-scanner-tool  —  Windows (Command Prompt / PowerShell)
:: =============================================================================
:: Interactive tool to scan multiple AWS accounts in parallel Docker containers.
:: Requirements: Docker Desktop for Windows must be installed and running.
:: Usage:  tool.bat   (double-click or run from Command Prompt)
:: =============================================================================

setlocal enabledelayedexpansion

set IMAGE_NAME=aws-scanner
set RESULTS_BASE=%cd%\aws-scan-results
set SCAN_SESSION=%date:~-4,4%%date:~-7,2%%date:~-10,2%_%time:~0,2%%time:~3,2%%time:~6,2%
set SCAN_SESSION=%SCAN_SESSION: =0%
set CONTAINER_PREFIX=aws-scan

:: Track running container names for cleanup
set RUNNING_CONTAINERS=

cls
call :banner
call :check_docker
call :build_image
call :run_scans
goto :eof

:: ── Banner ────────────────────────────────────────────────────────────────────
:banner
echo.
echo   ==============================================================
echo     AWS Multi-Account Resource Scanner
echo     Scans ALL resources across ALL regions per account
echo   ==============================================================
echo.
echo   Results folder: %RESULTS_BASE%
echo.
goto :eof

:: ── Check Docker ──────────────────────────────────────────────────────────────
:check_docker
docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   ERROR: Docker is not running.
    echo   Please start Docker Desktop and try again.
    pause
    exit /b 1
)
echo   Docker is running.
goto :eof

:: ── Build image ───────────────────────────────────────────────────────────────
:build_image
echo.
echo   Building scanner Docker image...
docker build -t %IMAGE_NAME% "%~dp0" -f "%~dp0Dockerfile" --quiet
if %errorlevel% neq 0 (
    echo   ERROR: Docker build failed. Check Dockerfile.
    pause
    exit /b 1
)
echo   Image built: %IMAGE_NAME%
goto :eof

:: ── Main scan loop ────────────────────────────────────────────────────────────
:run_scans
echo.
set /p NUM_SCANS="  How many AWS accounts to scan? : "
echo.

if "%NUM_SCANS%"=="" (
    echo   Please enter a number.
    goto :run_scans
)

set /a CHECK=%NUM_SCANS% 2>nul
if %CHECK% LSS 1 (
    echo   Please enter a number of 1 or more.
    goto :run_scans
)

echo   You will now enter credentials for %NUM_SCANS% account(s).
echo   All containers will start in parallel after credentials are collected.
echo.

:: Collect all credentials first
set CONT_NUM=0
:cred_loop
set /a CONT_NUM=%CONT_NUM%+1
if %CONT_NUM% GTR %NUM_SCANS% goto :launch_all

echo   ── Credentials for Account %CONT_NUM% ──────────────────────────────
set /p "KEY_%CONT_NUM%=    AWS Access Key ID      : "
set /p "SECRET_%CONT_NUM%=    AWS Secret Access Key  : "
set /p "TOKEN_%CONT_NUM%=    AWS Session Token      : "
set /p "REGION_%CONT_NUM%=    Default Region [us-east-1]: "
if "!REGION_%CONT_NUM%!"=="" set "REGION_%CONT_NUM%=us-east-1"
echo.
goto :cred_loop

:: ── Launch all containers ─────────────────────────────────────────────────────
:launch_all
echo   Launching %NUM_SCANS% container(s)...
echo.

set CONT_NUM=0
:launch_loop
set /a CONT_NUM=%CONT_NUM%+1
if %CONT_NUM% GTR %NUM_SCANS% goto :wait_all

set CNAME=%CONTAINER_PREFIX%-%SCAN_SESSION%-%CONT_NUM%
set OUT_DIR=%RESULTS_BASE%\scan%CONT_NUM%_%date:~-4,4%%date:~-7,2%%date:~-10,2%
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

echo   Starting container: %CNAME%
echo   Results: %OUT_DIR%

set DOCKER_RUN=docker run --name %CNAME% --rm -v "%OUT_DIR%:/scanner"
set DOCKER_RUN=%DOCKER_RUN% -e AWS_ACCESS_KEY_ID=!KEY_%CONT_NUM%!
set DOCKER_RUN=%DOCKER_RUN% -e AWS_SECRET_ACCESS_KEY=!SECRET_%CONT_NUM%!
set DOCKER_RUN=%DOCKER_RUN% -e AWS_DEFAULT_REGION=!REGION_%CONT_NUM%!

if not "!TOKEN_%CONT_NUM%!"=="" (
    set DOCKER_RUN=%DOCKER_RUN% -e AWS_SESSION_TOKEN=!TOKEN_%CONT_NUM%!
)

set DOCKER_RUN=%DOCKER_RUN% %IMAGE_NAME%

:: Run in background, log to file
start "AWS-Scan-%CONT_NUM%" /B cmd /c "%DOCKER_RUN% > "%OUT_DIR%\scan.log" 2>&1"
set RUNNING_CONTAINERS=%RUNNING_CONTAINERS% %CNAME%

:: Track container name for cleanup
echo %CNAME% >> "%RESULTS_BASE%\.running_%SCAN_SESSION%.txt"

timeout /t 2 /nobreak >nul
goto :launch_loop

:: ── Wait for all to finish ────────────────────────────────────────────────────
:wait_all
echo.
echo   All containers started. Waiting for scans to complete...
echo   (Close this window to stop all scans — containers auto-delete when done)
echo.

:check_running
set STILL_RUNNING=0
for %%C in (%RUNNING_CONTAINERS%) do (
    docker ps -q --filter "name=%%C" 2>nul | findstr /r "." >nul 2>&1
    if !errorlevel! equ 0 set /a STILL_RUNNING+=1
)
if %STILL_RUNNING% GTR 0 (
    echo   Running: %STILL_RUNNING% container(s)... (%time%)
    timeout /t 10 /nobreak >nul
    goto :check_running
)

echo.
echo   All scans completed!
call :show_results

:: ── Ask again or exit ─────────────────────────────────────────────────────────
:ask_again
echo.
echo   Do you want to scan more accounts?
echo   [Y] Yes
echo   [N] No - Exit
echo.
set /p AGAIN="  Your choice [Y/N]: "
if /i "%AGAIN%"=="Y" (
    set SCAN_SESSION=%date:~-4,4%%date:~-7,2%%date:~-10,2%_%time:~0,2%%time:~3,2%%time:~6,2%
    set SCAN_SESSION=%SCAN_SESSION: =0%
    set RUNNING_CONTAINERS=
    goto :run_scans
)
if /i "%AGAIN%"=="N" (
    echo.
    echo   Thank you for using AWS Scanner Tool. Goodbye!
    echo.
    pause
    exit /b 0
)
goto :ask_again

:: ── Show results ──────────────────────────────────────────────────────────────
:show_results
echo.
echo   ══ Results Summary ══════════════════════════════════
set COUNT=0
for /r "%RESULTS_BASE%" %%f in (aws_inventory_*.xlsx) do (
    echo     %%f
    set /a COUNT+=1
)
echo.
echo   Total reports: %COUNT%
echo   Results folder: %RESULTS_BASE%
echo.
goto :eof
