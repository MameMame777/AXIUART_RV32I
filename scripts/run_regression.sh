#!/bin/bash
#==============================================================================
# DSIM UVM Regression Test Runner Script
# Usage: ./run_regression.sh [options]
#
# Options:
#   --stage N         Run specific stage tests (1, 2, etc.)
#   --test NAME       Run single test (can be repeated)
#   --waves           Enable waveform capture for all tests
#   --verbosity LVL   UVM verbosity (UVM_LOW, UVM_MEDIUM, UVM_DEBUG)
#   --parallel N      Run N tests in parallel (default: 1)
#   --stop-on-fail    Stop regression on first failure
#   --report FILE     Output report file (default: regression_report.txt)
#==============================================================================

set -e

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
VERBOSITY="UVM_LOW"
WAVES=0
PARALLEL=1
STOP_ON_FAIL=0
STAGE=""
SPECIFIC_TESTS=()
REPORT_FILE=""

# Test definitions by stage
declare -a STAGE1_TESTS=(
    "vexriscv_regfile_test"
    "vexriscv_alu_test"
    "vexriscv_pipeline_flow_test"
    "vexriscv_ibus_fetch_test"
    "vexriscv_memory_access_test"
    "vexriscv_ex_bypass_test"
    "vexriscv_mem_bypass_test"
    "vexriscv_wb_bypass_test"
    "vexriscv_load_use_stall_test"
    "vexriscv_dbus_access_test"
)

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --stage)
            STAGE="$2"
            shift 2
            ;;
        --test)
            SPECIFIC_TESTS+=("$2")
            shift 2
            ;;
        --waves)
            WAVES=1
            shift
            ;;
        --verbosity)
            VERBOSITY="$2"
            shift 2
            ;;
        --parallel)
            PARALLEL="$2"
            shift 2
            ;;
        --stop-on-fail)
            STOP_ON_FAIL=1
            shift
            ;;
        --report)
            REPORT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --stage N         Run specific stage tests (1, 2, etc.)"
            echo "  --test NAME       Run single test (can be repeated)"
            echo "  --waves           Enable waveform capture"
            echo "  --verbosity LVL   UVM verbosity (UVM_LOW, UVM_MEDIUM, UVM_DEBUG)"
            echo "  --parallel N      Run N tests in parallel (default: 1)"
            echo "  --stop-on-fail    Stop on first failure"
            echo "  --report FILE     Output report file"
            echo ""
            echo "Available Stage 1 tests:"
            for t in "${STAGE1_TESTS[@]}"; do
                echo "  - $t"
            done
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Determine which tests to run
TESTS_TO_RUN=()

if [[ ${#SPECIFIC_TESTS[@]} -gt 0 ]]; then
    TESTS_TO_RUN=("${SPECIFIC_TESTS[@]}")
elif [[ -n "$STAGE" ]]; then
    case $STAGE in
        1)
            TESTS_TO_RUN=("${STAGE1_TESTS[@]}")
            ;;
        *)
            echo "ERROR: Unknown stage: $STAGE"
            exit 1
            ;;
    esac
else
    # Default: run all Stage 1 tests
    TESTS_TO_RUN=("${STAGE1_TESTS[@]}")
fi

# Setup report file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
if [[ -z "$REPORT_FILE" ]]; then
    REPORT_FILE="$WORKSPACE/sim/exec/logs/regression_${TIMESTAMP}.txt"
fi
REPORT_DIR=$(dirname "$REPORT_FILE")
mkdir -p "$REPORT_DIR"

# Results tracking
declare -A TEST_RESULTS
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Run single test and capture result
run_single_test() {
    local test_name="$1"
    local test_opts=("--verbosity" "$VERBOSITY")

    if [[ $WAVES -eq 1 ]]; then
        test_opts+=("--waves")
    fi

    echo "Running: $test_name"

    local exit_code=0
    "$SCRIPT_DIR/run_test.sh" "$test_name" "${test_opts[@]}" || exit_code=$?

    return $exit_code
}

# Print banner
echo "============================================================"
echo "DSIM UVM Regression Runner"
echo "============================================================"
echo "Timestamp: $TIMESTAMP"
echo "Tests to run: ${#TESTS_TO_RUN[@]}"
echo "Verbosity: $VERBOSITY"
echo "Waves: $([ $WAVES -eq 1 ] && echo "Enabled" || echo "Disabled")"
echo "Stop on fail: $([ $STOP_ON_FAIL -eq 1 ] && echo "Yes" || echo "No")"
echo "Report: $REPORT_FILE"
echo "============================================================"
echo ""

# Initialize report
cat << EOF > "$REPORT_FILE"
================================================================================
DSIM UVM Regression Report
================================================================================
Timestamp: $TIMESTAMP
Tests: ${#TESTS_TO_RUN[@]}
Verbosity: $VERBOSITY

--------------------------------------------------------------------------------
TEST RESULTS
--------------------------------------------------------------------------------
EOF

# Run tests
for test_name in "${TESTS_TO_RUN[@]}"; do
    echo ""
    echo "------------------------------------------------------------"
    echo "[$((PASS_COUNT + FAIL_COUNT + 1))/${#TESTS_TO_RUN[@]}] $test_name"
    echo "------------------------------------------------------------"

    start_time=$(date +%s)

    if run_single_test "$test_name"; then
        TEST_RESULTS["$test_name"]="PASS"
        ((PASS_COUNT++))
        result="PASS"
    else
        TEST_RESULTS["$test_name"]="FAIL"
        ((FAIL_COUNT++))
        result="FAIL"

        if [[ $STOP_ON_FAIL -eq 1 ]]; then
            echo ""
            echo "STOPPING: Test failed and --stop-on-fail is set"
            SKIP_COUNT=$((${#TESTS_TO_RUN[@]} - PASS_COUNT - FAIL_COUNT))
            break
        fi
    fi

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    # Append to report
    printf "%-40s %s (%ds)\n" "$test_name" "$result" "$duration" >> "$REPORT_FILE"
done

# Summary
echo ""
echo "============================================================"
echo "REGRESSION SUMMARY"
echo "============================================================"
echo "Total:   ${#TESTS_TO_RUN[@]}"
echo "Passed:  $PASS_COUNT"
echo "Failed:  $FAIL_COUNT"
echo "Skipped: $SKIP_COUNT"
echo ""

if [[ $FAIL_COUNT -eq 0 && $SKIP_COUNT -eq 0 ]]; then
    echo "Status: ALL TESTS PASSED"
    overall_status="PASS"
else
    echo "Status: REGRESSION FAILED"
    overall_status="FAIL"
fi

echo "============================================================"
echo "Report: $REPORT_FILE"

# Finalize report
cat << EOF >> "$REPORT_FILE"

--------------------------------------------------------------------------------
SUMMARY
--------------------------------------------------------------------------------
Total:   ${#TESTS_TO_RUN[@]}
Passed:  $PASS_COUNT
Failed:  $FAIL_COUNT
Skipped: $SKIP_COUNT
Status:  $overall_status
================================================================================
EOF

# Generate JSON report
JSON_REPORT="${REPORT_FILE%.txt}.json"
cat << EOF > "$JSON_REPORT"
{
  "timestamp": "$TIMESTAMP",
  "total_tests": ${#TESTS_TO_RUN[@]},
  "passed": $PASS_COUNT,
  "failed": $FAIL_COUNT,
  "skipped": $SKIP_COUNT,
  "status": "$overall_status",
  "results": {
EOF

first=1
for test_name in "${!TEST_RESULTS[@]}"; do
    if [[ $first -eq 1 ]]; then
        first=0
    else
        echo "," >> "$JSON_REPORT"
    fi
    printf '    "%s": "%s"' "$test_name" "${TEST_RESULTS[$test_name]}" >> "$JSON_REPORT"
done

cat << EOF >> "$JSON_REPORT"

  }
}
EOF

echo "JSON Report: $JSON_REPORT"

# Exit with appropriate code
if [[ "$overall_status" == "PASS" ]]; then
    exit 0
else
    exit 1
fi
