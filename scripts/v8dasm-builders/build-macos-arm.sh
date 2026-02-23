#!/bin/bash
set -e

V8_VERSION=$1
BUILD_ARGS=$2

echo "=========================================="
echo "Building v8dasm for macOS ARM64"
echo "V8 Version: $V8_VERSION"
echo "Build Args: $BUILD_ARGS"
echo "=========================================="

# Detect environment (GitHub Actions or local)
if [ -z "$GITHUB_WORKSPACE" ]; then
    echo "Detected local environment"
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    WORKSPACE_DIR="$( cd "$SCRIPT_DIR/../.." && pwd )"
    IS_LOCAL=true
else
    echo "Detected GitHub Actions environment"
    WORKSPACE_DIR="$GITHUB_WORKSPACE"
    IS_LOCAL=false
fi

echo "Workspace: $WORKSPACE_DIR"

if [ "$IS_LOCAL" = true ]; then
    echo "Local environment - skipping dependency install (ensure git, python3, Xcode Command Line Tools are installed)"
fi

# Configure Git
git config --global user.name "V8 Disassembler Builder"
git config --global user.email "v8dasm.builder@localhost"
git config --global core.autocrlf false
git config --global core.filemode false

# Get Depot Tools
cd ~
if [ ! -d "depot_tools" ]; then
    echo "=====[ Getting Depot Tools ]====="
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi
export PATH=$(pwd)/depot_tools:$PATH
gclient

# Create working directory
mkdir -p v8
cd v8

# Get V8 source
if [ ! -d "v8" ]; then
    echo "=====[ Fetching V8 ]====="
    fetch v8
    echo "target_os = ['mac']" >> .gclient
fi

cd v8
V8_DIR=$(pwd)

# Checkout specified version
echo "=====[ Checking out V8 $V8_VERSION ]====="
git fetch --all --tags
git checkout $V8_VERSION
gclient sync

# Reset to clean state after gclient sync (hooks may modify tracked files like build/util/LASTCHANGE)
echo "=====[ Resetting to clean state ]====="
git reset --hard HEAD
git clean -fd

# Apply patch (multi-level fallback strategy)
echo "=====[ Applying v8.patch ]====="
PATCH_FILE="$WORKSPACE_DIR/Disassembler/v8.patch"
PATCH_LOG="$WORKSPACE_DIR/scripts/v8dasm-builders/patch-utils/patch-state.log"

chmod +x "$WORKSPACE_DIR/scripts/v8dasm-builders/patch-utils/apply-patch.sh"
bash "$WORKSPACE_DIR/scripts/v8dasm-builders/patch-utils/apply-patch.sh" \
    "$PATCH_FILE" \
    "$V8_DIR" \
    "$PATCH_LOG" \
    "true"

if [ $? -ne 0 ]; then
    echo "ERROR: Patch application failed. Build aborted."
    echo "Check log file: $PATCH_LOG"
    exit 1
fi

echo "Patch applied successfully"

# Configure build (ARM64)
echo "=====[ Configuring V8 Build for ARM64 ]====="
GN_ARGS='target_os="mac" target_cpu="arm64" is_component_build=false is_debug=false use_custom_libcxx=false v8_monolithic=true v8_static_library=true v8_enable_disassembler=true v8_enable_object_print=true v8_use_external_startup_data=false dcheck_always_on=false symbol_level=0 is_clang=true'

# Append extra build args if provided
if [ -n "$BUILD_ARGS" ]; then
    GN_ARGS="$GN_ARGS $BUILD_ARGS"
fi

echo "GN Args: $GN_ARGS"

# Generate build config
gn gen out.gn/arm64.release --args="$GN_ARGS"

# Build V8 static library
echo "=====[ Building V8 Monolith ]====="
ninja -C out.gn/arm64.release v8_monolith

# Compile v8dasm
echo "=====[ Compiling v8dasm ]====="
DASM_SOURCE="$WORKSPACE_DIR/Disassembler/v8dasm.cpp"
OUTPUT_NAME="v8dasm-$V8_VERSION"

clang++ $DASM_SOURCE \
    -std=c++20 \
    -O2 \
    -Iinclude \
    -Lout.gn/arm64.release/obj \
    -lv8_libbase \
    -lv8_libplatform \
    -lv8_monolith \
    -o $OUTPUT_NAME

# Verify compilation
if [ -f "$OUTPUT_NAME" ]; then
    echo "=====[ Build Successful ]====="
    ls -lh $OUTPUT_NAME
    file $OUTPUT_NAME
    echo ""
    echo "Build successful: $OUTPUT_NAME"
    echo "Location: $(pwd)/$OUTPUT_NAME"
else
    echo "ERROR: $OUTPUT_NAME binary not found!"
    exit 1
fi
