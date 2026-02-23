@echo on
setlocal enabledelayedexpansion

set V8_VERSION=%1
set BUILD_ARGS=%2

echo ==========================================
echo Building v8dasm for Windows x64
echo V8 Version: %V8_VERSION%
echo Build Args: %BUILD_ARGS%
echo ==========================================

if "%V8_VERSION%"=="" (
    echo ERROR: V8 version not specified
    echo Usage: build-windows.cmd ^<v8_version^> [build_args]
    exit /b 1
)

REM Detect environment (GitHub Actions or local)
if "%GITHUB_WORKSPACE%"=="" (
    echo Detected local environment
    set WORKSPACE_DIR=%~dp0..\..
    set IS_LOCAL=true
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

REM Set up paths - V8 source must already be present (fetched by setup-v8-windows.cmd or cache)
cd /d %USERPROFILE%

if not exist depot_tools (
    echo ERROR: depot_tools not found at %USERPROFILE%\depot_tools
    echo Run setup-v8-windows.cmd first, or ensure the cache was restored correctly.
    exit /b 1
)

set PATH=%USERPROFILE%\depot_tools;%PATH%
set DEPOT_TOOLS_WIN_TOOLCHAIN=0

if not exist v8\v8 (
    echo ERROR: V8 source not found at %USERPROFILE%\v8\v8
    echo Run setup-v8-windows.cmd first, or ensure the cache was restored correctly.
    exit /b 1
)

cd /d %USERPROFILE%\v8\v8
set V8_DIR=%CD%

REM Checkout the specified version (fast on cache hit - just moves HEAD pointer)
echo =====[ Checking out V8 %V8_VERSION% ]=====
git fetch --all --tags
git checkout %V8_VERSION%

REM Reset to clean state (removes any residue from previous builds or partial patches)
echo =====[ Resetting to clean state ]=====
git reset --hard HEAD
git clean -ffd

REM Apply patch (multi-level fallback strategy)
echo =====[ Applying v8.patch ]=====
set PATCH_FILE=%WORKSPACE_DIR%\Disassembler\v8.patch
set PATCH_LOG=%WORKSPACE_DIR%\scripts\v8dasm-builders\patch-utils\patch-state.log
set APPLY_PATCH=%WORKSPACE_DIR%\scripts\v8dasm-builders\patch-utils\apply-patch.cmd

echo Patch file: %PATCH_FILE%
echo V8 dir:     %V8_DIR%
echo Log file:   %PATCH_LOG%
echo Script:     %APPLY_PATCH%

call "%APPLY_PATCH%" "%PATCH_FILE%" "%V8_DIR%" "%PATCH_LOG%" "true"
set PATCH_RESULT=%errorlevel%

if %PATCH_RESULT% neq 0 (
    echo ERROR: Patch application failed. Build aborted.
    echo Check log file: %PATCH_LOG%
    exit /b 1
)

echo Patch applied successfully

REM Configure build
echo =====[ Configuring V8 Build ]=====
set GN_ARGS=target_os="win" target_cpu="x64" is_component_build=false is_debug=false use_custom_libcxx=false v8_monolithic=true v8_static_library=true v8_enable_disassembler=true v8_enable_object_print=true v8_use_external_startup_data=false dcheck_always_on=false symbol_level=0 is_clang=true

if not "%BUILD_ARGS%"=="" (
    set GN_ARGS=%GN_ARGS% %BUILD_ARGS%
)

echo GN Args: %GN_ARGS%

REM Generate build config
call gn gen out.gn\x64.release --args="%GN_ARGS%"
if %errorlevel% neq 0 ( echo ERROR: gn gen failed & exit /b 1 )

REM Build V8 static library
echo =====[ Building V8 Monolith ]=====
call ninja -C out.gn\x64.release v8_monolith
if %errorlevel% neq 0 ( echo ERROR: ninja build failed & exit /b 1 )

REM Compile v8dasm using V8's own bundled clang++
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
if %errorlevel% neq 0 ( echo ERROR: clang++ compile failed & exit /b 1 )

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
