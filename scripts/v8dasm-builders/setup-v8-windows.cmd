@echo on
setlocal enabledelayedexpansion

set V8_VERSION=%1

echo ==========================================
echo Setting up V8 source for Windows x64
echo V8 Version: %V8_VERSION%
echo ==========================================

if "%V8_VERSION%"=="" (
    echo ERROR: V8 version not specified
    echo Usage: setup-v8-windows.cmd ^<v8_version^>
    exit /b 1
)

REM Configure Git
git config --global user.name "V8 Disassembler Builder"
git config --global user.email "v8dasm.builder@localhost"
git config --global core.autocrlf false
git config --global core.filemode false

cd /d %USERPROFILE%

REM Get Depot Tools (skip if already cached)
if not exist depot_tools (
    echo =====[ Getting Depot Tools ]=====
    powershell -command "Invoke-WebRequest https://storage.googleapis.com/chrome-infra/depot_tools.zip -O depot_tools.zip"
    powershell -command "Expand-Archive depot_tools.zip -DestinationPath depot_tools"
    del depot_tools.zip
) else (
    echo =====[ Depot Tools already present ]=====
)

set PATH=%USERPROFILE%\depot_tools;%PATH%
set DEPOT_TOOLS_WIN_TOOLCHAIN=0
call gclient

REM Create working directory
if not exist v8 mkdir v8
cd v8

REM Fetch V8 source (skip if already fetched)
if not exist v8 (
    echo =====[ Fetching V8 ]=====
    call fetch v8
    echo target_os = ['win'] >> .gclient
) else (
    echo =====[ V8 source already present ]=====
)

cd v8

REM Checkout specified version
echo =====[ Checking out V8 %V8_VERSION% ]=====
git fetch --all --tags
git -c advice.detachedHead=false checkout %V8_VERSION%

REM Sync all dependencies for this version
echo =====[ Running gclient sync ]=====
call gclient sync

REM Reset to clean state after gclient sync
REM (hooks may modify tracked files like build/util/LASTCHANGE)
echo =====[ Resetting to clean state after sync ]=====
git reset --hard HEAD
git clean -fd

echo =====[ V8 Source Setup Complete ]=====
echo V8 %V8_VERSION% is ready at %CD%

exit /b 0
