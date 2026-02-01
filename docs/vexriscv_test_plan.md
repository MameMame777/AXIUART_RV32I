# VexRiscv Verification Test Plan

**Created**: 2026-01-18  
**Project**: AXIUART_RV32I  
**Architecture**: VexRiscv GenSmallOptimized (RV32I)  
**Branch**: feature/vexriscv-complete-redesign

---

## Table of Contents

1. [Overview & Methodology](#1-overview--methodology)
2. [Test Infrastructure](#2-test-infrastructure)
3. [Stage 1: UVM+MCP Unit Tests](#3-stage-1-uvmmcp-unit-tests)
4. [Stage 2: VexRiscv Integration Tests](#4-stage-2-vexriscv-integration-tests)
5. [Stage 3: Assertion Strategy](#5-stage-3-assertion-strategy)
6. [Test Execution Workflow](#6-test-execution-workflow)
7. [Success Criteria & Metrics](#7-success-criteria--metrics)

---

## 1. Overview & Methodology

### 1.1 Test Philosophy

**Core Principles**:
1. **Fresh Start Required** - Architecture changed from custom RV32I to VexRiscv; existing tests are reference-only
2. **Upstream Resource Reuse** - Leverage VexRiscv's 180+ pre-compiled ISA tests (riscv-tests suite)
3. **Non-Intrusive Assertions** - All assertions in separate modules, bound to DUT (mandatory practice)
4. **Observable Verification** - Test through UART debug interface, not direct RTL access
5. **MCP Automation** - FastMCP server orchestrates all test execution

### 1.2 Architecture Context

**VexRiscv Configuration** (from `vexriscv_reference/config/GenSmallOptimized.scala`):
- **ISA**: RV32I base only (no M/C/F extensions)
- **Pipeline**: 4 stages (DECODE → EXECUTE → MEMORY → WRITEBACK)
- **Hazard Plugin**: bypassExecute, bypassMemory, bypassWriteBack, **bypassWriteBackBuffer** (critical fix)
- **Reset Vector**: 0x00000000 (custom, not standard 0x80000000)
- **Target Frequency**: 125MHz @ Zynq-7020
- **Memory**: 8KB dual-port BlockRAM (0x0000_0000 - 0x0000_1FFF)

**Key Difference from Existing Tests**:
- Previous tests targeted custom 6-stage RV32I core
- VexRiscv has different internal signals (e.g., `decode_arbitration_isStuck`)
- Hazard resolution mechanism changed (VexRiscv HazardSimplePlugin vs custom hazard unit)

### 1.3 Test Staging Strategy

```
Stage 1: UVM+MCP Unit Tests (2-3 weeks)
├── Smoke Tests: Register File, Pipeline Flow, Memory Access
├── Hazard Tests: EX/MEM/WB Bypass + Load-Use Stall
└── Bus Tests: IBus/DBus Protocol

Stage 2: VexRiscv Integration (3-4 weeks)
├── ISA Tests: 30 RV32I instruction tests (upstream)
├── Compliance Tests: 40+ RISC-V compliance suite
├── Exception Tests: EBREAK/ECALL/MRET/Interrupts
└── Control Flow: Branches/Jumps/Penalties

Stage 3: Assertion Coverage (Ongoing)
├── Pipeline Arbitration Assertions
├── Hazard Plugin Assertions
├── Stream FIFO Protocol Assertions
├── Jump Interface Assertions
└── RegFile Bypass Assertions
```

**Timeline**:
- **Stage 1**: 2-3 weeks (build UVM test infrastructure)
- **Stage 2**: 3-4 weeks (integrate 180+ ISA tests)
- **Stage 3**: Ongoing (add assertions as bugs discovered)
- **Total**: ~8 weeks to full coverage

---

## 2. Test Infrastructure

### 2.1 UVM Test Framework

**Base Class Architecture**:

```systemverilog
// File: sim/uvm/sv/vexriscv_base_test.sv
class vexriscv_base_test extends axiuart_base_test;
    `uvm_component_utils(vexriscv_base_test)
    
    // Configuration
    string hex_file_path;           // Path to Intel HEX file
    bit use_tohost_checking;        // Enable tohost monitor
    int timeout_cycles = 10000;     // Default timeout
    
    // Helper tasks
    virtual task load_hex_file(string hex_path, bit translate_addr = 1);
        // Python MCP tool preprocesses VexRiscv hex files
        // Translates 0x80000000 → 0x00000000 if translate_addr=1
        // Loads into memory via backdoor
    endtask
    
    virtual task wait_for_tohost(int max_cycles = 10000);
        // Monitor address 0x80001000 (or translated address)
        // Wait until tohost written
        // Check value: 1 = PASS, other = FAIL (error code)
    endtask
    
    // CPU control via UART debug interface
    virtual task reset_cpu();
        write_cpu_reg(REG_CPU_CTRL, CTRL_RESET);
        #100ns;
    endtask
    
    virtual task start_cpu();
        write_cpu_reg(REG_CPU_CTRL, CTRL_RUN);
    endtask
    
    virtual task halt_cpu();
        write_cpu_reg(REG_CPU_CTRL, CTRL_HALT);
    endtask
    
    virtual task step_cpu(int steps = 1);
        for (int i = 0; i < steps; i++)
            write_cpu_reg(REG_CPU_CTRL, CTRL_STEP);
    endtask
    
    // Register access helpers
    virtual task read_cpu_reg(int reg_num, output logic [31:0] value);
        // Read via debug interface
    endtask
    
    virtual task write_cpu_reg(int reg_num, logic [31:0] value);
        // Write via debug interface
    endtask
endclass
```

**Test Sequence Pattern**:
```systemverilog
class vexriscv_isa_sequence extends uvm_sequence;
    string test_hex;  // e.g., "rv32ui-p-add.hex"
    
    task body();
        // 1. Load test program (with address translation)
        load_hex_file(test_hex, .translate_addr(1));
        
        // 2. Reset CPU to PC=0
        reset_cpu();
        
        // 3. Start execution
        start_cpu();
        
        // 4. Wait for completion or timeout
        wait_for_tohost(10000);
        
        // 5. Check result
        if (tohost_value == 32'h1)
            `uvm_info("TEST", "PASS", UVM_LOW)
        else
            `uvm_error("TEST", $sformatf("FAIL: error code %0d", tohost_value))
    endtask
endclass
```

### 2.2 Python Hex Loader with Address Translation

**File**: `tools/vexriscv_hex_loader.py`

```python
import re
from pathlib import Path

class VexRiscvHexLoader:
    """
    Load VexRiscv Intel HEX files with address translation.
    
    VexRiscv tests expect boot at 0x80000000 (standard RISC-V).
    Our hardware boots at 0x00000000 (bare-metal).
    This loader translates addresses automatically.
    """
    
    def __init__(self, hex_file: str, address_offset: int = -0x80000000):
        self.hex_file = Path(hex_file)
        self.address_offset = address_offset
        self.memory = {}  # {addr: byte_value}
        
    def parse_hex(self) -> dict:
        """
        Parse Intel HEX format and apply address translation.
        
        Intel HEX format:
        :LLAAAATT[DD...]CC
        LL = byte count
        AAAA = address
        TT = record type (00=data, 01=EOF, 04=extended linear address)
        DD = data bytes
        CC = checksum
        """
        extended_addr = 0
        
        with open(self.hex_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line.startswith(':'):
                    continue
                    
                byte_count = int(line[1:3], 16)
                address = int(line[3:7], 16)
                record_type = int(line[7:9], 16)
                data = line[9:9+byte_count*2]
                
                if record_type == 0x00:  # Data record
                    full_addr = (extended_addr << 16) + address
                    translated_addr = full_addr + self.address_offset
                    
                    for i in range(0, len(data), 2):
                        byte_val = int(data[i:i+2], 16)
                        self.memory[translated_addr + i//2] = byte_val
                        
                elif record_type == 0x04:  # Extended linear address
                    extended_addr = int(data, 16)
                    
                elif record_type == 0x01:  # EOF
                    break
                    
        return self.memory
    
    def get_word_aligned_data(self) -> dict:
        """
        Convert byte memory to word-aligned dictionary.
        Returns: {word_addr: 32-bit_value}
        """
        word_data = {}
        sorted_addrs = sorted(self.memory.keys())
        
        for addr in range(sorted_addrs[0], sorted_addrs[-1] + 1, 4):
            word = 0
            for i in range(4):
                if addr + i in self.memory:
                    word |= self.memory[addr + i] << (i * 8)
            word_data[addr >> 2] = word  # Word address
            
        return word_data
    
    def translate_special_addresses(self) -> dict:
        """
        Translate special addresses (tohost, fromhost).
        
        Returns: {
            'tohost': translated_address,
            'fromhost': translated_address,
            'begin_signature': translated_address,
            'end_signature': translated_address
        }
        """
        return {
            'tohost': 0x80001000 + self.address_offset,      # Usually 0x00001000
            'fromhost': 0x80001040 + self.address_offset,    # Usually 0x00001040
            'begin_signature': 0x80002000 + self.address_offset,
            'end_signature': 0x80003000 + self.address_offset
        }
```

### 2.3 UVM tohost Monitor

**File**: `sim/uvm/sv/vexriscv_tohost_monitor.sv`

```systemverilog
class vexriscv_tohost_monitor extends uvm_monitor;
    `uvm_component_utils(vexriscv_tohost_monitor)
    
    // Configuration
    bit [31:0] tohost_addr = 32'h0000_1000;  // Translated from 0x8000_1000
    bit [31:0] tohost_value;
    bit tohost_written;
    event tohost_event;
    
    // Virtual interface (connected to memory controller)
    virtual axiuart_if vif;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk);
            
            // Watch for memory write to tohost address
            if (vif.mem_write_enable && 
                vif.mem_write_addr == tohost_addr) begin
                
                tohost_value = vif.mem_write_data;
                tohost_written = 1;
                -> tohost_event;
                
                `uvm_info("TOHOST", 
                    $sformatf("tohost written: 0x%08x at time %0t", 
                        tohost_value, $time), UVM_MEDIUM)
                
                // Check pass/fail
                if (tohost_value == 32'h0000_0001) begin
                    `uvm_info("TOHOST", "TEST PASSED", UVM_LOW)
                end else begin
                    `uvm_error("TOHOST", 
                        $sformatf("TEST FAILED: error code %0d", tohost_value))
                end
            end
        end
    endtask
    
    // Helper: Wait for tohost with timeout
    task wait_for_tohost(int timeout_cycles);
        fork
            begin
                @(tohost_event);
            end
            begin
                repeat(timeout_cycles) @(posedge vif.clk);
                `uvm_error("TOHOST", 
                    $sformatf("Timeout waiting for tohost after %0d cycles", 
                        timeout_cycles))
            end
        join_any
        disable fork;
    endtask
endclass
```

### 2.4 VexRiscv Test Assets

**Source**: `vexriscv_reference/source/src/test/resources/`

**Available Test Programs** (180+ files):

| Category | Count | Pattern | Description |
|----------|-------|---------|-------------|
| RV32I ISA Tests | 30 | `rv32ui-p-*.hex` | Add, sub, logical, shift, branch, jump, load/store |
| Compliance Tests | 40+ | `I-*.hex` | RISC-V compliance suite |
| Benchmarks | 5 | `dhrystone*.hex`, `coremark*.hex` | Performance validation |
| Custom Tests | 10+ | `csr.hex`, `debug.hex` | VexRiscv-specific features |

**Pass/Fail Protocol**:
```assembly
# Test framework convention (from rv32ui-p-add.hex)
80000040 <write_tohost>:
    00001f17    auipc t5,0x1
    fdcf2023    sw t3,-64(t5)      # Write to 0x80001000
    ff9ff06f    j 80000040         # Infinite loop

# Result interpretation:
# tohost == 0x00000001 → PASS
# tohost != 0x00000001 → FAIL (tohost contains error code)
```

### 2.5 MCP Tool Extensions

**New MCP Tools**:

```python
# File: mcp_server/dsim_fastmcp_server.py (add new tools)

@mcp.tool()
def run_vexriscv_isa_test(
    test_name: str,
    timeout_cycles: int = 10000,
    waves: bool = False
) -> dict:
    """
    Run VexRiscv ISA test from upstream test suite.
    
    Args:
        test_name: Test name (e.g., "rv32ui-p-add")
        timeout_cycles: Maximum cycles before timeout
        waves: Enable waveform generation
    
    Returns:
        {
            "status": "pass" | "fail" | "timeout",
            "tohost_value": int,
            "cycles": int,
            "waves_file": str | null
        }
    """
    from tools.vexriscv_hex_loader import VexRiscvHexLoader
    
    # Locate hex file
    hex_file = Path("vexriscv_reference/source/src/test/resources/hex") / f"{test_name}.hex"
    if not hex_file.exists():
        return {"status": "error", "message": f"Hex file not found: {hex_file}"}
    
    # Load and translate hex file
    loader = VexRiscvHexLoader(str(hex_file), address_offset=-0x80000000)
    memory_data = loader.parse_hex()
    word_data = loader.get_word_aligned_data()
    special_addrs = loader.translate_special_addresses()
    
    # Prepare UVM configuration
    uvm_config = {
        "test_class": "vexriscv_isa_test",
        "memory_data": word_data,
        "tohost_addr": special_addrs['tohost'],
        "timeout_cycles": timeout_cycles,
        "waves": waves
    }
    
    # Execute simulation
    result = run_uvm_simulation(**uvm_config)
    
    return {
        "status": result["status"],
        "tohost_value": result.get("tohost_value", 0),
        "cycles": result.get("elapsed_cycles", 0),
        "waves_file": result.get("waves_file")
    }

@mcp.tool()
def list_vexriscv_tests(category: str = "all") -> list:
    """
    List available VexRiscv test programs.
    
    Args:
        category: "isa" | "compliance" | "benchmark" | "all"
    
    Returns:
        List of test names with descriptions
    """
    import glob
    
    test_dir = Path("vexriscv_reference/source/src/test/resources/hex")
    
    filters = {
        "isa": "rv32ui-p-*.hex",
        "compliance": "I-*.hex",
        "benchmark": "*dhrystone*.hex"
    }
    
    pattern = filters.get(category, "*.hex")
    hex_files = glob.glob(str(test_dir / pattern))
    
    tests = []
    for hex_file in hex_files:
        test_name = Path(hex_file).stem
        tests.append({
            "name": test_name,
            "file": hex_file,
            "category": category
        })
    
    return tests
```

---

## 3. Stage 1: UVM+MCP Unit Tests

**Objective**: Build basic VexRiscv test infrastructure from scratch

### 3.1 Smoke Tests (Week 1)

#### Test 1.1: Register File Read/Write
**File**: `sim/tests/vexriscv_regfile_test.sv`

**Purpose**: Verify 32×32-bit register file with zero hardwiring

**Test Implementation**:
```systemverilog
class vexriscv_regfile_test extends vexriscv_base_test;
    `uvm_component_utils(vexriscv_regfile_test)
    
    virtual task run_test_sequence();
        logic [31:0] reg_val;
        
        `uvm_info("TEST", "=== Register File Test Started ===", UVM_LOW)
        
        // Load test program
        write_cpu_memory(32'h000, 32'h00010093);  // ADDI x1, x0, 1
        write_cpu_memory(32'h004, 32'h00110113);  // ADDI x2, x2, 1
        write_cpu_memory(32'h008, 32'h00208193);  // ADDI x3, x1, 2
        write_cpu_memory(32'h00C, 32'h00000013);  // NOP
        write_cpu_memory(32'h010, 32'h00100073);  // EBREAK
        
        // Execute
        reset_cpu();
        start_cpu();
        step_cpu(5);
        halt_cpu();
        
        // Read back registers via debug interface
        read_cpu_reg(0, reg_val);
        assert_equal_32("x0 hardwired zero", reg_val, 32'h0);
        
        read_cpu_reg(1, reg_val);
        assert_equal_32("x1 = 1", reg_val, 32'h1);
        
        read_cpu_reg(2, reg_val);
        assert_equal_32("x2 = 1", reg_val, 32'h1);
        
        read_cpu_reg(3, reg_val);
        assert_equal_32("x3 = 3", reg_val, 32'h3);
        
        `uvm_info("TEST", "✓ Register file test passed", UVM_LOW)
    endtask
endclass
```

**Success Criteria**:
- x0 remains 0 (hardwired zero)
- x1, x2, x3 updated correctly
- No hazard stalls (pure ALU ops)
- Duration: ~5s

---

#### Test 1.2: Pipeline Flow
**File**: `sim/tests/vexriscv_pipeline_flow_test.sv`

**Purpose**: Verify instruction progresses through 4 pipeline stages

**Test Implementation**:
```systemverilog
class vexriscv_pipeline_flow_test extends vexriscv_base_test;
    `uvm_component_utils(vexriscv_pipeline_flow_test)
    
    virtual task run_test_sequence();
        `uvm_info("TEST", "=== Pipeline Flow Test Started ===", UVM_LOW)
        
        // Load NOP sequence (8 instructions)
        for (int i = 0; i < 8; i++) begin
            write_cpu_memory(i*4, 32'h00000013);  // ADDI x0, x0, 0 (NOP)
        end
        
        // Execute and monitor (assertions will check stage progression)
        reset_cpu();
        start_cpu();
        
        // Wait for completion (8 instructions * ~1 cycle each = ~12 cycles with startup)
        repeat(20) @(posedge vif.clk);
        
        halt_cpu();
        
        // Verify PC advanced
        logic [31:0] pc_val;
        read_cpu_pc(pc_val);
        assert(pc_val >= 32'h1C);  // At least 7 instructions executed
        
        `uvm_info("TEST", "✓ Pipeline flow test passed", UVM_LOW)
    endtask
endclass
```

**Associated Assertion** (separate module):
```systemverilog
// File: sim/assertions/spec/vexriscv_pipeline_flow_spec.sv
module vexriscv_pipeline_flow_assertions (
    input logic clk,
    input logic rst_n,
    input logic decode_arbitration_isValid,
    input logic decode_arbitration_isFiring,
    input logic execute_arbitration_isValid,
    input logic execute_arbitration_isFiring,
    input logic memory_arbitration_isValid,
    input logic memory_arbitration_isFiring,
    input logic writeBack_arbitration_isValid,
    input logic writeBack_arbitration_isFiring
);
    // Check stage progression for NOPs (no stalls)
    property pipeline_flow_nop;
        @(posedge clk) disable iff (!rst_n)
        decode_arbitration_isFiring |-> 
            ##1 execute_arbitration_isFiring ##1 
            memory_arbitration_isFiring ##1 
            writeBack_arbitration_isFiring;
    endproperty
    
    assert_pipeline_flow: assert property(pipeline_flow_nop)
        else $error("[PIPELINE] Stage progression violated");
endmodule
```

**Success Criteria**:
- Each NOP instruction takes 4 cycles (no stalls)
- PC increments by 4 each cycle
- Assertions pass

---

#### Test 1.3: Memory Access
**File**: `sim/tests/vexriscv_memory_access_test.sv`

**Purpose**: Validate load/store through DBus interface

**Test Implementation**:
```systemverilog
class vexriscv_memory_access_test extends vexriscv_base_test;
    `uvm_component_utils(vexriscv_memory_access_test)
    
    virtual task run_test_sequence();
        logic [31:0] reg_val;
        
        `uvm_info("TEST", "=== Memory Access Test Started ===", UVM_LOW)
        
        // Load test program
        write_cpu_memory(32'h000, 32'h100007b7);  // LUI x15, 0x10000
        write_cpu_memory(32'h004, 32'h0007a023);  // SW x0, 0(x15)
        write_cpu_memory(32'h008, 32'h12345537);  // LUI x10, 0x12345
        write_cpu_memory(32'h00C, 32'h67850513);  // ADDI x10, x10, 0x678
        write_cpu_memory(32'h010, 32'h00a7a023);  // SW x10, 0(x15)
        write_cpu_memory(32'h014, 32'h0007a583);  // LW x11, 0(x15)
        write_cpu_memory(32'h018, 32'h00100073);  // EBREAK
        
        // Execute
        reset_cpu();
        start_cpu();
        step_cpu(7);
        halt_cpu();
        
        // Verify loaded value
        read_cpu_reg(11, reg_val);
        assert_equal_32("x11 = 0x12345678", reg_val, 32'h12345678);
        
        `uvm_info("TEST", "✓ Memory access test passed", UVM_LOW)
    endtask
endclass
```

**Success Criteria**:
- SW writes correct value
- LW reads back correct value
- Load-use hazard detected (1 cycle stall)
- Duration: ~8s

---

### 3.2 Hazard Tests (Week 2)

#### Test 2.1: EX Stage Bypass
**File**: `sim/tests/vexriscv_ex_bypass_test.sv`

**Purpose**: Verify EX→EX forwarding (highest priority)

**Test Implementation**:
```systemverilog
class vexriscv_ex_bypass_test extends vexriscv_base_test;
    `uvm_component_utils(vexriscv_ex_bypass_test)
    
    virtual task run_test_sequence();
        logic [31:0] reg_val;
        int cycle_count_start, cycle_count_end;
        
        `uvm_info("TEST", "=== EX Bypass Test Started ===", UVM_LOW)
        
        // RAW hazard: EX stage provides data
        write_cpu_memory(32'h000, 32'h00500093);  // ADDI x1, x0, 5
        write_cpu_memory(32'h004, 32'h00108113);  // ADDI x2, x1, 1 (EX bypass)
        write_cpu_memory(32'h008, 32'h00100073);  // EBREAK
        
        // Measure cycles
        reset_cpu();
        cycle_count_start = get_cycle_count();
        start_cpu();
        step_cpu(3);
        halt_cpu();
        cycle_count_end = get_cycle_count();
        
        // Verify result
        read_cpu_reg(2, reg_val);
        assert_equal_32("x2 = 6 (forwarded)", reg_val, 32'd6);
        
        // Verify no stall (3 cycles total)
        assert((cycle_count_end - cycle_count_start) == 3);
        
        `uvm_info("TEST", "✓ EX bypass test passed (no stall)", UVM_LOW)
    endtask
endclass
```

**Associated Assertion**:
```systemverilog
// File: sim/assertions/spec/vexriscv_ex_bypass_spec.sv
property ex_bypass_no_stall;
    @(posedge clk) disable iff (!rst_n)
    (decode_RS1 == execute_RD) && execute_RD_WRITE && 
    (execute_RD != 0) && execute_arbitration_isValid
    |-> !decode_arbitration_isStuck;  // No stall with EX bypass
endproperty
```

**Success Criteria**:
- x2 = 6 (correct forwarded value)
- No pipeline stall
- Total 3 cycles

---

#### Test 2.2: MEM Stage Bypass
**File**: `sim/tests/vexriscv_mem_bypass_test.sv`

**Purpose**: Verify MEM→EX forwarding

**Test Implementation**: Similar to EX bypass but with 1 NOP delay

**Success Criteria**:
- x2 = 6 (correct forwarded value)
- No pipeline stall
- Total 4 cycles

---

#### Test 2.3: WB Stage Bypass (with Buffer)
**File**: `sim/tests/vexriscv_wb_bypass_test.sv`

**Purpose**: Verify WB→EX forwarding with bypassWriteBackBuffer

**Critical Check**: This validates the **bypassWriteBackBuffer** fix

**Test Implementation**: Similar to EX bypass but with 2 NOP delays

**Success Criteria**:
- x2 = 6 (proves bypassWriteBackBuffer works)
- **No pipeline stall** (critical - old config would stall)
- Total 5 cycles

---

#### Test 2.4: Load-Use Hazard
**File**: `sim/tests/vexriscv_load_use_stall_test.sv`

**Purpose**: Verify mandatory 1-cycle stall for load-use hazard

**Test Implementation**:
```systemverilog
class vexriscv_load_use_stall_test extends vexriscv_base_test;
    `uvm_component_utils(vexriscv_load_use_stall_test)
    
    virtual task run_test_sequence();
        logic [31:0] reg_val;
        int cycle_count_start, cycle_count_end;
        
        `uvm_info("TEST", "=== Load-Use Stall Test Started ===", UVM_LOW)
        
        // Load-use hazard
        write_cpu_memory(32'h000, 32'h00002083);  // LW x1, 0(x0)
        write_cpu_memory(32'h004, 32'h00108113);  // ADDI x2, x1, 1 (use immediately)
        write_cpu_memory(32'h008, 32'h00100073);  // EBREAK
        
        // Measure cycles
        reset_cpu();
        cycle_count_start = get_cycle_count();
        start_cpu();
        step_cpu(3);
        halt_cpu();
        cycle_count_end = get_cycle_count();
        
        // Verify result
        read_cpu_reg(2, reg_val);
        // (depends on memory content at address 0)
        
        // Verify 1-cycle stall (4 cycles total: 3 + 1 stall)
        assert((cycle_count_end - cycle_count_start) == 4);
        
        `uvm_info("TEST", "✓ Load-use stall test passed (1-cycle stall)", UVM_LOW)
    endtask
endclass
```

**Associated Assertion**:
```systemverilog
property load_use_stall;
    @(posedge clk) disable iff (!rst_n)
    (execute_arbitration_isValid && execute_IS_LOAD) &&
    (decode_arbitration_isValid && decode_RS1_USE)
    |=> decode_arbitration_isStuck;  // Must stall 1 cycle
endproperty
```

**Success Criteria**:
- Exactly 1-cycle stall detected
- Total 4 cycles (3 + 1 stall)

---

### 3.3 Bus Protocol Tests (Week 3)

#### Test 3.1: IBus Instruction Fetch
**File**: `sim/tests/vexriscv_ibus_fetch_test.sv`

**Purpose**: Verify IBusSimplePlugin behavior

**Test Implementation**: Load 8 instructions, monitor IBus valid/ready handshake

**Assertions**:
```systemverilog
// IBus valid/ready protocol
property ibus_handshake;
    @(posedge clk) disable iff (!rst_n)
    iBus_cmd_valid && !iBus_cmd_ready |=> iBus_cmd_valid;
endproperty

// PC increment by 4
property pc_increment;
    @(posedge clk) disable iff (!rst_n)
    iBus_cmd_valid && iBus_cmd_ready |=> 
        iBus_cmd_payload_pc == $past(iBus_cmd_payload_pc) + 4;
endproperty
```

**Success Criteria**:
- IBus protocol compliant
- PC increments correctly
- No fetch stalls

---

#### Test 3.2: DBus Data Access
**File**: `sim/tests/vexriscv_dbus_access_test.sv`

**Purpose**: Verify DBusSimplePlugin load/store transactions

**Test Implementation**: Test byte/halfword/word access with proper size encoding

**Success Criteria**:
- Correct byte/halfword/word access
- Proper size field encoding
- No bus errors

---

## 4. Stage 2: VexRiscv Integration Tests

**Objective**: Validate against 180+ upstream ISA tests

### 4.1 RV32I ISA Test Suite (Week 4-5)

#### Execution Method

```python
# Single test via MCP
python mcp_server/mcp_client.py --workspace . \
    --tool run_vexriscv_isa_test --test-name rv32ui-p-add

# Regression suite
python mcp_server/run_regression.py --suite vexriscv_isa_full
```

#### Test Subsets

**Subset 1: Arithmetic & Logical (10 tests)**
```
rv32ui-p-add, rv32ui-p-addi, rv32ui-p-sub,
rv32ui-p-and, rv32ui-p-andi, rv32ui-p-or, rv32ui-p-ori,
rv32ui-p-xor, rv32ui-p-xori, rv32ui-p-lui
```
**Duration**: <2 min | **Success**: All tohost = 1

**Subset 2: Shifts (6 tests)**
```
rv32ui-p-sll, rv32ui-p-slli, rv32ui-p-srl,
rv32ui-p-srli, rv32ui-p-sra, rv32ui-p-srai
```
**Duration**: <3 min | **Critical**: LightShifterPlugin (multi-cycle)

**Subset 3: Comparisons (4 tests)**
```
rv32ui-p-slt, rv32ui-p-slti, rv32ui-p-sltu, rv32ui-p-sltiu
```
**Duration**: <2 min

**Subset 4: Branches (6 tests)**
```
rv32ui-p-beq, rv32ui-p-bne, rv32ui-p-blt,
rv32ui-p-bge, rv32ui-p-bltu, rv32ui-p-bgeu
```
**Duration**: <4 min | **Critical**: earlyBranch=false (3-cycle penalty)

**Subset 5: Jumps (3 tests)**
```
rv32ui-p-jal, rv32ui-p-jalr, rv32ui-p-auipc
```
**Duration**: <2 min

**Subset 6: Load/Store (9 tests)**
```
rv32ui-p-lw, rv32ui-p-lh, rv32ui-p-lhu, rv32ui-p-lb, rv32ui-p-lbu,
rv32ui-p-sw, rv32ui-p-sh, rv32ui-p-sb
```
**Duration**: <5 min | **Critical**: Load latency (2 cycles)

---

### 4.2 Compliance Test Suite (Week 6)

**Source**: `vexriscv_reference/source/src/test/resources/hex/I-*.hex`

**Test Count**: 40+ tests

**Execution**:
```python
python mcp_server/run_regression.py --suite vexriscv_compliance
```

**Success Criteria**:
- 100% pass rate
- Total duration: <20 min

**Known Issues**:
- Address translation required (0x80000000 → 0x00000000)
- CSR pre-initialization via debug interface

---

### 4.3 Exception & Interrupt Tests (Week 7)

#### Test: EBREAK Handling
**Purpose**: Verify trap vector jump and CSR updates

**Success Criteria**:
- PC jumps to mtvec on EBREAK
- mepc = EBREAK address
- mcause = 3 (breakpoint)
- MRET returns correctly

#### Test: ECALL System Call
**Success Criteria**:
- mcause = 11 (environment call)

#### Test: External Interrupt
**Success Criteria**:
- Interrupt taken within 5 cycles
- mcause = 0x8000000B

---

## 5. Stage 3: Assertion Strategy

**Objective**: Non-intrusive debug assertions

### 5.1 Assertion Principles

**Mandatory Rules** (from `sim/assertions/forCopilot-assertions.md`):
1. **Separate Modules** - Never embed in RTL
2. **Bind Attachment** - Use bind statement
3. **Observer-Only** - No assumptions
4. **Conditional Compilation** - `+define+ENABLE_ASSERTIONS`
5. **One-Intent-One-Assertion** - Clear messages

### 5.2 Required Assertion Modules

#### Module 1: Pipeline Arbitration
**File**: `sim/assertions/spec/vexriscv_pipeline_arbitration_spec.sv`

**Checks**:
- Valid propagation
- Stuck = haltItself || haltByOther
- Firing = isValid && isMoving
- Flush propagation

#### Module 2: Hazard Plugin
**File**: `sim/assertions/spec/vexriscv_hazard_plugin_spec.sv`

**Checks**:
- RAW hazard detection
- Bypass priority (EX > MEM > WB)
- Load-use mandatory stall
- bypassWriteBackBuffer correctness

#### Module 3: Stream FIFO
**File**: `sim/assertions/spec/vexriscv_stream_fifo_spec.sv`

**Checks**:
- Valid/ready handshake
- Hold requirement
- No data change when stalled

#### Module 4: Jump Interface
**File**: `sim/assertions/spec/vexriscv_jump_arbitration_spec.sv`

**Checks**:
- Priority (Branch > CSR)
- Flush signals
- PC update

#### Module 5: RegFile Bypass
**File**: `sim/assertions/spec/vexriscv_regfile_bypass_spec.sv`

**Checks**:
- Read-after-write (SyncDR)
- x0 hardwiring
- Write enable

### 5.3 Assertion Execution

**Enable Assertions** (debug only):
```powershell
python mcp_server/mcp_client.py --tool run_uvm_simulation \
    --test-name vexriscv_smoke_test --mode compile \
    --plusarg +define+ENABLE_ASSERTIONS
```

**Performance Impact**: +19% compilation overhead

**When to Enable**:
- ❌ Normal regression (too slow)
- ✅ Debugging failures
- ✅ First-time validation
- ✅ After RTL changes

---

## 6. Test Execution Workflow

### 6.1 Quick Validation

```powershell
# 1. Check environment
.\scripts\run_test.ps1 -Help

# 2. List VexRiscv tests
Get-ChildItem sim\tests\vexriscv*.sv

# 3. Run single test
.\scripts\run_test.ps1 vexriscv_regfile_test -Verbosity UVM_LOW

# 4. With waveforms
.\scripts\run_test.ps1 vexriscv_regfile_test -Verbosity UVM_LOW -Waves
```

### 6.2 Regression Testing

```powershell
# Stage 1 regression (foundation tests)
.\scripts\run_regression.ps1 -Stage 1 -Verbosity UVM_LOW

# Run specific tests
.\scripts\run_regression.ps1 -Tests vexriscv_regfile_test,vexriscv_alu_test -Verbosity UVM_LOW
```

### 6.3 Troubleshooting

#### Issue: Test Timeout
**Debug Steps**:
1. Enable waveforms
2. Check for infinite loops
3. Verify PC advancing
4. Check pipeline stuck

#### Issue: Test Failure (tohost != 1)
**Debug Steps**:
1. Decode tohost error code
2. Check test source: `*.dump` file
3. Reproduce with assertions enabled

---

## 7. Success Criteria & Metrics

### 7.1 Stage 1 Success (Unit Tests)

| Category | Tests | Pass Rate | Duration | Status |
|----------|-------|-----------|----------|--------|
| Smoke | 3 | 100% | <15s | ⏳ Pending |
| Hazard | 4 | 100% | <25s | ⏳ Pending |
| Bus Protocol | 2 | 100% | <15s | ⏳ Pending |
| **Total** | **9** | **100%** | **<60s** | ⏳ Pending |

### 7.2 Stage 2 Success (Integration)

| Suite | Tests | Pass Rate | Duration | Status |
|-------|-------|-----------|----------|--------|
| ALU & Logic | 10 | 100% | <2 min | ⏳ Pending |
| Shifts | 6 | 100% | <3 min | ⏳ Pending |
| Comparisons | 4 | 100% | <2 min | ⏳ Pending |
| Branches | 6 | 100% | <4 min | ⏳ Pending |
| Jumps | 3 | 100% | <2 min | ⏳ Pending |
| Load/Store | 9 | 100% | <5 min | ⏳ Pending |
| Exception | 3 | 100% | <1 min | ⏳ Pending |
| Compliance | 40+ | 100% | <20 min | ⏳ Pending |
| **Total** | **81+** | **100%** | **<40 min** | ⏳ Pending |

### 7.3 Stage 3 Success (Assertions)

| Module | Checks | Bound To | Status |
|--------|--------|----------|--------|
| Pipeline Arbitration | 4 | vexriscv_wrapper | ⏳ Pending |
| Hazard Plugin | 4 | vexriscv_wrapper | ⏳ Pending |
| Stream FIFO | 3 | vexriscv_stream_fifo | ⏳ Pending |
| Jump Arbitration | 3 | vexriscv_wrapper | ⏳ Pending |
| RegFile Bypass | 3 | vexriscv_regfile | ⏳ Pending |
| **Total** | **17** | **5 modules** | ⏳ Pending |

### 7.4 Overall Metrics

**Test Coverage Goals**:
- ✅ Instruction Coverage: 100% of RV32I (40 instructions)
- ✅ Hazard Coverage: All RAW cases
- ✅ Exception Coverage: EBREAK/ECALL/interrupts/MRET
- ✅ Bus Protocol Coverage: IBus/DBus transactions

**Performance Targets**:
- Smoke suite: <2 minutes (CI-friendly)
- Full regression: <45 minutes (nightly)
- Single test: <5 seconds average

**Quality Metrics**:
- Zero UVM_FATAL/UVM_ERROR in passing tests
- 100% ISA compliance pass rate
- No assertion failures

---

## Appendices

### A. File Organization

```
sim/
├── tests/
│   ├── vexriscv_regfile_test.sv         # NEW: Stage 1.1
│   ├── vexriscv_pipeline_flow_test.sv   # NEW: Stage 1.2
│   ├── vexriscv_memory_access_test.sv   # NEW: Stage 1.3
│   ├── vexriscv_ex_bypass_test.sv       # NEW: Hazard
│   ├── vexriscv_mem_bypass_test.sv      # NEW: Hazard
│   ├── vexriscv_wb_bypass_test.sv       # NEW: Hazard
│   ├── vexriscv_load_use_stall_test.sv  # NEW: Hazard
│   ├── vexriscv_ibus_fetch_test.sv      # NEW: Bus
│   └── vexriscv_dbus_access_test.sv     # NEW: Bus
├── uvm/sv/
│   ├── vexriscv_base_test.sv            # NEW: Base class
│   └── vexriscv_tohost_monitor.sv       # NEW: Monitor
├── assertions/spec/
│   ├── vexriscv_pipeline_arbitration_spec.sv  # NEW
│   ├── vexriscv_hazard_plugin_spec.sv         # NEW
│   ├── vexriscv_stream_fifo_spec.sv           # NEW
│   ├── vexriscv_jump_arbitration_spec.sv      # NEW
│   └── vexriscv_regfile_bypass_spec.sv        # NEW
└── assertions/bind_vexriscv_*.sv              # NEW: 5 files

scripts/
├── run_test.ps1                             # Test execution
├── run_regression.ps1                       # Regression runner
└── clean_logs.ps1                           # Log cleanup
tools/
└── vexriscv_hex_loader.py                     # Hex loader
```

### B. PowerShell Script Reference

```powershell
# Check environment
.\scripts\run_test.ps1 -Help

# List tests
Get-ChildItem sim\tests\vexriscv*.sv

# Run single test
.\scripts\run_test.ps1 vexriscv_regfile_test -Verbosity UVM_LOW

# Regression
.\scripts\run_regression.ps1 -Stage 1
```

### C. References

**Key Documents**:
1. [VexRiscv Implementation Principles](vexriscv_implementation_principles.md)
2. [Assertion Guidelines](../sim/assertions/forCopilot-assertions.md)

**Upstream Resources**:
1. VexRiscv GitHub: https://github.com/SpinalHDL/VexRiscv
2. RISC-V Tests: https://github.com/riscv/riscv-tests
3. RISC-V ISA Spec: https://riscv.org/specifications/

---

**Document Status**: ✅ Complete  
**Next Action**: Create Python hex loader and UVM base test class  
**Review Date**: 2026-02-01
