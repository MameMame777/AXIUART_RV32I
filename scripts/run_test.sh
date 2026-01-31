#!/bin/bash
#==============================================================================
# DSIM UVM Test Runner Script
# Usage: ./run_test.sh <test_name> [options]
#
# Options:
#   --waves           Enable waveform capture (MXD format)
#   --verbosity LVL   UVM verbosity (UVM_LOW, UVM_MEDIUM, UVM_DEBUG)
#   --seed N          Random seed (default: 1)
#   --compile-only    Compile only, do not run
#   --run-only        Run only (use existing compiled image)
#==============================================================================

set -e

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
VERBOSITY="UVM_LOW"
SEED=1
WAVES=0
COMPILE_ONLY=0
RUN_ONLY=0
TEST_NAME=""

# DSIM Configuration
DSIM_HOME="${DSIM_HOME:-C:/Program Files/Altair/DSim/2025.1}"
TB_DIR="$WORKSPACE/sim/uvm/tb"
LOG_DIR="$WORKSPACE/sim/exec/logs"
WAVE_DIR="$WORKSPACE/sim/exec/wave"
CONFIG_FILE="dsim_config.f"
TOP_MODULE="rv32i_tb_top"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --waves)
            WAVES=1
            shift
            ;;
        --verbosity)
            VERBOSITY="$2"
            shift 2
            ;;
        --seed)
            SEED="$2"
            shift 2
            ;;
        --compile-only)
            COMPILE_ONLY=1
            shift
            ;;
        --run-only)
            RUN_ONLY=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 <test_name> [options]"
            echo ""
            echo "Options:"
            echo "  --waves           Enable waveform capture"
            echo "  --verbosity LVL   UVM verbosity (UVM_LOW, UVM_MEDIUM, UVM_DEBUG)"
            echo "  --seed N          Random seed (default: 1)"
            echo "  --compile-only    Compile only"
            echo "  --run-only        Run only"
            exit 0
            ;;
        *)
            if [[ -z "$TEST_NAME" ]]; then
                TEST_NAME="$1"
            else
                echo "ERROR: Unknown argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate test name
if [[ -z "$TEST_NAME" ]]; then
    echo "ERROR: Test name required"
    echo "Usage: $0 <test_name> [options]"
    exit 1
fi

# Setup environment
setup_environment() {
    export DSIM_HOME
    export DSIM_ROOT="$DSIM_HOME"
    export DSIM_LIB_PATH="$DSIM_HOME/lib"

    # Add to PATH
    export PATH="$DSIM_HOME/bin:$DSIM_HOME/mingw/bin:$DSIM_HOME/dsim_deps/bin:$DSIM_HOME/lib:$PATH"

    # License
    if [[ -z "$DSIM_LICENSE" ]]; then
        for lic in "$DSIM_HOME/../dsim-license.json" \
                   "$DSIM_HOME/dsim-license.json" \
                   "%LOCALAPPDATA%/metrics-ca/dsim-license.json"; do
            if [[ -f "$lic" ]]; then
                export DSIM_LICENSE="$lic"
                break
            fi
        done
    fi

    # Create directories
    mkdir -p "$LOG_DIR" "$WAVE_DIR"
}

# Run DSIM
run_dsim() {
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local LOG_FILE="$LOG_DIR/${TEST_NAME}_${TIMESTAMP}.log"
    local WAVE_FILE="$WAVE_DIR/${TEST_NAME}_${TIMESTAMP}.mxd"
    local IMAGE_NAME="compiled_image_${TEST_NAME}"

    # Build command
    local CMD=("$DSIM_HOME/bin/dsim.exe")
    CMD+=("-uvm" "1.2")
    CMD+=("-timescale" "1ns/1ps")
    CMD+=("-f" "$CONFIG_FILE")
    CMD+=("-top" "$TOP_MODULE")
    CMD+=("+UVM_TESTNAME=$TEST_NAME")
    CMD+=("+UVM_VERBOSITY=$VERBOSITY")
    CMD+=("-sv_seed" "$SEED")
    CMD+=("-l" "$LOG_FILE")
    CMD+=("+UVM_PHASE_TRACE")
    CMD+=("+UVM_OBJECTION_TRACE")

    if [[ $WAVES -eq 1 ]]; then
        CMD+=("-waves" "$WAVE_FILE")
    fi

    if [[ $COMPILE_ONLY -eq 1 ]]; then
        CMD+=("-genimage" "$IMAGE_NAME")
    elif [[ $RUN_ONLY -eq 1 ]]; then
        CMD+=("-image" "$IMAGE_NAME")
    fi

    # Execute
    echo "============================================================"
    echo "DSIM UVM Test: $TEST_NAME"
    echo "============================================================"
    echo "Working Dir: $TB_DIR"
    echo "Log File: $LOG_FILE"
    [[ $WAVES -eq 1 ]] && echo "Waveform: $WAVE_FILE"
    echo "------------------------------------------------------------"
    echo "Command: ${CMD[*]}"
    echo "============================================================"

    cd "$TB_DIR"
    local EXIT_CODE=0
    "${CMD[@]}" || EXIT_CODE=$?

    # Parse results
    echo ""
    echo "============================================================"
    echo "RESULTS"
    echo "============================================================"

    if [[ -f "$LOG_FILE" ]]; then
        local UVM_ERRORS=$(grep -c "UVM_ERROR" "$LOG_FILE" 2>/dev/null || echo "0")
        local UVM_FATALS=$(grep -c "UVM_FATAL" "$LOG_FILE" 2>/dev/null || echo "0")
        local TEST_PASS=$(grep -c "TEST PASSED" "$LOG_FILE" 2>/dev/null || echo "0")

        echo "UVM Errors: $UVM_ERRORS"
        echo "UVM Fatals: $UVM_FATALS"

        if [[ $TEST_PASS -gt 0 && $UVM_ERRORS -eq 0 && $UVM_FATALS -eq 0 ]]; then
            echo "Status: PASS"
        else
            echo "Status: FAIL"
            # Show errors
            echo ""
            echo "--- Error Summary ---"
            grep -E "UVM_ERROR|UVM_FATAL|FAIL" "$LOG_FILE" 2>/dev/null | head -20 || true
        fi
    fi

    echo ""
    echo "Log: $LOG_FILE"
    [[ $WAVES -eq 1 ]] && echo "Wave: $WAVE_FILE"
    echo "Exit Code: $EXIT_CODE"

    # Output JSON for script consumers
    cat << EOF > "$LOG_DIR/${TEST_NAME}_${TIMESTAMP}_result.json"
{
  "test_name": "$TEST_NAME",
  "status": "$([ $EXIT_CODE -eq 0 ] && echo "success" || echo "failure")",
  "exit_code": $EXIT_CODE,
  "log_file": "$LOG_FILE",
  "wave_file": "$([ $WAVES -eq 1 ] && echo "$WAVE_FILE" || echo "")",
  "timestamp": "$TIMESTAMP"
}
EOF

    return $EXIT_CODE
}

# Main
setup_environment
run_dsim
