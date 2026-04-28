@echo off
:: =============================================================================
:: aws-scanner-tool  —  Windows (Command Prompt)
:: =============================================================================
:: Interactive tool to scan multiple AWS accounts in parallel Docker containers.
:: Requirements: Docker Desktop for Windows must be installed and running.
:: Usage:  Double-click tool.bat  OR  run from Command Prompt
:: =============================================================================

setlocal enabledelayedexpansion

set IMAGE_NAME=aws-scanner
set RESULTS_BASE=%cd%\aws-scan-results
set CONTAINER_PREFIX=aws-scan

:: Build session timestamp
set SCAN_SESSION=%date:~-4,4%%date:~-7,2%%date:~-10,2%_%time:~0,2%%time:~3,2%%time:~6,2%
set SCAN_SESSION=%SCAN_SESSION: =0%

:: Track running container names
set RUNNING_CONTAINERS=

cls
call :banner
call :check_docker
call :build_image
call :run_scans
goto :eof


:: ══════════════════════════════════════════════════════════════════════════════
:: BANNER
:: ══════════════════════════════════════════════════════════════════════════════
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


:: ══════════════════════════════════════════════════════════════════════════════
:: CHECK DOCKER
:: ══════════════════════════════════════════════════════════════════════════════
:check_docker
docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   ERROR: Docker is not running.
    echo   Please start Docker Desktop and try again.
    pause
    exit /b 1
)
echo   [OK] Docker is running.
goto :eof


:: ══════════════════════════════════════════════════════════════════════════════
:: BUILD IMAGE — auto removes old image, always builds fresh
:: ══════════════════════════════════════════════════════════════════════════════
:build_image
echo.
echo   Building scanner Docker image...

:: Step 1 — Verify required files exist
if not exist "%~dp0aws_scan.py" (
    echo.
    echo   ERROR: aws_scan.py not found in: %~dp0
    echo   Make sure aws_scan.py is in the same folder as tool.bat
    pause
    exit /b 1
)
if not exist "%~dp0Dockerfile" (
    echo.
    echo   ERROR: Dockerfile not found in: %~dp0
    pause
    exit /b 1
)

:: Step 2 — Remove old cached image automatically (no manual step needed)
:: This ensures updated aws_scan.py is always included — never a stale cache
docker image inspect %IMAGE_NAME% >nul 2>&1
if %errorlevel% equ 0 (
    echo   Removing old cached image: %IMAGE_NAME%...
    docker rmi %IMAGE_NAME% --force >nul 2>&1
    echo   [OK] Old image removed.
)

:: Step 3 — Build fresh image
echo   Building fresh image (this takes ~1 min first time)...
docker build --no-cache -t %IMAGE_NAME% -f "%~dp0Dockerfile" "%~dp0" 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   ERROR: Docker build failed. See output above.
    pause
    exit /b 1
)
echo   [OK] Image built successfully: %IMAGE_NAME%
goto :eof


:: ══════════════════════════════════════════════════════════════════════════════
:: MAIN SCAN LOOP
:: ══════════════════════════════════════════════════════════════════════════════
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

:: ── Collect all credentials first ────────────────────────────────────────────
set CONT_NUM=0
:cred_loop
set /a CONT_NUM=%CONT_NUM%+1
if %CONT_NUM% GTR %NUM_SCANS% goto :launch_all

echo   ── Credentials for Account %CONT_NUM% ──────────────────────────────
echo   (All fields are shown as you type — including Secret Key)
echo.

:: Access Key — visible input
set "KEY_%CONT_NUM%="
:retry_key_%CONT_NUM%
set /p "KEY_%CONT_NUM%=    AWS Access Key ID      : "
if "!KEY_%CONT_NUM%!"=="" (
    echo   Cannot be empty. Please enter your Access Key ID.
    goto :retry_key_%CONT_NUM%
)

:: Secret Key — visible input (set /p always shows input on Windows)
set "SECRET_%CONT_NUM%="
:retry_secret_%CONT_NUM%
set /p "SECRET_%CONT_NUM%=    AWS Secret Access Key  : "
if "!SECRET_%CONT_NUM%!"=="" (
    echo   Cannot be empty. Please enter your Secret Access Key.
    goto :retry_secret_%CONT_NUM%
)

:: Session Token — optional
set "TOKEN_%CONT_NUM%="
set /p "TOKEN_%CONT_NUM%=    AWS Session Token      : (press Enter to skip) "

:: Default Region
set "REGION_%CONT_NUM%="
set /p "REGION_%CONT_NUM%=    Default Region         : (press Enter for us-east-1) "
if "!REGION_%CONT_NUM%!"=="" set "REGION_%CONT_NUM%=us-east-1"

echo.
goto :cred_loop


:: ══════════════════════════════════════════════════════════════════════════════
:: LAUNCH ALL CONTAINERS IN PARALLEL
:: ══════════════════════════════════════════════════════════════════════════════
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

echo   Starting container for Scan %CONT_NUM%: %CNAME%
echo   Results will appear in: %OUT_DIR%

:: Build docker run command
:: NOTE: -v mounts to /scanner (output dir only)
::       OUTPUT_DIR=/scanner tells aws_scan.py where to write Excel files
::       Script lives in /app inside image — separate from /scanner volume
set DOCKER_RUN=docker run --name %CNAME% --rm
set DOCKER_RUN=%DOCKER_RUN% -v "%OUT_DIR%:/scanner"
set DOCKER_RUN=%DOCKER_RUN% -e OUTPUT_DIR=/scanner
set DOCKER_RUN=%DOCKER_RUN% -e AWS_ACCESS_KEY_ID=!KEY_%CONT_NUM%!
set DOCKER_RUN=%DOCKER_RUN% -e AWS_SECRET_ACCESS_KEY=!SECRET_%CONT_NUM%!
set DOCKER_RUN=%DOCKER_RUN% -e AWS_DEFAULT_REGION=!REGION_%CONT_NUM%!

if not "!TOKEN_%CONT_NUM%!"=="" (
    set DOCKER_RUN=%DOCKER_RUN% -e AWS_SESSION_TOKEN=!TOKEN_%CONT_NUM%!
)

set DOCKER_RUN=%DOCKER_RUN% %IMAGE_NAME%

:: Run in background — log output to file
start "AWS-Scan-%CONT_NUM%" /B cmd /c "%DOCKER_RUN% > "%OUT_DIR%\scan.log" 2>&1"
set RUNNING_CONTAINERS=%RUNNING_CONTAINERS% %CNAME%

echo %CNAME% >> "%RESULTS_BASE%\.running_%SCAN_SESSION%.txt"

timeout /t 2 /nobreak >nul
goto :launch_loop


:: ══════════════════════════════════════════════════════════════════════════════
:: WAIT FOR ALL CONTAINERS TO FINISH
:: ══════════════════════════════════════════════════════════════════════════════
:wait_all
echo.
echo   All containers started. Waiting for scans to complete...
echo   (You can close this window to stop — partial Excel files are saved automatically)
echo.

:check_running
set STILL_RUNNING=0
for %%C in (%RUNNING_CONTAINERS%) do (
    docker ps -q --filter "name=%%C" 2>nul | findstr /r "." >nul 2>&1
    if !errorlevel! equ 0 set /a STILL_RUNNING+=1
)
if %STILL_RUNNING% GTR 0 (
    echo   Running containers: %STILL_RUNNING%  (%time%)
    timeout /t 10 /nobreak >nul
    goto :check_running
)

echo.
echo   All scans completed!
call :show_results
call :ask_again
goto :eof


:: ══════════════════════════════════════════════════════════════════════════════
:: SHOW RESULTS SUMMARY
:: ══════════════════════════════════════════════════════════════════════════════
:show_results
echo.
echo   ══ Results Summary ══════════════════════════════════
set COUNT=0

:: Show completed Excel files
for /r "%RESULTS_BASE%" %%f in (aws_inventory_*.xlsx) do (
    echo   [OK] %%f
    set /a COUNT+=1
)

:: Show any partial files saved during interruption
for /r "%RESULTS_BASE%" %%f in (*_PARTIAL.xlsx) do (
    echo   [PARTIAL] %%f
    set /a COUNT+=1
)

if %COUNT% EQU 0 (
    echo   No Excel files found yet.
    echo   Check scan logs in: %RESULTS_BASE%
    echo.
    echo   To view errors run:
    echo     type "%RESULTS_BASE%\scan1_*\scan.log"
) else (
    echo.
    echo   Total reports : %COUNT%
)

echo   Results folder: %RESULTS_BASE%
echo.
goto :eof


:: ══════════════════════════════════════════════════════════════════════════════
:: ASK RUN AGAIN OR EXIT
:: ══════════════════════════════════════════════════════════════════════════════
:ask_again
echo.
echo   Do you want to scan more accounts?
echo   [Y] Yes — scan more accounts
echo   [N] No  — exit the tool
echo.
set "AGAIN="
set /p AGAIN="  Your choice [Y/N]: "

if /i "%AGAIN%"=="Y" (
    :: Reset for new session
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
:: Invalid input — ask again
echo   Please enter Y or N.
goto :ask_again
