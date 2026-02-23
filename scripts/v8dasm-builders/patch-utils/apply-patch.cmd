@echo off
REM apply-patch.cmd - Multi-level fallback V8 patch application script (Windows)
REM
REM Usage: apply-patch.cmd <patch_file> <v8_dir> <log_file> [abort_on_failure]
REM
REM Arguments:
REM   patch_file        - Absolute path to the patch file
REM   v8_dir            - Absolute path to the V8 source directory
REM   log_file          - Absolute path to the log file
REM   abort_on_failure  - Whether to abort on failure (true/false, default: true)

setlocal enabledelayedexpansion

REM Parse arguments
set PATCH_FILE=%~1
set V8_DIR=%~2
set LOG_FILE=%~3
set ABORT_ON_FAILURE=%~4
if "%ABORT_ON_FAILURE%"=="" set ABORT_ON_FAILURE=true

REM Validate arguments
if "%PATCH_FILE%"=="" (
    echo Error: Missing required argument
    echo Usage: %~nx0 ^<patch_file^> ^<v8_dir^> ^<log_file^> [abort_on_failure]
    exit /b 1
)

if "%V8_DIR%"=="" (
    echo Error: Missing required argument
    echo Usage: %~nx0 ^<patch_file^> ^<v8_dir^> ^<log_file^> [abort_on_failure]
    exit /b 1
)

if "%LOG_FILE%"=="" (
    echo Error: Missing required argument
    echo Usage: %~nx0 ^<patch_file^> ^<v8_dir^> ^<log_file^> [abort_on_failure]
    exit /b 1
)

if not exist "%PATCH_FILE%" (
    echo Error: Patch file not found: %PATCH_FILE%
    exit /b 1
)

if not exist "%V8_DIR%" (
    echo Error: V8 directory not found: %V8_DIR%
    exit /b 1
)

REM Ensure log directory exists
for %%F in ("%LOG_FILE%") do set LOG_DIR=%%~dpF
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

REM Initialize log file
echo =====[ V8 Patch Application - Multi-level Fallback ]===== > "%LOG_FILE%"
echo Patch file: %PATCH_FILE% >> "%LOG_FILE%"
echo V8 dir:     %V8_DIR% >> "%LOG_FILE%"
echo Log file:   %LOG_FILE% >> "%LOG_FILE%"
echo Abort on failure: %ABORT_ON_FAILURE% >> "%LOG_FILE%"
echo Timestamp: %date% %time% >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

echo =====[ V8 Patch Application - Multi-level Fallback ]=====
echo Patch file: %PATCH_FILE%
echo V8 dir:     %V8_DIR%
echo Log file:   %LOG_FILE%
echo Abort on failure: %ABORT_ON_FAILURE%
echo Timestamp: %date% %time%
echo.

REM Check if patch is already applied (reverse check)
:check_already_applied
echo [CHECK] Checking if patch is already applied...
echo [CHECK] Checking if patch is already applied... >> "%LOG_FILE%"
cd /d "%V8_DIR%"

git -c core.autocrlf=false apply --check --reverse "%PATCH_FILE%" >nul 2>&1
if %errorlevel% equ 0 (
    echo [CHECK] Patch already applied, skipping
    echo [CHECK] Patch already applied, skipping >> "%LOG_FILE%"
    exit /b 0
)

echo [CHECK] Patch not yet applied
echo [CHECK] Patch not yet applied >> "%LOG_FILE%"
echo.
echo. >> "%LOG_FILE%"

REM Level 1: git apply (cleanest method)
:try_git_apply
echo [LEVEL 1] Trying git apply...
echo [LEVEL 1] Trying git apply... >> "%LOG_FILE%"
cd /d "%V8_DIR%"

git -c core.autocrlf=false apply --check "%PATCH_FILE%" >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    echo [LEVEL 1] Check passed, applying...
    echo [LEVEL 1] Check passed, applying... >> "%LOG_FILE%"
    git -c core.autocrlf=false apply --verbose "%PATCH_FILE%" >> "%LOG_FILE%" 2>&1
    if %errorlevel% equ 0 (
        echo [LEVEL 1] SUCCESS: Patch applied via git apply
        echo [LEVEL 1] SUCCESS: Patch applied via git apply >> "%LOG_FILE%"
        exit /b 0
    )
)

echo [LEVEL 1] FAILED: git apply failed
echo [LEVEL 1] FAILED: git apply failed >> "%LOG_FILE%"
echo.
echo. >> "%LOG_FILE%"

REM Reset before trying level 2
call :reset_to_clean_state

REM Level 2: git apply with 3-way merge
:try_git_apply_3way
echo [LEVEL 2] Trying git apply with 3-way merge...
echo [LEVEL 2] Trying git apply with 3-way merge... >> "%LOG_FILE%"
cd /d "%V8_DIR%"

git -c core.autocrlf=false apply -3 --verbose "%PATCH_FILE%" >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    REM Check for conflict markers
    git diff --check 2>&1 | findstr /C:"conflict" >nul
    if errorlevel 1 (
        echo [LEVEL 2] SUCCESS: Patch applied via 3-way merge
        echo [LEVEL 2] SUCCESS: Patch applied via 3-way merge >> "%LOG_FILE%"
        exit /b 0
    ) else (
        echo [LEVEL 2] FAILED: 3-way merge produced conflicts
        echo [LEVEL 2] FAILED: 3-way merge produced conflicts >> "%LOG_FILE%"
    )
)

echo [LEVEL 2] FAILED: git apply -3 failed
echo [LEVEL 2] FAILED: git apply -3 failed >> "%LOG_FILE%"
echo.
echo. >> "%LOG_FILE%"

REM Reset before trying level 3
call :reset_to_clean_state

REM Level 3: git apply --ignore-whitespace
:try_git_apply_ignore_whitespace
echo [LEVEL 3] Trying git apply --ignore-whitespace...
echo [LEVEL 3] Trying git apply --ignore-whitespace... >> "%LOG_FILE%"
cd /d "%V8_DIR%"

git -c core.autocrlf=false apply --ignore-whitespace --verbose "%PATCH_FILE%" >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    echo [LEVEL 3] SUCCESS: Patch applied via --ignore-whitespace
    echo [LEVEL 3] SUCCESS: Patch applied via --ignore-whitespace >> "%LOG_FILE%"
    exit /b 0
)

echo [LEVEL 3] FAILED: git apply --ignore-whitespace failed
echo [LEVEL 3] FAILED: git apply --ignore-whitespace failed >> "%LOG_FILE%"
echo.
echo. >> "%LOG_FILE%"

REM Reset before trying level 4
call :reset_to_clean_state

REM Level 4: Semantic replacement (Python script)
:try_semantic_patches
echo [LEVEL 4] Trying semantic replacement...
echo [LEVEL 4] Trying semantic replacement... >> "%LOG_FILE%"

set SCRIPT_DIR=%~dp0
set SEMANTIC_SCRIPT=%SCRIPT_DIR%semantic-patches.py

if not exist "%SEMANTIC_SCRIPT%" (
    echo [LEVEL 4] FAILED: Semantic patch script not found: %SEMANTIC_SCRIPT%
    echo [LEVEL 4] FAILED: Semantic patch script not found: %SEMANTIC_SCRIPT% >> "%LOG_FILE%"
    echo.
    echo. >> "%LOG_FILE%"
    goto :all_failed
)

REM Check if Python 3 is available
where python3 >nul 2>&1
if errorlevel 1 (
    where python >nul 2>&1
    if errorlevel 1 (
        echo [LEVEL 4] FAILED: Python not installed
        echo [LEVEL 4] FAILED: Python not installed >> "%LOG_FILE%"
        echo.
        echo. >> "%LOG_FILE%"
        goto :all_failed
    )
    set PYTHON_CMD=python
) else (
    set PYTHON_CMD=python3
)

echo [LEVEL 4] Running semantic patch script...
echo [LEVEL 4] Running semantic patch script... >> "%LOG_FILE%"
%PYTHON_CMD% "%SEMANTIC_SCRIPT%" "%V8_DIR%" "%LOG_FILE%" >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    echo [LEVEL 4] SUCCESS: Patch applied via semantic replacement
    echo [LEVEL 4] SUCCESS: Patch applied via semantic replacement >> "%LOG_FILE%"
    exit /b 0
)

echo [LEVEL 4] FAILED: Semantic replacement failed
echo [LEVEL 4] FAILED: Semantic replacement failed >> "%LOG_FILE%"
echo.
echo. >> "%LOG_FILE%"

REM All methods failed
:all_failed
goto :all_failed_body

REM Level 0 subroutine: Reset V8 repo to clean state (unconditional)
:reset_to_clean_state
echo [RESET] Resetting V8 repository to clean state...
echo [RESET] Resetting V8 repository to clean state... >> "%LOG_FILE%"
cd /d "%V8_DIR%"

git reset --hard HEAD >> "%LOG_FILE%" 2>&1
git clean -fd >> "%LOG_FILE%" 2>&1
echo [RESET] Repository reset to clean state
echo [RESET] Repository reset to clean state >> "%LOG_FILE%"
echo.
echo. >> "%LOG_FILE%"
goto :eof

:all_failed_body
echo.
echo ========================================
echo FAILED: All patch application methods failed
echo ========================================
echo.
echo. >> "%LOG_FILE%"
echo ======================================== >> "%LOG_FILE%"
echo FAILED: All patch application methods failed >> "%LOG_FILE%"
echo ======================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

if /i "%ABORT_ON_FAILURE%"=="true" (
    echo Build aborted due to patch failure
    echo Check log file: %LOG_FILE%
    echo Build aborted due to patch failure >> "%LOG_FILE%"
    echo Check log file: %LOG_FILE% >> "%LOG_FILE%"
    exit /b 1
) else (
    echo WARNING: Continuing build without patch applied
    echo NOTE: v8dasm may be missing functionality
    echo WARNING: Continuing build without patch applied >> "%LOG_FILE%"
    echo NOTE: v8dasm may be missing functionality >> "%LOG_FILE%"
    exit /b 0
)
