@echo off
setlocal enabledelayedexpansion

set V8_VERSION=%1
set BUILD_ARGS=%2

echo ==========================================
echo Building v8dasm for Windows x64
echo V8 Version: %V8_VERSION%
echo Build Args: %BUILD_ARGS%
echo ==========================================

REM Detect environment (GitHub Actions or local)
if "%GITHUB_WORKSPACE%"=="" (
    echo Detected local environment
    set WORKSPACE_DIR=%~dp0..\..
    set IS_LOCAL=true
    echo Local environment - skipping dependency install (ensure git, python, Visual Studio/clang are installed)
) else (
    echo Detected GitHub Actions environment
    set WORKSPACE_DIR=%GITHUB_WORKSPACE%
    set IS_LOCAL=false
)

echo Workspace: %WORKSPACE_DIR%

REM Configure Git
git config --global user.name "V8 Disassembler Builder"
git config --global user.email "v8dasm.builder@localhost"
git config --global core.autocrlf false
git config --global core.filemode false

cd %HOMEPATH%

REM Get Depot Tools
if not exist depot_tools (
    echo =====[ Getting Depot Tools ]=====
    powershell -command "Invoke-WebRequest https://storage.googleapis.com/chrome-infra/depot_tools.zip -O depot_tools.zip"
    powershell -command "Expand-Archive depot_tools.zip -DestinationPath depot_tools"
    del depot_tools.zip
)

set PATH=%CD%\depot_tools;%PATH%
set DEPOT_TOOLS_WIN_TOOLCHAIN=0
call gclient

REM Create working directory
if not exist v8 mkdir v8
cd v8

REM Get V8 source
if not exist v8 (
    echo =====[ Fetching V8 ]=====
    call fetch v8
    echo target_os = ['win'] >> .gclient
)

cd v8
set V8_DIR=%CD%

REM Checkout specified version
echo =====[ Checking out V8 %V8_VERSION% ]=====
call git fetch --all --tags
call git checkout %V8_VERSION%
call gclient sync

REM Reset to clean state after gclient sync (hooks may modify tracked files like build/util/LASTCHANGE)
echo =====[ Resetting to clean state ]=====
git reset --hard HEAD
git clean -fd

REM Apply patch (multi-level fallback strategy)
echo =====[ Applying v8.patch ]=====
set PATCH_FILE=%WORKSPACE_DIR%\Disassembler\v8.patch
set PATCH_LOG=%WORKSPACE_DIR%\scripts\v8dasm-builders\patch-utils\patch-state.log

REM Call the patch application script
call "%WORKSPACE_DIR%\scripts\v8dasm-builders\patch-utils\apply-patch.cmd" ^
    "%PATCH_FILE%" ^
    "%V8_DIR%" ^
    "%PATCH_LOG%" ^
    "true"

if %errorlevel% neq 0 (
    echo ERROR: Patch application failed. Build aborted.
    echo Check log file: %PATCH_LOG%
    exit /b 1
)

echo ✅ Patch applied successfully


REM Configure build
echo =====[ Configuring V8 Build ]=====
REM Build GN args string
set GN_ARGS=target_os=\"win\" target_cpu=\"x64\" is_component_build=false is_debug=false use_custom_libcxx=false v8_monolithic=true v8_static_library=true v8_enable_disassembler=true v8_enable_object_print=true v8_use_external_startup_data=false dcheck_always_on=false symbol_level=0 is_clang=true

REM Append extra build args if provided
if not "%BUILD_ARGS%"=="" (
    set GN_ARGS=%GN_ARGS% %BUILD_ARGS%
)

echo GN Args: %GN_ARGS%

REM Generate build config directly with gn gen
call gn gen out.gn\x64.release --args="%GN_ARGS%"

REM Build V8 static library
echo =====[ Building V8 Monolith ]=====
call ninja -C out.gn\x64.release v8_monolith

REM Compile v8dasm
echo =====[ Compiling v8dasm ]=====
set DASM_SOURCE=%WORKSPACE_DIR%\Disassembler\v8dasm.cpp
set OUTPUT_NAME=v8dasm-%V8_VERSION%.exe
set CLANG_EXE=third_party\llvm-build\Release+Asserts\bin\clang++.exe

%CLANG_EXE% %DASM_SOURCE% ^
    -std=c++20 ^
    -O2 ^
    -Iinclude ^
    -Lout.gn\x64.release\obj ^
    -lv8_libbase ^
    -lv8_libplatform ^
    -lv8_monolith ^
    -ldbghelp ^
    -lwinmm ^
    -lAdvAPI32 ^
    -luser32 ^
    -o %OUTPUT_NAME%

REM Verify compilation
if exist %OUTPUT_NAME% (
    echo =====[ Build Successful ]=====
    dir %OUTPUT_NAME%
    echo.
    echo Build successful: %OUTPUT_NAME%
    echo Location: %CD%\%OUTPUT_NAME%
) else (
    echo ERROR: %OUTPUT_NAME% not found!
    exit /b 1
)
