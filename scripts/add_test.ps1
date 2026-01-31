#==============================================================================
# DSIM UVM Test Scaffolding Script
# Usage: .\add_test.ps1 -TestName <name> [options]
#
# Creates a new VexRiscv UVM test with template, and registers it in:
#   - sim/tests/<test_name>.sv          (test source from template)
#   - sim/uvm/tb/dsim_config.f          (compilation registration)
#   - sim/regression_tests.json         (regression suite registration)
#   - scripts/run_regression.ps1        (stage test list, if -Stage specified)
#==============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$TestName,

    [string]$Description = "",

    [ValidateSet("smoke", "hazard", "bus", "memory", "custom")]
    [string]$Category = "custom",

    [int]$Stage = 0,

    [int]$TimeoutCycles = 200,

    [int]$ExpectedDurationSec = 15,

    [switch]$Help
)

if ($Help) {
    Write-Host @"
Usage: .\add_test.ps1 -TestName <name> [options]

Options:
  -TestName         Test class name (e.g., vexriscv_branch_test)
  -Description      Test purpose description
  -Category         Test category: smoke, hazard, bus, memory, custom
  -Stage            Add to stage test list (0 = don't add to any stage)
  -TimeoutCycles    Cycle-based timeout in test (default: 200)
  -ExpectedDuration Expected duration in seconds for regression config
  -Help             Show this help

Examples:
  # Create a new hazard test, add to Stage 1
  .\add_test.ps1 -TestName vexriscv_branch_test -Description "Branch instruction verification" -Category hazard -Stage 1

  # Create a custom test (not added to any stage)
  .\add_test.ps1 -TestName vexriscv_csr_test -Description "CSR read/write" -Category custom
"@
    exit 0
}

$ErrorActionPreference = "Stop"

# Paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Workspace = Split-Path -Parent $ScriptDir
$TestFile = Join-Path $Workspace "sim\tests\${TestName}.sv"
$ConfigFile = Join-Path $Workspace "sim\uvm\tb\dsim_config.f"
$RegressionFile = Join-Path $Workspace "sim\regression_tests.json"
$RegressionScript = Join-Path $Workspace "scripts\run_regression.ps1"

# Validate test name format
if ($TestName -notmatch "^[a-z][a-z0-9_]*_test$") {
    Write-Error "Test name must match pattern: <name>_test (e.g., vexriscv_branch_test)"
    exit 1
}

# Check if test already exists
if (Test-Path $TestFile) {
    Write-Error "Test file already exists: $TestFile"
    exit 1
}

# Category ID mapping for Test ID comment
$CategoryStage = switch ($Category) {
    "smoke"   { "Smoke" }
    "hazard"  { "Hazard" }
    "bus"     { "Bus" }
    "memory"  { "Memory" }
    "custom"  { "Custom" }
}

# Default description
if (-not $Description) {
    $Description = "$TestName verification"
}

# ==============================================================
# Step 1: Generate test source file from template
# ==============================================================

Write-Host "Creating test source: sim/tests/${TestName}.sv"

$testTemplate = @"
``timescale 1ns / 1ps

//==============================================================================
// $TestName
//==============================================================================
// Test ID: $CategoryStage
// Duration: ~${ExpectedDurationSec}s
//
// Purpose:
//   $Description
//
// Test Sequence:
//   TODO: Define instruction sequence
//   1. <instruction>   // <effect>
//   2. EBREAK          // Halt
//
// Expected Results:
//   TODO: Define expected register/memory values
//
// Pass/Fail Criteria:
//   TODO: Define pass/fail conditions
//==============================================================================

class ${TestName} extends vexriscv_base_test;

    ``uvm_component_utils(${TestName})

    function new(string name = "${TestName}", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        use_tohost_checking = 0;       // Direct register checking
        timeout_cycles = ${TimeoutCycles};
        auto_start_cpu = 0;            // Manual CPU control
    endfunction

    virtual task run_phase(uvm_phase phase);
        bit test_passed;

        phase.raise_objection(this);

        ``uvm_info(get_type_name(),
            "============================================================\n  ${TestName}\n  ${Description}\n============================================================",
            UVM_NONE)

        // 1. Reset CPU
        reset_cpu();

        // 2. Load test program
        load_test_program();

        // 3. Start CPU
        start_cpu();

        // 4. Wait for completion
        repeat(${TimeoutCycles}) @(posedge `$root.rv32i_tb_top.clk);

        // 5. Halt and verify
        halt_cpu();
        test_passed = verify_results();

        // 6. Report
        if (test_passed) begin
            ``uvm_info(get_type_name(),
                "============================================================\n  TEST PASSED\n============================================================",
                UVM_NONE)
        end else begin
            ``uvm_error(get_type_name(),
                "============================================================\n  TEST FAILED\n============================================================")
        end

        phase.drop_objection(this);
    endtask

    // Load test program via backdoor memory writes
    // Base address: 0x80000000 (BlockRAM start)
    // Data region:  0x80001000 (offset +0x1000, within 8KB BlockRAM)
    virtual task load_test_program();
        ``uvm_info(get_type_name(), "Loading test program...", UVM_MEDIUM)

        // TODO: Replace with actual instruction encodings
        // Format: write_memory_backdoor(32'h<addr>, 32'h<instruction>);
        //
        // Memory map:
        //   0x80000000 - 0x800001FF : Program (code, up to 128 instructions)
        //   0x80001000 - 0x80001FFF : Data (store/load target)
        //
        // RV32I encoding reference:
        //   ADDI rd, rs1, imm  : imm[11:0] | rs1[4:0] | 000 | rd[4:0] | 0010011
        //   LUI  rd, imm       : imm[31:12] | rd[4:0] | 0110111
        //   EBREAK             : 0x00100073

        write_memory_backdoor(32'h80000000, 32'h00000013);  // NOP (placeholder)
        write_memory_backdoor(32'h80000004, 32'h00100073);  // EBREAK
    endtask

    // Verify test results by reading CPU registers
    virtual function bit verify_results();
        bit [31:0] reg_val;
        bit all_pass = 1;

        // TODO: Add register/memory checks
        // Example:
        //   read_cpu_reg(<reg_num>, reg_val);
        //   if (reg_val != 32'h<expected>) begin
        //       ``uvm_error(get_type_name(),
        //           `$sformatf("FAIL: x<N> = 0x%08X (expected 0x<expected>)", reg_val))
        //       all_pass = 0;
        //   end else begin
        //       ``uvm_info(get_type_name(),
        //           `$sformatf("PASS: x<N> = 0x%08X", reg_val), UVM_LOW)
        //   end

        return all_pass;
    endfunction

endclass : ${TestName}
"@

$testTemplate | Out-File -FilePath $TestFile -Encoding UTF8
Write-Host "  Created: $TestFile"

# ==============================================================
# Step 2: Register in dsim_config.f
# ==============================================================

Write-Host "Registering in dsim_config.f..."

$configContent = Get-Content $ConfigFile
$insertLine = "../../tests/${TestName}.sv"

# Find the marker before "# Testbench Top Module"
$insertIndex = -1
for ($i = 0; $i -lt $configContent.Count; $i++) {
    if ($configContent[$i] -match "^# Testbench Top Module") {
        $insertIndex = $i
        break
    }
}

if ($insertIndex -eq -1) {
    Write-Error "Could not find insertion point in dsim_config.f"
    exit 1
}

# Insert test file reference
$newConfig = @()
$newConfig += $configContent[0..($insertIndex - 1)]
$newConfig += $insertLine
$newConfig += $configContent[$insertIndex..($configContent.Count - 1)]
$newConfig | Out-File -FilePath $ConfigFile -Encoding UTF8
Write-Host "  Added to dsim_config.f (before Testbench Top Module)"

# ==============================================================
# Step 3: Register in regression_tests.json
# ==============================================================

Write-Host "Registering in regression_tests.json..."

$regJson = Get-Content $RegressionFile -Raw | ConvertFrom-Json

# Determine target suite
$targetSuite = switch ($Category) {
    "smoke"   { "vexriscv_smoke" }
    "hazard"  { "vexriscv_hazard" }
    "bus"     { "vexriscv_bus" }
    "memory"  { "vexriscv_smoke" }
    "custom"  { "vexriscv_stage1" }
}

# New test entry
$newTest = [pscustomobject]@{
    name = $TestName
    description = $Description
    timeout = 120
    expected_duration = $ExpectedDurationSec
}

# Add to target suite
if ($regJson.regression_suites.PSObject.Properties[$targetSuite]) {
    $regJson.regression_suites.$targetSuite.tests += $newTest
    Write-Host "  Added to suite: $targetSuite"
} else {
    Write-Host "  Warning: Suite '$targetSuite' not found, skipped"
}

# Also add to vexriscv_stage1 (if not already the target)
if ($targetSuite -ne "vexriscv_stage1") {
    if ($regJson.regression_suites.PSObject.Properties["vexriscv_stage1"]) {
        $regJson.regression_suites.vexriscv_stage1.tests += $newTest
        Write-Host "  Added to suite: vexriscv_stage1"
    }
}

$regJson | ConvertTo-Json -Depth 5 | Out-File -FilePath $RegressionFile -Encoding UTF8
Write-Host "  Updated: $RegressionFile"

# ==============================================================
# Step 4: Register in run_regression.ps1 (if stage specified)
# ==============================================================

if ($Stage -eq 1) {
    Write-Host "Adding to Stage 1 test list in run_regression.ps1..."

    $regScriptContent = Get-Content $RegressionScript
    $newEntry = "    `"${TestName}`","

    # Find the last entry in Stage1Tests array (before closing paren)
    for ($i = 0; $i -lt $regScriptContent.Count; $i++) {
        if ($regScriptContent[$i] -match "vexriscv_dbus_access_test") {
            # Add new entry after dbus_access_test
            $newScript = @()
            $newScript += $regScriptContent[0..$i]
            $newScript += $newEntry
            $newScript += $regScriptContent[($i + 1)..($regScriptContent.Count - 1)]
            $newScript | Out-File -FilePath $RegressionScript -Encoding UTF8
            Write-Host "  Added to Stage1Tests in run_regression.ps1"
            break
        }
    }
}

# ==============================================================
# Summary
# ==============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "Test scaffolding complete: $TestName"
Write-Host "============================================================"
Write-Host ""
Write-Host "Files modified:"
Write-Host "  [NEW] sim/tests/${TestName}.sv"
Write-Host "  [MOD] sim/uvm/tb/dsim_config.f"
Write-Host "  [MOD] sim/regression_tests.json"
if ($Stage -eq 1) {
    Write-Host "  [MOD] scripts/run_regression.ps1"
}
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Edit sim/tests/${TestName}.sv:"
Write-Host "     - Define test sequence in load_test_program()"
Write-Host "     - Add verification checks in verify_results()"
Write-Host "  2. Run test:"
Write-Host "     .\scripts\run_test.ps1 ${TestName} -Waves -Verbosity UVM_MEDIUM"
Write-Host ""
