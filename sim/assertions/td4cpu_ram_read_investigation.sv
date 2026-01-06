`timescale 1ns / 1ps

// ========================================
// RAM Read Operation Investigation Module
// ========================================
// Purpose: Systematic investigation of RAM read path failures
// Focuses on: Control conflicts, timing, address propagation
//
// Known Bug: Lines 715 and 753 in td4cpu_core.sv assign to ram_rd_en
//            in the same always_ff block, causing last assignment to win
//
// Investigation Areas:
// 1. ram_rd_en assignment conflicts (run vs debug operations)
// 2. ram_addr_next timing and propagation
// 3. ram_rd_data capture sequence
// 4. mem_busy_q and mem_data_valid handshake
// ========================================

module td4cpu_ram_read_investigation (
    input logic clk,
    input logic rst,
    
    // CPU state
    input logic        halted,
    input logic        running,
    input logic [15:0] pc,
    
    // Debug control pulses
    input logic        dbg_run_req_pulse,
    input logic        dbg_halt_req_pulse,
    input logic        dbg_step_req_pulse,
    
    // Debug memory interface
    input logic [15:0] dbg_mem_addr,
    input logic [15:0] dbg_mem_rdata,
    input logic [15:0] dbg_mem_wdata,
    input logic        dbg_mem_read_req_pulse,
    input logic        dbg_mem_write_req_pulse,
    input logic        dbg_mem_busy,
    input logic        dbg_mem_err,
    
    // RAM control signals (CRITICAL for investigation)
    input logic        ram_rd_en,
    input logic [15:0] ram_addr_next,
    input logic [15:0] ram_addr_reg,
    input logic [15:0] ram_rd_data,
    input logic        ram_wr_en,
    input logic [15:0] ram_wr_addr,
    input logic [15:0] ram_wr_data,
    
    // Internal state signals
    input logic        mem_busy_q,
    input logic        mem_data_valid,
    input logic [15:0] dbg_mem_addr_latched,
    
    // Instruction fetch signals (for conflict detection)
    input logic        insn_valid,
    input logic [15:0] insn
);

    // ========================================
    // Investigation State Tracking
    // ========================================
    
    typedef enum logic [2:0] {
        IDLE,
        READ_REQUESTED,
        READ_CYCLE1_EXPECT_RD_EN,
        READ_CYCLE2_WAIT_DATA,
        READ_COMPLETE,
        READ_ERROR
    } ram_read_fsm_t;
    
    ram_read_fsm_t read_fsm;
    
    // Capture request parameters
    logic [15:0] req_addr;
    logic [15:0] expected_data;
    logic [63:0] req_timestamp;
    
    // Track last operations (for conflict detection)
    logic [15:0] last_fetch_addr;
    logic [15:0] last_write_addr;
    logic [15:0] last_debug_write_addr;
    
    // Conflict detection flags
    logic conflict_run_debug;
    logic conflict_fetch_debug;
    logic pollution_from_fetch;
    logic pollution_from_write;
    
    // ========================================
    // CRITICAL BUG TRACKING: Assignment Conflict
    // Lines 715 (run handler) and 753 (debug read) both assign ram_rd_en
    // ========================================
    
    logic dbg_read_should_trigger;   // Debug read SHOULD set ram_rd_en
    logic run_would_clear;            // Run handler WOULD clear ram_rd_en
    logic assignment_conflict_detected;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            dbg_read_should_trigger <= 1'b0;
            run_would_clear <= 1'b0;
            assignment_conflict_detected <= 1'b0;
        end else begin
            // Detect cycle where both assignments could execute
            dbg_read_should_trigger <= (dbg_mem_read_req_pulse && halted);
            run_would_clear <= (running && !halted);
            
            // CRITICAL: Detect if both conditions true in same cycle
            if (dbg_read_should_trigger && run_would_clear) begin
                assignment_conflict_detected <= 1'b1;
                $error("[RAM_READ_INVEST] @%0t ASSIGNMENT CONFLICT: Both line 715 and 753 executing in same cycle!", $time);
                $error("[RAM_READ_INVEST]   running=%0b, halted=%0b, dbg_mem_read_req_pulse=%0b", 
                       running, halted, dbg_mem_read_req_pulse);
            end else begin
                assignment_conflict_detected <= 1'b0;
            end
        end
    end
    
    // ========================================
    // FSM State Tracking and Display
    // ========================================
    
    always_ff @(posedge clk) begin
        if (rst) begin
            read_fsm <= IDLE;
            req_addr <= 16'h0;
            req_timestamp <= 64'h0;
            last_fetch_addr <= 16'h0;
            last_write_addr <= 16'h0;
            last_debug_write_addr <= 16'h0;
            conflict_run_debug <= 1'b0;
            conflict_fetch_debug <= 1'b0;
            pollution_from_fetch <= 1'b0;
            pollution_from_write <= 1'b0;
        end else begin
            // Track background operations
            if (insn_valid) begin
                last_fetch_addr <= pc;
            end
            if (ram_wr_en && !halted) begin
                last_write_addr <= ram_wr_addr;
            end
            if (dbg_mem_write_req_pulse && halted) begin
                last_debug_write_addr <= dbg_mem_addr;
            end
            
            // FSM state transitions
            case (read_fsm)
                IDLE: begin
                    if (dbg_mem_read_req_pulse && halted) begin
                        read_fsm <= READ_REQUESTED;
                        req_addr <= dbg_mem_addr;
                        req_timestamp <= $time;
                        
                        // Verbose logging disabled - reduce log output
                        // $display("================================================================================");
                        // $display("[RAM_READ_INVEST] @%0t READ REQUEST START", $time);
                        // $display("  Requested Address: 0x%04h", dbg_mem_addr);
                        // $display("  CPU State: halted=%0b, running=%0b, mem_busy_q=%0b", halted, running, mem_busy_q);
                        // $display("  Conflict Check:");
                        // $display("    - Running: %0b (would clear ram_rd_en at line 715)", running);
                        // $display("    - Debug Read: %0b (should set ram_rd_en at line 753)", dbg_mem_read_req_pulse);
                        
                        // Detect potential conflicts
                        if (running && !halted) begin
                            conflict_run_debug <= 1'b1;
                            $warning("[RAM_READ_INVEST]   *** CONFLICT: CPU running during debug read request! ***");
                        end else begin
                            conflict_run_debug <= 1'b0;
                        end
                    end
                end
                
                READ_REQUESTED: begin
                    read_fsm <= READ_CYCLE1_EXPECT_RD_EN;
                    
                    // Verbose logging disabled - reduce log output
                    // $display("[RAM_READ_INVEST] @%0t READ CYCLE 1 - Checking Control Signals", $time);
                    // $display("  Expected: ram_rd_en=1, mem_busy_q=1, ram_addr_next=0x%04h", req_addr);
                    // $display("  Actual:   ram_rd_en=%0b, mem_busy_q=%0b, ram_addr_next=0x%04h", 
                    //          ram_rd_en, mem_busy_q, ram_addr_next);
                    
                    // Check ram_rd_en (CRITICAL)
                    if (!ram_rd_en) begin
                        $error("[RAM_READ_INVEST]   *** BUG: ram_rd_en=0 (should be 1) ***");
                        $error("[RAM_READ_INVEST]   Likely cause: Multiple assignments in always_ff block");
                        $error("[RAM_READ_INVEST]   Check: Halt handler (~L718), Run handler (~L734), LD instruction (~L1195)");
                        $error("[RAM_READ_INVEST]   All must check ram_read_phase before clearing ram_rd_en");
                        read_fsm <= READ_ERROR;
                    end
                    
                    // Check address propagation
                    if (ram_addr_next != req_addr) begin
                        $error("[RAM_READ_INVEST]   *** BUG: ram_addr_next mismatch ***");
                        $error("[RAM_READ_INVEST]   Expected: 0x%04h, Got: 0x%04h", req_addr, ram_addr_next);
                        
                        // Pollution detection
                        if (ram_addr_next == last_fetch_addr) begin
                            pollution_from_fetch <= 1'b1;
                            $error("[RAM_READ_INVEST]   Polluted by instruction fetch: 0x%04h", last_fetch_addr);
                        end
                        if (ram_addr_next == last_write_addr) begin
                            pollution_from_write <= 1'b1;
                            $error("[RAM_READ_INVEST]   Polluted by last write: 0x%04h", last_write_addr);
                        end
                        if (ram_addr_next == last_debug_write_addr) begin
                            $error("[RAM_READ_INVEST]   Polluted by last debug write: 0x%04h", last_debug_write_addr);
                        end
                        
                        read_fsm <= READ_ERROR;
                    end
                    
                    // Check mem_busy_q
                    if (!mem_busy_q) begin
                        $warning("[RAM_READ_INVEST]   mem_busy_q=0 (expected 1)");
                    end
                end
                
                READ_CYCLE1_EXPECT_RD_EN: begin
                    if (ram_rd_en) begin
                        read_fsm <= READ_CYCLE2_WAIT_DATA;
                        // Verbose logging disabled
                        // $display("[RAM_READ_INVEST] @%0t READ CYCLE 2 - RAM Access", $time);
                        // $display("  RAM Address: 0x%04h (ram_addr_next)", ram_addr_next);
                        // $display("  RAM will output to ram_rd_data next cycle");
                    end else begin
                        // Verbose logging disabled
                        // $display("[RAM_READ_INVEST] @%0t READ CYCLE 2 - ram_rd_en already cleared", $time);
                        read_fsm <= READ_CYCLE2_WAIT_DATA;
                    end
                end
                
                READ_CYCLE2_WAIT_DATA: begin
                    if (mem_data_valid) begin
                        read_fsm <= READ_COMPLETE;
                        
                        // Verbose logging disabled
                        // $display("[RAM_READ_INVEST] @%0t READ COMPLETE", $time);
                        // $display("  Duration: %0d ns", $time - req_timestamp);
                        // $display("  Captured Data: ram_rd_data=0x%04h", ram_rd_data);
                        // $display("  Returned to UART: dbg_mem_rdata=0x%04h", dbg_mem_rdata);
                        
                        if (ram_rd_data != dbg_mem_rdata) begin
                            $error("[RAM_READ_INVEST]   *** Data mismatch between RAM and debug interface! ***");
                        end
                        // $display("================================================================================");
                    end else begin
                        // Verbose logging disabled - waiting for data
                        // $display("[RAM_READ_INVEST] @%0t READ CYCLE 3+ - Waiting for data", $time);
                        // $display("  ram_rd_data=0x%04h, mem_data_valid=%0b, mem_busy_q=%0b",
                        //          ram_rd_data, mem_data_valid, mem_busy_q);
                    end
                end
                
                READ_COMPLETE: begin
                    read_fsm <= IDLE;
                end
                
                READ_ERROR: begin
                    // Verbose logging disabled
                    // $display("[RAM_READ_INVEST] @%0t READ ERROR - Aborting", $time);
                    // $display("================================================================================");
                    read_fsm <= IDLE;
                end
            endcase
        end
    end
    
    // ========================================
    // ASSERTION 1: ram_rd_en MUST be 1 after debug read request
    // ========================================
    
    property p_ram_rd_en_after_debug_read;
        @(posedge clk) disable iff (rst)
        (dbg_mem_read_req_pulse && halted) |=> ram_rd_en;
    endproperty
    
    assert property (p_ram_rd_en_after_debug_read) else begin
        $error("[ASSERT_RAM_READ] ram_rd_en=0 after debug read request (CRITICAL BUG)");
        $error("[ASSERT_RAM_READ] Check td4cpu_core.sv for ram_rd_en assignments during halted state");
        $error("[ASSERT_RAM_READ] All assignments must respect ram_read_phase flag");
    end
    
    // ========================================
    // ASSERTION 2: No simultaneous run and debug read
    // ========================================
    
    property p_no_run_debug_conflict;
        @(posedge clk) disable iff (rst)
        !(dbg_mem_read_req_pulse && running && !halted);
    endproperty
    
    assert property (p_no_run_debug_conflict) else
        $error("[ASSERT_RAM_READ] Debug read requested while CPU running (illegal state)");
    
    // ========================================
    // ASSERTION 3: Address propagation correctness
    // ========================================
    
    property p_addr_propagation;
        logic [15:0] addr;
        @(posedge clk) disable iff (rst)
        (dbg_mem_read_req_pulse && halted, addr = dbg_mem_addr) |=> 
        (ram_addr_next == addr);
    endproperty
    
    assert property (p_addr_propagation) else
        $error("[ASSERT_RAM_READ] ram_addr_next != requested address");
    
    // ========================================
    // ASSERTION 4: Read enable stability
    // ram_rd_en should stay high for at least 1 cycle
    // ========================================
    
    property p_rd_en_stability;
        @(posedge clk) disable iff (rst)
        (ram_rd_en && halted && mem_busy_q) |=> 
        (ram_rd_en || mem_data_valid);  // Either still reading or data ready
    endproperty
    
    assert property (p_rd_en_stability) else
        $warning("[ASSERT_RAM_READ] ram_rd_en cleared too early");
    
    // ========================================
    // ASSERTION 5: Complete read sequence timing
    // ========================================
    
    property p_complete_read_sequence;
        @(posedge clk) disable iff (rst)
        (dbg_mem_read_req_pulse && halted) |-> 
        ##[1:3] mem_data_valid;
    endproperty
    
    assert property (p_complete_read_sequence) else
        $error("[ASSERT_RAM_READ] Read sequence did not complete within 3 cycles");
    
    // ========================================
    // COVERAGE: Track all scenarios
    // ========================================
    
    covergroup cg_ram_read_scenarios @(posedge clk);
        cp_read_requested: coverpoint dbg_mem_read_req_pulse {
            bins read_req = {1'b1};
        }
        
        cp_ram_rd_en: coverpoint ram_rd_en {
            bins enabled = {1'b1};
            bins disabled = {1'b0};
        }
        
        cp_halted_state: coverpoint halted {
            bins halted = {1'b1};
            bins running = {1'b0};
        }
        
        cp_read_req_with_rd_en: cross cp_read_requested, cp_ram_rd_en, cp_halted_state {
            bins successful_read = binsof(cp_read_requested.read_req) && 
                                   binsof(cp_ram_rd_en.enabled) && 
                                   binsof(cp_halted_state.halted);
            bins failed_read = binsof(cp_read_requested.read_req) && 
                               binsof(cp_ram_rd_en.disabled) && 
                               binsof(cp_halted_state.halted);
        }
    endgroup
    
    cg_ram_read_scenarios cg_inst = new();

endmodule

// ========================================
// Bind to td4cpu_core
// ========================================
bind td4cpu_core td4cpu_ram_read_investigation ram_read_investigator (
    .clk(clk),
    .rst(rst),
    
    // CPU state
    .halted(halted),
    .running(running),
    .pc(pc),
    
    // Debug control
    .dbg_run_req_pulse(dbg_run_req_pulse),
    .dbg_halt_req_pulse(dbg_halt_req_pulse),
    .dbg_step_req_pulse(dbg_step_req_pulse),
    
    // Debug memory interface
    .dbg_mem_addr(dbg_mem_addr),
    .dbg_mem_rdata(dbg_mem_rdata),
    .dbg_mem_wdata(dbg_mem_wdata),
    .dbg_mem_read_req_pulse(dbg_mem_read_req_pulse),
    .dbg_mem_write_req_pulse(dbg_mem_write_req_pulse),
    .dbg_mem_busy(dbg_mem_busy),
    .dbg_mem_err(dbg_mem_err),
    
    // RAM signals
    .ram_rd_en(ram_rd_en),
    .ram_addr_next(ram_addr_next),
    .ram_addr_reg(ram_addr_reg),
    .ram_rd_data(ram_rd_data),
    .ram_wr_en(ram_wr_en),
    .ram_wr_addr(ram_wr_addr),
    .ram_wr_data(ram_wr_data),
    
    // Internal state
    .mem_busy_q(mem_busy_q),
    .mem_data_valid(mem_data_valid),
    .dbg_mem_addr_latched(dbg_mem_addr_latched),
    
    // Instruction fetch
    .insn_valid(insn_valid),
    .insn(insn)
);
