# AXIUART UVM Testbench Architecture

## Overview

This document provides detailed information about the UVM (Universal Verification Methodology) testbench architecture implemented for the AXIUART project. The testbench follows standard UVM design patterns and best practices for verifying the UART-AXI4 Bridge functionality.

## Table of Contents

1. [UVM Hierarchy](#uvm-hierarchy)
2. [Component Details](#component-details)
3. [Transaction Layer](#transaction-layer)
4. [Sequence Architecture](#sequence-architecture)
5. [Verification Strategy](#verification-strategy)
6. [Phase Execution](#phase-execution)
7. [Configuration Mechanism](#configuration-mechanism)
8. [Scoreboards and Checkers](#scoreboards-and-checkers)

## UVM Hierarchy

### Component Tree Structure

```
uvm_test_top (axiuart_base_test / axiuart_basic_test / axiuart_reset_test / axiuart_reg_rw_test)
└── env (axiuart_env)
    ├── uart_agt (uart_agent)
    │   ├── driver (uart_driver)
    │   ├── monitor (uart_monitor)
    │   └── sequencer (uart_sequencer)
    │
    ├── axi_mon (axi4_lite_monitor) [optional]
    │
    └── scoreboard (axiuart_scoreboard)
        ├── axi_export (uvm_analysis_export)
        ├── axi_fifo (uvm_tlm_analysis_fifo)
        ├── uart_export (uvm_analysis_export)
        └── uart_fifo (uvm_tlm_analysis_fifo)
```

**Note**: As of December 2024 refactoring, test classes are now organized in separate files under `sim/tests/` directory for improved scalability and maintainability.

### Hierarchy Explanation

- **Test Layer**: Top-level test classes that configure and control the verification environment
- **Environment Layer**: Contains all verification components and their connections
- **Agent Layer**: Encapsulates driver, monitor, and sequencer for UART protocol
- **Verification Layer**: Scoreboard for checking functional correctness

## Component Details

### 1. Test Classes (sim/tests/ - December 2024 Refactored Structure)

**File Organization**: Each test is now in a separate file for better scalability:
- `axiuart_test_pkg.sv` - Central package including all tests
- `axiuart_base_test.sv` - Base test class
- `axiuart_basic_test.sv` - Basic connectivity test
- `axiuart_reset_test.sv` - Reset functionality test
- `axiuart_reg_rw_test.sv` - Register R/W verification test

#### axiuart_base_test

Base class providing common infrastructure for all tests.

**Key Responsibilities**:
- Environment instantiation
- Basic configuration
- Default sequence execution
- Common utility functions

**Important Methods**:
```systemverilog
function void build_phase(uvm_phase phase);
    // Create environment
    env = axiuart_env::type_id::create("env", this);
    
    // Set verbosity
    set_report_verbosity_level_hier(UVM_FULL);
endfunction

function void end_of_elaboration_phase(uvm_phase phase);
    // Print topology
    print_topology();
endfunction
```

**Configuration**:
- Sets default timeout values
- Configures report verbosity
- Initializes factory overrides if needed

#### axiuart_basic_test

Extends axiuart_base_test for basic connectivity verification.

**Test Objectives**:
- Verify reset functionality
- Execute single write transaction
- Confirm basic UART-to-AXI4 bridge operation

**Test Sequence**:
1. Raise objection to keep simulation alive
2. Execute reset sequence (100 cycles)
3. Perform single register write
4. Wait for completion
5. Drop objection to end test

**Code Flow**:
```systemverilog
task run_phase(uvm_phase phase);
    phase.raise_objection(this, "Starting basic test");
    
    // Reset sequence
    reset_seq = uart_reset_sequence::type_id::create("reset_seq");
    reset_seq.start(env.uart_agt.sequencer);
    
    // Basic write sequence
    write_seq = uart_write_sequence::type_id::create("write_seq");
    write_seq.addr = 32'h00001020;
    write_seq.data = 32'hDEADBEEF;
    write_seq.start(env.uart_agt.sequencer);
    
    #1000ns;
    phase.drop_objection(this, "Basic test completed");
endtask
```

#### axiuart_reg_rw_test

Comprehensive register read/write verification test.

**Test Objectives**:
- Verify write operations to multiple registers
- Verify read operations return correct data
- Confirm read-after-write consistency
- Validate scoreboard matching logic

**Test Coverage**:
- 5 test registers (REG_TEST_0 through REG_TEST_4)
- Address range: 0x00001020 to 0x00001040
- Various data patterns

**Test Sequence**:
```systemverilog
task run_phase(uvm_phase phase);
    phase.raise_objection(this, "Starting register R/W test");
    
    // Phase 1: Reset
    reset_seq.start(env.uart_agt.sequencer);
    
    // Phase 2: Write to all test registers
    for (int i = 0; i < 5; i++) begin
        write_seq[i] = uart_write_sequence::type_id::create($sformatf("wr_seq_%0d", i));
        write_seq[i].addr = base_addr + (i * addr_stride);
        write_seq[i].data = test_pattern[i];
        write_seq[i].start(env.uart_agt.sequencer);
    end
    
    // Phase 3: Read back and verify
    for (int i = 0; i < 5; i++) begin
        read_seq[i] = uart_read_sequence::type_id::create($sformatf("rd_seq_%0d", i));
        read_seq[i].addr = base_addr + (i * addr_stride);
        read_seq[i].start(env.uart_agt.sequencer);
    end
    
    // Phase 4: Check scoreboard results
    #2ms;
    check_scoreboard_results();
    
    phase.drop_objection(this, "Register R/W test completed");
endtask
```

### 2. Environment (axiuart_env.sv)

The environment is the top-level container for all verification components.

**Key Responsibilities**:
- Component instantiation
- Connection establishment
- Configuration propagation
- Interface assignment

**Build Phase Activities**:
```systemverilog
function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    // Create agent
    uart_agt = uart_agent::type_id::create("uart_agt", this);
    
    // Create scoreboard
    scoreboard = axiuart_scoreboard::type_id::create("scoreboard", this);
    
    // Get virtual interfaces
    if (!uvm_config_db#(virtual uart_if)::get(this, "", "uart_vif", uart_vif))
        `uvm_fatal("ENV", "Cannot get UART virtual interface")
    
    if (!uvm_config_db#(virtual axi4_lite_if)::get(this, "", "axi_vif", axi_vif)) begin
        `uvm_warning("ENV", "AXI interface not found - disabling AXI monitor")
        has_axi_monitor = 0;
    end
    
    // Set interfaces for agent
    uvm_config_db#(virtual uart_if)::set(this, "uart_agt*", "vif", uart_vif);
endfunction
```

**Connect Phase Activities**:
```systemverilog
function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    
    // Connect monitor to scoreboard
    uart_agt.monitor.analysis_port.connect(scoreboard.uart_export);
    `uvm_info("ENV", "Connected Monitor -> Scoreboard (uart_export)", UVM_LOW)
    
    // Connect driver to scoreboard (for write tracking)
    uart_agt.driver.axi_write_port.connect(scoreboard.axi_export);
    `uvm_info("ENV", "Connected Driver -> Scoreboard (axi_export)", UVM_LOW)
    
    // Optional: Connect AXI monitor if available
    if (has_axi_monitor) begin
        axi_mon.analysis_port.connect(scoreboard.axi_export);
    end
endfunction
```

**Configuration Options**:
- `has_axi_monitor`: Enable/disable AXI4-Lite monitoring
- `uart_vif`: UART virtual interface handle
- `axi_vif`: AXI4-Lite virtual interface handle

### 3. UART Agent (uart_agent.sv)

The agent encapsulates the driver, monitor, and sequencer for UART protocol operations.

**Agent Types**:
- **Active Agent**: Contains driver, monitor, and sequencer
- **Passive Agent**: Contains only monitor (not used in current implementation)

**Configuration**:
```systemverilog
typedef enum {UVM_ACTIVE, UVM_PASSIVE} uvm_active_passive_enum;
uvm_active_passive_enum is_active = UVM_ACTIVE;
```

**Component Instantiation**:
```systemverilog
function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    // Always create monitor
    monitor = uart_monitor::type_id::create("monitor", this);
    
    if (is_active == UVM_ACTIVE) begin
        driver = uart_driver::type_id::create("driver", this);
        sequencer = uart_sequencer::type_id::create("sequencer", this);
    end
    
    // Get virtual interface
    if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
        `uvm_fatal("AGENT", "Cannot get virtual interface")
        
    uvm_config_db#(virtual uart_if)::set(this, "*", "vif", vif);
endfunction
```

**Connection Phase**:
```systemverilog
function void connect_phase(uvm_phase phase);
    if (is_active == UVM_ACTIVE) begin
        driver.seq_item_port.connect(sequencer.seq_item_export);
    end
endfunction
```

### 4. UART Driver (uart_driver.sv)

The driver converts high-level transactions into pin-level activity on the UART interface.

**Key Responsibilities**:
- Receive transactions from sequencer
- Drive UART RX signals (from testbench perspective)
- Handle reset conditions
- Broadcast write transactions to scoreboard

**Main Process Flow**:
```systemverilog
task run_phase(uvm_phase phase);
    forever begin
        seq_item_port.get_next_item(req);
        
        case (req.cmd)
            CMD_RESET:  drive_reset();
            CMD_WRITE:  drive_write(req);
            CMD_READ:   drive_read(req);
            default:    `uvm_error("UART_DRIVER", "Unknown command")
        endcase
        
        seq_item_port.item_done();
    end
endtask
```

**Reset Handling**:
```systemverilog
task drive_reset();
    `uvm_info("UART_DRIVER", $sformatf("Executing reset: %0d cycles", req.reset_cycles), UVM_LOW)
    
    vif.rx = 1'b1;  // UART idle state
    repeat(req.reset_cycles) @(posedge vif.clk);
    
    `uvm_info("UART_DRIVER", "Reset completed", UVM_LOW)
endtask
```

**Write Transaction**:
```systemverilog
task drive_write(uart_transaction req);
    // Construct frame: [SOF][CMD][ADDR][DATA][CRC]
    byte_stream = build_frame(CMD_WRITE, req.addr, req.data);
    
    // Drive each byte via UART
    foreach(byte_stream[i]) begin
        drive_uart_byte(byte_stream[i]);
    end
    
    // Broadcast to scoreboard for verification
    axi_write_port.write(req);
    `uvm_info("UART_DRIVER", $sformatf("Broadcasted WRITE to Scoreboard: ADDR=0x%08h DATA=0x%08h", 
              req.addr, req.data), UVM_LOW)
endtask
```

**Read Transaction**:
```systemverilog
task drive_read(uart_transaction req);
    // Construct frame: [SOF][CMD][ADDR][CRC]
    byte_stream = build_frame(CMD_READ, req.addr);
    
    // Drive each byte via UART
    foreach(byte_stream[i]) begin
        drive_uart_byte(byte_stream[i]);
    end
    
    // Note: Read response will be captured by monitor
endtask
```

**UART Byte Transmission**:
```systemverilog
task drive_uart_byte(byte data);
    // Start bit
    vif.rx = 1'b0;
    repeat(uart_bit_cycles) @(posedge vif.clk);
    
    // Data bits (LSB first)
    for (int i = 0; i < 8; i++) begin
        vif.rx = data[i];
        repeat(uart_bit_cycles) @(posedge vif.clk);
    end
    
    // Stop bit
    vif.rx = 1'b1;
    repeat(uart_bit_cycles) @(posedge vif.clk);
endtask
```

**Analysis Port**:
- `axi_write_port`: Broadcasts write transactions to scoreboard for tracking

### 5. UART Monitor (uart_monitor.sv)

The monitor observes the UART TX line and reconstructs transactions.

**Key Responsibilities**:
- Capture UART TX bytes
- Reconstruct protocol frames
- Extract transaction information
- Broadcast transactions to scoreboard

**Monitoring Process**:
```systemverilog
task run_phase(uvm_phase phase);
    forever begin
        // Wait for start bit
        wait_for_start_bit();
        
        // Capture byte
        captured_byte = capture_uart_byte();
        
        // Process based on protocol state machine
        process_byte(captured_byte);
        
        // If complete transaction received, broadcast it
        if (transaction_complete) begin
            analysis_port.write(monitored_transaction);
        end
    end
endtask
```

**Byte Capture**:
```systemverilog
function byte capture_uart_byte();
    byte data;
    
    // Sample at middle of each bit period
    for (int i = 0; i < 8; i++) begin
        repeat(uart_bit_cycles) @(posedge vif.clk);
        data[i] = vif.tx;
    end
    
    // Wait for stop bit
    repeat(uart_bit_cycles) @(posedge vif.clk);
    if (vif.tx !== 1'b1)
        `uvm_warning("UART_MONITOR", "Invalid stop bit detected")
    
    return data;
endfunction
```

**Frame Processing**:
```systemverilog
task process_byte(byte data);
    case (frame_state)
        WAIT_SOF: begin
            if (data == SOF_BYTE) begin
                frame_state = WAIT_STATUS;
                byte_count = 0;
            end
        end
        
        WAIT_STATUS: begin
            frame_buffer[byte_count++] = data;
            status = data;
            frame_state = WAIT_CMD;
        end
        
        WAIT_CMD: begin
            frame_buffer[byte_count++] = data;
            command = data;
            frame_state = (command[7]) ? WAIT_ADDR : WAIT_CRC;
        end
        
        // Additional states for ADDR, DATA, CRC...
    endcase
endtask
```

**Transaction Broadcasting**:
```systemverilog
function void broadcast_transaction();
    uart_transaction trans;
    trans = uart_transaction::type_id::create("monitored_trans");
    
    if (command == CMD_WRITE_ACK) begin
        trans.cmd = CMD_WRITE;
        trans.status = status;
        `uvm_info("UART_MONITOR", $sformatf("WRITE_ACK: STATUS=0x%02h CMD=0x%02h CRC=0x%02h",
                  status, command, crc), UVM_LOW)
    end
    else if (command[7:4] == 4'hA) begin  // Read response
        trans.cmd = CMD_READ;
        trans.addr = {frame_buffer[2], frame_buffer[3], frame_buffer[4], frame_buffer[5]};
        trans.data = {frame_buffer[6], frame_buffer[7], frame_buffer[8], frame_buffer[9]};
        trans.status = status;
        `uvm_info("UART_MONITOR", $sformatf("READ_RESP: STATUS=0x%02h ADDR=0x%08h DATA=0x%08h CRC=0x%02h",
                  status, trans.addr, trans.data, crc), UVM_LOW)
    end
    
    analysis_port.write(trans);
endfunction
```

### 6. UART Sequencer (uart_sequencer.sv)

Standard UVM sequencer for uart_transaction objects.

```systemverilog
class uart_sequencer extends uvm_sequencer#(uart_transaction);
    `uvm_component_utils(uart_sequencer)
    
    function new(string name = "uart_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
```

## Transaction Layer

### uart_transaction (uart_transaction.sv)

Base transaction class for all UART operations.

**Transaction Fields**:
```systemverilog
class uart_transaction extends uvm_sequence_item;
    // Command type
    rand uart_cmd_e cmd;
    
    // Address and data
    rand bit [31:0] addr;
    rand bit [31:0] data;
    
    // Control fields
    rand int reset_cycles;
    
    // Status
    bit [7:0] status;
    
    `uvm_object_utils_begin(uart_transaction)
        `uvm_field_enum(uart_cmd_e, cmd, UVM_ALL_ON)
        `uvm_field_int(addr, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(data, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(reset_cycles, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(status, UVM_ALL_ON | UVM_HEX)
    `uvm_object_utils_end
    
    // Constraints
    constraint valid_addr_c {
        addr inside {[32'h00001000:32'h00001FFF]};  // Register address range
    }
    
    constraint reasonable_reset_c {
        reset_cycles inside {[10:1000]};
    }
endclass
```

**Command Types**:
```systemverilog
typedef enum {
    CMD_RESET,
    CMD_WRITE,
    CMD_READ,
    CMD_WRITE_ACK,
    CMD_READ_RESP
} uart_cmd_e;
```

**Utility Methods**:
```systemverilog
function string convert2string();
    return $sformatf("CMD=%s ADDR=0x%08h DATA=0x%08h STATUS=0x%02h",
                     cmd.name(), addr, data, status);
endfunction

function void do_copy(uvm_object rhs);
    uart_transaction rhs_;
    if (!$cast(rhs_, rhs))
        `uvm_fatal("UART_TRANSACTION", "Cast failed in do_copy")
    
    super.do_copy(rhs);
    this.cmd = rhs_.cmd;
    this.addr = rhs_.addr;
    this.data = rhs_.data;
    this.reset_cycles = rhs_.reset_cycles;
    this.status = rhs_.status;
endfunction
```

## Sequence Architecture

### Base Sequences

#### uart_reset_sequence (uart_reset_sequence.sv)

Generates reset transaction for DUT initialization.

```systemverilog
class uart_reset_sequence extends uvm_sequence#(uart_transaction);
    `uvm_object_utils(uart_reset_sequence)
    
    rand int reset_cycles;
    
    constraint default_reset_c {
        reset_cycles == 100;
    }
    
    task body();
        uart_transaction req;
        req = uart_transaction::type_id::create("req");
        
        start_item(req);
        assert(req.randomize() with {
            cmd == CMD_RESET;
            reset_cycles == local::reset_cycles;
        });
        `uvm_info("uart_reset_sequence", $sformatf("Executing reset sequence: %0d cycles", reset_cycles), UVM_LOW)
        finish_item(req);
        
        `uvm_info("uart_reset_sequence", "Reset sequence completed", UVM_LOW)
    endtask
endclass
```

#### uart_write_sequence (uart_reg_sequences.sv)

Generates write transaction to specified address.

```systemverilog
class uart_write_sequence extends uvm_sequence#(uart_transaction);
    `uvm_object_utils(uart_write_sequence)
    
    rand bit [31:0] addr;
    rand bit [31:0] data;
    
    task body();
        uart_transaction req;
        req = uart_transaction::type_id::create("req");
        
        start_item(req);
        assert(req.randomize() with {
            cmd == CMD_WRITE;
            addr == local::addr;
            data == local::data;
        });
        `uvm_info("REG_WR_SEQ", $sformatf("Writing addr=0x%08h data=0x%08h", addr, data), UVM_LOW)
        finish_item(req);
    endtask
endclass
```

#### uart_read_sequence (uart_reg_sequences.sv)

Generates read transaction from specified address.

```systemverilog
class uart_read_sequence extends uvm_sequence#(uart_transaction);
    `uvm_object_utils(uart_read_sequence)
    
    rand bit [31:0] addr;
    
    task body();
        uart_transaction req;
        req = uart_transaction::type_id::create("req");
        
        start_item(req);
        assert(req.randomize() with {
            cmd == CMD_READ;
            addr == local::addr;
        });
        `uvm_info("REG_RD_SEQ", $sformatf("Reading from addr=0x%08h", addr), UVM_LOW)
        finish_item(req);
    endtask
endclass
```

### Sequence Library Pattern

Sequences can be organized into libraries for complex test scenarios:

```systemverilog
class uart_sequence_lib extends uvm_sequence_library#(uart_transaction);
    `uvm_object_utils(uart_sequence_lib)
    `uvm_sequence_library_utils(uart_sequence_lib)
    
    function new(string name = "uart_sequence_lib");
        super.new(name);
        init_sequence_library();
        
        // Register sequences
        add_typewide_sequence(uart_write_sequence::get_type());
        add_typewide_sequence(uart_read_sequence::get_type());
    endfunction
endclass
```

## Verification Strategy

### Scoreboard Architecture

The scoreboard implements transaction-level verification using reference model approach.

**Verification Flow**:
1. **Write Phase**: Track all write transactions (address + data)
2. **Read Phase**: Compare read responses against tracked writes
3. **Match Reporting**: Report matches and mismatches

**Data Structures**:
```systemverilog
class axiuart_scoreboard extends uvm_scoreboard;
    // Write tracking
    bit [31:0] write_data_queue[bit [31:0]];  // Associative array: addr -> data
    int write_count;
    
    // Read tracking
    int read_count;
    int match_count;
    int mismatch_count;
    
    // TLM interfaces
    uvm_analysis_export #(uart_transaction) uart_export;
    uvm_analysis_export #(uart_transaction) axi_export;
    
    uvm_tlm_analysis_fifo #(uart_transaction) uart_fifo;
    uvm_tlm_analysis_fifo #(uart_transaction) axi_fifo;
endclass
```

**Write Transaction Processing**:
```systemverilog
task process_axi_transactions();
    uart_transaction trans;
    forever begin
        axi_fifo.get(trans);
        
        if (trans.cmd == CMD_WRITE) begin
            // Store write for later verification
            write_data_queue[trans.addr] = trans.data;
            write_count++;
            `uvm_info("SCOREBOARD", $sformatf("Write tracked: ADDR=0x%08h DATA=0x%08h (total: %0d)",
                      trans.addr, trans.data, write_count), UVM_LOW)
        end
    end
endtask
```

**Read Response Verification**:
```systemverilog
task process_uart_transactions();
    uart_transaction trans;
    forever begin
        uart_fifo.get(trans);
        
        if (trans.cmd == CMD_READ) begin
            read_count++;
            
            // Check if we have a matching write
            if (write_data_queue.exists(trans.addr)) begin
                bit [31:0] expected_data = write_data_queue[trans.addr];
                
                if (trans.data == expected_data) begin
                    match_count++;
                    `uvm_info("SCOREBOARD", $sformatf("READ MATCH: ADDR=0x%08h Expected=0x%08h Got=0x%08h",
                              trans.addr, expected_data, trans.data), UVM_LOW)
                end
                else begin
                    mismatch_count++;
                    `uvm_error("SCOREBOARD", $sformatf("READ MISMATCH: ADDR=0x%08h Expected=0x%08h Got=0x%08h",
                               trans.addr, expected_data, trans.data))
                end
            end
            else begin
                `uvm_warning("SCOREBOARD", $sformatf("Read from unwritten address: 0x%08h", trans.addr))
            end
        end
    end
endtask
```

**Final Report**:
```systemverilog
function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    
    `uvm_info("SCOREBOARD", "=== Final Register R/W Verification Results ===", UVM_LOW)
    `uvm_info("SCOREBOARD", $sformatf("Total Writes: %0d", write_count), UVM_LOW)
    `uvm_info("SCOREBOARD", $sformatf("Total Reads:  %0d", read_count), UVM_LOW)
    `uvm_info("SCOREBOARD", $sformatf("MATCHES:      %0d", match_count), UVM_LOW)
    `uvm_info("SCOREBOARD", $sformatf("MISMATCHES:   %0d", mismatch_count), UVM_LOW)
    
    if (mismatch_count == 0 && match_count > 0) begin
        `uvm_info("SCOREBOARD", "*** TEST PASSED ***", UVM_LOW)
    end
    else if (mismatch_count > 0) begin
        `uvm_error("SCOREBOARD", "*** TEST FAILED - MISMATCHES DETECTED ***")
    end
    else begin
        `uvm_warning("SCOREBOARD", "*** NO VERIFICATION PERFORMED ***")
    end
endfunction
```

### Coverage Strategy

Functional coverage can be added to track verification completeness:

```systemverilog
covergroup uart_transaction_cg;
    // Command coverage
    cmd_cp: coverpoint trans.cmd {
        bins write = {CMD_WRITE};
        bins read  = {CMD_READ};
        bins reset = {CMD_RESET};
    }
    
    // Address coverage
    addr_cp: coverpoint trans.addr {
        bins reg_test_0 = {32'h00001020};
        bins reg_test_1 = {32'h00001024};
        bins reg_test_2 = {32'h00001028};
        bins reg_test_3 = {32'h0000102C};
        bins reg_test_4 = {32'h00001040};
        bins other_regs = default;
    }
    
    // Cross coverage
    cmd_addr_cross: cross cmd_cp, addr_cp;
endgroup
```

## Phase Execution

### UVM Phase Overview

The testbench executes through standard UVM phases in the following order:

1. **Build Phase**: Component construction and configuration
2. **Connect Phase**: Connection establishment between components
3. **End of Elaboration Phase**: Final checks and printing
4. **Start of Simulation Phase**: Pre-simulation initialization
5. **Run Phase**: Main simulation execution
   - Reset Phase
   - Configure Phase
   - Main Phase
   - Shutdown Phase
6. **Extract Phase**: Data extraction for reporting
7. **Check Phase**: Final checks
8. **Report Phase**: Results reporting
9. **Final Phase**: Cleanup

### Phase Details

#### Build Phase

Component creation and configuration retrieval:

```systemverilog
function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    // Create components
    env = axiuart_env::type_id::create("env", this);
    
    // Retrieve configuration
    if (!uvm_config_db#(virtual uart_if)::get(this, "", "uart_vif", uart_vif))
        `uvm_fatal("BUILD", "Cannot get UART interface")
    
    // Set configuration for sub-components
    uvm_config_db#(virtual uart_if)::set(this, "env.uart_agt*", "vif", uart_vif);
endfunction
```

#### Connect Phase

TLM port connections:

```systemverilog
function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    
    // Connect analysis ports
    monitor.analysis_port.connect(scoreboard.uart_export);
    driver.axi_write_port.connect(scoreboard.axi_export);
endfunction
```

#### Run Phase

Main test execution with objections:

```systemverilog
task run_phase(uvm_phase phase);
    // Raise objection to prevent phase from ending
    phase.raise_objection(this, "Test starting");
    
    // Execute test sequences
    run_test_sequences();
    
    // Wait for completion
    #1us;
    
    // Drop objection to allow phase to end
    phase.drop_objection(this, "Test completed");
endtask
```

### Objection Mechanism

Objections control phase execution timing:

**Raising Objections**:
```systemverilog
// In test
phase.raise_objection(this, "Starting register test");

// In sequence
starting_phase.raise_objection(this);
```

**Dropping Objections**:
```systemverilog
// In test
phase.drop_objection(this, "Test finished");

// In sequence
starting_phase.drop_objection(this);
```

**Objection Counting**:
- Phase waits until all objections are dropped
- Each raise must have corresponding drop
- Drain time allows final activity to complete

## Configuration Mechanism

### Configuration Database Usage

The UVM configuration database provides hierarchical configuration:

**Setting Configuration**:
```systemverilog
// In testbench top or test
uvm_config_db#(virtual uart_if)::set(null, "uvm_test_top.env.uart_agt*", "vif", uart_vif);
uvm_config_db#(int)::set(null, "uvm_test_top", "timeout_cycles", 1000000);
```

**Getting Configuration**:
```systemverilog
// In component
if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
    `uvm_fatal("CONFIG", "Cannot get virtual interface")

uvm_config_db#(int)::get(this, "", "timeout_cycles", timeout);
```

### Virtual Interface Passing

Virtual interfaces must be passed through configuration database:

```systemverilog
// In testbench top
initial begin
    uvm_config_db#(virtual uart_if)::set(null, "*", "uart_vif", uart_if_inst);
    uvm_config_db#(virtual axi4_lite_if)::set(null, "*", "axi_vif", axi_if_inst);
    
    run_test();
end
```

## Scoreboards and Checkers

### Transaction-Level Checking

The scoreboard uses associative arrays for efficient lookup:

```systemverilog
// Write tracking
bit [31:0] expected_data[bit [31:0]];  // addr -> data mapping

// Store write
expected_data[write_addr] = write_data;

// Verify read
if (expected_data.exists(read_addr)) begin
    if (read_data == expected_data[read_addr])
        // MATCH
    else
        // MISMATCH
end
```

### Assertion-Based Checking

Protocol assertions can be added for additional checking:

```systemverilog
// In interface or monitor
property uart_start_bit;
    @(posedge clk) $fell(rx) |-> ##[uart_bit_cycles] (rx == data_bit);
endproperty

assert property (uart_start_bit)
    else `uvm_error("UART_MONITOR", "Start bit violation")
```

## Best Practices

### 1. Objection Management
- Always pair raise/drop objections
- Use descriptive objection messages
- Consider using objection callbacks for debugging

### 2. Message Reporting
- Use appropriate severity levels (INFO, WARNING, ERROR, FATAL)
- Include context in messages (addresses, data values)
- Use consistent message IDs

### 3. Transaction Recording
- Implement do_record() for transaction recording
- Enable transaction recording for debug

### 4. Reusability
- Make components configurable
- Use factory pattern for type overrides
- Keep interfaces generic

### 5. Debugging
- Print topology in end_of_elaboration
- Use verbosity levels appropriately
- Enable objection trace for phase debugging

## References

- UVM 1.2 User Guide
- Accellera UVM Reference Manual
- Project-specific documentation: `../docs/uvm_testbench_architecture.md`

## Revision History

- Version 1.0 - Initial documentation (December 14, 2025)
