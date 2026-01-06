`timescale 1ns / 1ps

// ========================================
// RAM Read Enable Timing Investigation
// ========================================
// Purpose: Investigate ram_rd_en timing and identify correct behavior
//
// RAM Read Timing Specification:
// --------------------------------
// Cycle N: Debug read request
//   - Input: dbg_mem_read_req_pulse = 1, halted = 1
//   - Output: ram_rd_en <= 1, mem_busy_q <= 1, ram_addr_next <= dbg_mem_addr
//
// Cycle N+1: RAM access
//   - Input: ram_rd_en = 1 (from previous cycle)
//   - RAM outputs data to ram_rd_data (registered)
//   - Control: Keep ram_rd_en = 1 for one cycle
//
// Cycle N+2: Data capture
//   - Input: ram_rd_data valid
//   - Output: dbg_mem_rdata <= ram_rd_data, mem_data_valid <= 1, ram_rd_en <= 0
//
// Cycle N+3: Complete
//   - Output: mem_busy_q <= 0
//
// ========================================

module td4cpu_ram_rd_en_timing (
    input logic clk,
    input logic rst,
    
    // Debug interface
    input logic        dbg_mem_read_req_pulse,
    input logic        dbg_mem_write_req_pulse,
    input logic [15:0] dbg_mem_addr,
    input logic [15:0] dbg_mem_rdata,
    input logic        dbg_mem_err,
    
    // CPU state
    input logic        halted,
    input logic        running,
    
    // RAM control (FOCUS)
    input logic        ram_rd_en,
    input logic [15:0] ram_addr_next,
    input logic [15:0] ram_rd_data,
    
    // Internal state
    input logic        mem_busy_q,
    input logic        mem_data_valid
);

    // ========================================
    // Timing Analysis State Machine
    // ========================================
    
    typedef enum logic [3:0] {
        IDLE,
        READ_REQUEST_CYCLE,      // Cycle N: Request issued
        WAIT_RD_EN_SET,          // Check if ram_rd_en gets set
        RAM_ACCESS_CYCLE,        // Cycle N+1: RAM reading
        DATA_CAPTURE_CYCLE,      // Cycle N+2: Capture data
        COMPLETE_CYCLE,          // Cycle N+3: Done
        ERROR_STATE
    } timing_state_t;
    
    timing_state_t state, next_state;
    
    // Capture values
    logic [15:0] captured_addr;
    logic [63:0] timestamp_request;
    logic [63:0] timestamp_rd_en_expected;
    logic [63:0] timestamp_rd_en_actual;
    logic [63:0] timestamp_data_valid;
    
    // Analysis flags
    logic rd_en_set_on_time;
    logic rd_en_held_correctly;
    logic rd_en_cleared_too_early;
    
    // ========================================
    // State Machine Logic
    // ========================================
    
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            captured_addr <= 16'h0;
            timestamp_request <= 64'h0;
            timestamp_rd_en_expected <= 64'h0;
            timestamp_rd_en_actual <= 64'h0;
            timestamp_data_valid <= 64'h0;
            rd_en_set_on_time <= 1'b0;
            rd_en_held_correctly <= 1'b0;
            rd_en_cleared_too_early <= 1'b0;
        end else begin
            state <= next_state;
            
            case (state)
                IDLE: begin
                    if (dbg_mem_read_req_pulse && halted) begin
                        captured_addr <= dbg_mem_addr;
                        timestamp_request <= $time;
                        timestamp_rd_en_expected <= $time + 10000; // Next cycle
                        rd_en_set_on_time <= 1'b0;
                        rd_en_held_correctly <= 1'b0;
                        rd_en_cleared_too_early <= 1'b0;
                        
                        $display("================================================================================");
                        $display("[RAM_RD_EN_TIMING] @%0t CYCLE N: Read Request", $time);
                        $display("  Address: 0x%04h", dbg_mem_addr);
                        $display("  Expected in NEXT cycle:");
                        $display("    - ram_rd_en should become 1");
                        $display("    - mem_busy_q should become 1");
                        $display("    - ram_addr_next should be 0x%04h", dbg_mem_addr);
                    end
                end
                
                READ_REQUEST_CYCLE: begin
                    // This is Cycle N (same cycle as request due to FF delay)
                    $display("[RAM_RD_EN_TIMING] @%0t CYCLE N (post-clock): Checking immediate effects", $time);
                    $display("  ram_rd_en = %0b (still old value, new value applies next cycle)", ram_rd_en);
                    $display("  mem_busy_q = %0b", mem_busy_q);
                end
                
                WAIT_RD_EN_SET: begin
                    // This is Cycle N+1 - check if ram_rd_en was set
                    $display("[RAM_RD_EN_TIMING] @%0t CYCLE N+1: RAM Access Cycle", $time);
                    $display("  Expected: ram_rd_en=1, mem_busy_q=1, ram_addr_next=0x%04h", captured_addr);
                    $display("  Actual:   ram_rd_en=%0b, mem_busy_q=%0b, ram_addr_next=0x%04h", 
                             ram_rd_en, mem_busy_q, ram_addr_next);
                    
                    if (ram_rd_en) begin
                        rd_en_set_on_time <= 1'b1;
                        timestamp_rd_en_actual <= $time;
                        $display("  ✓ ram_rd_en SET correctly (latency: %0d ps)", $time - timestamp_request);
                    end else begin
                        rd_en_set_on_time <= 1'b0;
                        $error("[RAM_RD_EN_TIMING]   ✗ TIMING ERROR: ram_rd_en NOT SET");
                        $error("[RAM_RD_EN_TIMING]   Expected at t=%0t, but still 0 at t=%0t", 
                               timestamp_rd_en_expected, $time);
                    end
                    
                    if (mem_busy_q) begin
                        $display("  ✓ mem_busy_q=1 correctly");
                    end else begin
                        $warning("[RAM_RD_EN_TIMING]   ⚠ mem_busy_q still 0");
                    end
                    
                    if (ram_addr_next == captured_addr) begin
                        $display("  ✓ ram_addr_next correct");
                    end else begin
                        $error("[RAM_RD_EN_TIMING]   ✗ ram_addr_next mismatch");
                    end
                end
                
                RAM_ACCESS_CYCLE: begin
                    // Cycle N+1 - RAM is being accessed
                    $display("[RAM_RD_EN_TIMING] @%0t CYCLE N+1 (continued): RAM Outputting", $time);
                    $display("  RAM will output ram_rd_data in this cycle");
                    $display("  ram_rd_en should STAY 1 for capture next cycle");
                    
                    if (!ram_rd_en) begin
                        rd_en_cleared_too_early <= 1'b1;
                        $error("[RAM_RD_EN_TIMING]   ✗ CRITICAL: ram_rd_en cleared TOO EARLY");
                        $error("[RAM_RD_EN_TIMING]   It was 1 last cycle but now 0");
                        $error("[RAM_RD_EN_TIMING]   This prevents data capture!");
                    end
                end
                
                DATA_CAPTURE_CYCLE: begin
                    // Cycle N+2 - should capture ram_rd_data
                    $display("[RAM_RD_EN_TIMING] @%0t CYCLE N+2: Data Capture", $time);
                    $display("  ram_rd_data = 0x%04h", ram_rd_data);
                    $display("  mem_data_valid = %0b", mem_data_valid);
                    
                    if (mem_data_valid) begin
                        timestamp_data_valid <= $time;
                        rd_en_held_correctly <= !rd_en_cleared_too_early;
                        $display("  ✓ Data capture successful");
                        $display("  Total latency: %0d ps", $time - timestamp_request);
                    end else begin
                        $error("[RAM_RD_EN_TIMING]   ✗ mem_data_valid not set");
                    end
                    
                    // ram_rd_en should be cleared NOW or next cycle
                    if (!ram_rd_en) begin
                        $display("  ✓ ram_rd_en cleared appropriately");
                    end
                end
                
                COMPLETE_CYCLE: begin
                    $display("[RAM_RD_EN_TIMING] @%0t CYCLE N+3: Complete", $time);
                    $display("  mem_busy_q = %0b (should clear to 0)", mem_busy_q);
                    $display("================================================================================");
                end
                
                ERROR_STATE: begin
                    $display("[RAM_RD_EN_TIMING] @%0t ERROR STATE - Aborting", $time);
                    $display("================================================================================");
                end
            endcase
        end
    end
    
    // Next state logic
    always_comb begin
        case (state)
            IDLE: begin
                if (dbg_mem_read_req_pulse && halted)
                    next_state = READ_REQUEST_CYCLE;
                else
                    next_state = IDLE;
            end
            
            READ_REQUEST_CYCLE: begin
                next_state = WAIT_RD_EN_SET;
            end
            
            WAIT_RD_EN_SET: begin
                if (ram_rd_en && mem_busy_q)
                    next_state = RAM_ACCESS_CYCLE;
                else if (!ram_rd_en)
                    next_state = ERROR_STATE;
                else
                    next_state = WAIT_RD_EN_SET;
            end
            
            RAM_ACCESS_CYCLE: begin
                if (mem_data_valid)
                    next_state = DATA_CAPTURE_CYCLE;
                else if (!ram_rd_en && !mem_data_valid)
                    next_state = ERROR_STATE;  // Cleared too early
                else
                    next_state = RAM_ACCESS_CYCLE;
            end
            
            DATA_CAPTURE_CYCLE: begin
                if (!mem_busy_q)
                    next_state = COMPLETE_CYCLE;
                else
                    next_state = DATA_CAPTURE_CYCLE;
            end
            
            COMPLETE_CYCLE: begin
                next_state = IDLE;
            end
            
            ERROR_STATE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // ========================================
    // TIMING ASSERTIONS
    // ========================================
    
    // ASSERTION 1: ram_rd_en must be set within 1 cycle of request
    property p_rd_en_timing;
        @(posedge clk) disable iff (rst)
        (dbg_mem_read_req_pulse && halted) |=> ram_rd_en;
    endproperty
    
    assert property (p_rd_en_timing) else
        $error("[ASSERT_TIMING] ram_rd_en NOT SET 1 cycle after request (CRITICAL)");
    
    // ASSERTION 2: ram_rd_en must stay high for at least 1 cycle
    property p_rd_en_hold;
        @(posedge clk) disable iff (rst)
        (ram_rd_en && mem_busy_q && !mem_data_valid) |=> (ram_rd_en || mem_data_valid);
    endproperty
    
    assert property (p_rd_en_hold) else
        $error("[ASSERT_TIMING] ram_rd_en cleared too early before data capture");
    
    // ASSERTION 3: Complete sequence timing
    sequence s_read_sequence;
        (dbg_mem_read_req_pulse && halted) ##1 
        (ram_rd_en && mem_busy_q) ##[1:2]
        mem_data_valid;
    endsequence
    
    property p_complete_timing;
        @(posedge clk) disable iff (rst)
        (dbg_mem_read_req_pulse && halted) |-> s_read_sequence;
    endproperty
    
    assert property (p_complete_timing) else
        $error("[ASSERT_TIMING] Read sequence timing violated");
    
    // ========================================
    // COVERAGE
    // ========================================
    
    covergroup cg_timing @(posedge clk);
        cp_rd_en_latency: coverpoint (state) {
            bins request = (IDLE => READ_REQUEST_CYCLE);
            bins rd_en_set = (READ_REQUEST_CYCLE => WAIT_RD_EN_SET => RAM_ACCESS_CYCLE);
            bins data_capture = (RAM_ACCESS_CYCLE => DATA_CAPTURE_CYCLE);
            bins complete = (DATA_CAPTURE_CYCLE => COMPLETE_CYCLE => IDLE);
            bins error = (WAIT_RD_EN_SET => ERROR_STATE, RAM_ACCESS_CYCLE => ERROR_STATE);
        }
        
        cp_rd_en_value: coverpoint ram_rd_en {
            bins low = {0};
            bins high = {1};
            bins transitions = (0 => 1 => 0);
        }
    endgroup
    
    cg_timing cg_inst = new();

endmodule

// ========================================
// Bind to td4cpu_core
// ========================================
bind td4cpu_core td4cpu_ram_rd_en_timing ram_rd_en_timing_checker (
    .clk(clk),
    .rst(rst),
    
    // Debug interface
    .dbg_mem_read_req_pulse(dbg_mem_read_req_pulse),
    .dbg_mem_write_req_pulse(dbg_mem_write_req_pulse),
    .dbg_mem_addr(dbg_mem_addr),
    .dbg_mem_rdata(dbg_mem_rdata),
    .dbg_mem_err(dbg_mem_err),
    
    // CPU state
    .halted(halted),
    .running(running),
    
    // RAM control
    .ram_rd_en(ram_rd_en),
    .ram_addr_next(ram_addr_next),
    .ram_rd_data(ram_rd_data),
    
    // Internal state
    .mem_busy_q(mem_busy_q),
    .mem_data_valid(mem_data_valid)
);
