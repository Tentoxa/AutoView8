#!/bin/bash
# apply-patch.sh - Multi-level fallback V8 patch application script (bash/macOS/Linux)
#
# Usage: apply-patch.sh <patch_file> <v8_dir> <log_file> [abort_on_failure]
#
# Arguments:
#   patch_file        - Absolute path to the patch file
#   v8_dir            - Absolute path to the V8 source directory
#   log_file          - Absolute path to the log file
#   abort_on_failure  - Whether to abort on failure (true/false, default: true)

set -o pipefail

PATCH_FILE="$1"
V8_DIR="$2"
LOG_FILE="$3"
ABORT_ON_FAILURE="${4:-true}"

# Validate arguments
if [ -z "$PATCH_FILE" ] || [ -z "$V8_DIR" ] || [ -z "$LOG_FILE" ]; then
    echo "Error: Missing required argument"
    echo "Usage: $0 <patch_file> <v8_dir> <log_file> [abort_on_failure]"
    exit 1
fi

if [ ! -f "$PATCH_FILE" ]; then
    echo "Error: Patch file not found: $PATCH_FILE"
    exit 1
fi

if [ ! -d "$V8_DIR" ]; then
    echo "Error: V8 directory not found: $V8_DIR"
    exit 1
fi

# Ensure log directory exists
LOG_DIR=$(dirname "$LOG_FILE")
mkdir -p "$LOG_DIR"

# Initialize log file
echo "=====[ V8 Patch Application - Multi-level Fallback ]=====" | tee "$LOG_FILE"
echo "Patch file: $PATCH_FILE" | tee -a "$LOG_FILE"
echo "V8 dir:     $V8_DIR" | tee -a "$LOG_FILE"
echo "Log file:   $LOG_FILE" | tee -a "$LOG_FILE"
echo "Abort on failure: $ABORT_ON_FAILURE" | tee -a "$LOG_FILE"
echo "Timestamp: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Reset V8 repo unconditionally to a clean state
reset_to_clean_state() {
    echo "[RESET] Resetting V8 repository to clean state..." | tee -a "$LOG_FILE"
    cd "$V8_DIR"
    git reset --hard HEAD 2>&1 | tee -a "$LOG_FILE"
    git clean -fd 2>&1 | tee -a "$LOG_FILE"
    echo "[RESET] Repository reset to clean state" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

# Check if patch is already applied (reverse check)
check_already_applied() {
    echo "[CHECK] Checking if patch is already applied..." | tee -a "$LOG_FILE"
    cd "$V8_DIR"

    if git apply --check --reverse "$PATCH_FILE" > /dev/null 2>&1; then
        echo "[CHECK] Patch already applied, skipping" | tee -a "$LOG_FILE"
        return 0
    fi

    echo "[CHECK] Patch not yet applied" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    return 1
}

# Level 1: git apply (cleanest method)
try_git_apply() {
    echo "[LEVEL 1] Trying git apply..." | tee -a "$LOG_FILE"
    cd "$V8_DIR"

    if git -c core.autocrlf=false apply --check "$PATCH_FILE" 2>&1 | tee -a "$LOG_FILE"; then
        echo "[LEVEL 1] Check passed, applying..." | tee -a "$LOG_FILE"
        if git -c core.autocrlf=false apply --verbose "$PATCH_FILE" 2>&1 | tee -a "$LOG_FILE"; then
            echo "[LEVEL 1] SUCCESS: Patch applied via git apply" | tee -a "$LOG_FILE"
            return 0
        fi
    fi

    echo "[LEVEL 1] FAILED: git apply failed" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    return 1
}

# Level 2: git apply with 3-way merge
try_git_apply_3way() {
    echo "[LEVEL 2] Trying git apply with 3-way merge..." | tee -a "$LOG_FILE"
    cd "$V8_DIR"

    if git -c core.autocrlf=false apply -3 --verbose "$PATCH_FILE" 2>&1 | tee -a "$LOG_FILE"; then
        if git diff --check 2>&1 | grep -q "conflict"; then
            echo "[LEVEL 2] FAILED: 3-way merge produced conflicts" | tee -a "$LOG_FILE"
            echo "" | tee -a "$LOG_FILE"
            return 1
        fi
        echo "[LEVEL 2] SUCCESS: Patch applied via 3-way merge" | tee -a "$LOG_FILE"
        return 0
    fi

    echo "[LEVEL 2] FAILED: git apply -3 failed" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    return 1
}

# Level 3: git apply --ignore-whitespace
try_git_apply_ignore_whitespace() {
    echo "[LEVEL 3] Trying git apply --ignore-whitespace..." | tee -a "$LOG_FILE"
    cd "$V8_DIR"

    if git -c core.autocrlf=false apply --ignore-whitespace --verbose "$PATCH_FILE" 2>&1 | tee -a "$LOG_FILE"; then
        echo "[LEVEL 3] SUCCESS: Patch applied via --ignore-whitespace" | tee -a "$LOG_FILE"
        return 0
    fi

    echo "[LEVEL 3] FAILED: git apply --ignore-whitespace failed" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    return 1
}

# Level 4: Semantic replacement (Python script)
try_semantic_patches() {
    echo "[LEVEL 4] Trying semantic replacement..." | tee -a "$LOG_FILE"

    SCRIPT_DIR="$(dirname "$0")"
    SEMANTIC_SCRIPT="$SCRIPT_DIR/semantic-patches.py"

    if [ ! -f "$SEMANTIC_SCRIPT" ]; then
        echo "[LEVEL 4] FAILED: Semantic patch script not found: $SEMANTIC_SCRIPT" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        return 1
    fi

    if ! command -v python3 &> /dev/null; then
        echo "[LEVEL 4] FAILED: Python 3 not installed" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        return 1
    fi

    echo "[LEVEL 4] Running semantic patch script..." | tee -a "$LOG_FILE"
    if python3 "$SEMANTIC_SCRIPT" "$V8_DIR" "$LOG_FILE" 2>&1 | tee -a "$LOG_FILE"; then
        echo "[LEVEL 4] SUCCESS: Patch applied via semantic replacement" | tee -a "$LOG_FILE"
        return 0
    fi

    echo "[LEVEL 4] FAILED: Semantic replacement failed" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    return 1
}

# Main flow
main() {
    # Check if already applied
    if check_already_applied; then
        exit 0
    fi

    # Level 1: git apply
    if try_git_apply; then
        exit 0
    fi

    # Reset before level 2
    reset_to_clean_state

    # Level 2: 3-way merge
    if try_git_apply_3way; then
        exit 0
    fi

    # Reset before level 3
    reset_to_clean_state

    # Level 3: ignore-whitespace
    if try_git_apply_ignore_whitespace; then
        exit 0
    fi

    # Reset before level 4
    reset_to_clean_state

    # Level 4: semantic replacement
    if try_semantic_patches; then
        exit 0
    fi

    # All methods failed
    echo "" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
    echo "FAILED: All patch application methods failed" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    if [ "$ABORT_ON_FAILURE" = "true" ]; then
        echo "Build aborted due to patch failure" | tee -a "$LOG_FILE"
        echo "Check log file: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
    else
        echo "WARNING: Continuing build without patch applied" | tee -a "$LOG_FILE"
        echo "NOTE: v8dasm may be missing functionality" | tee -a "$LOG_FILE"
        exit 0
    fi
}

main
