`timescale 1ns / 1ps

// Address Flow Debugging Assertions for TD4 CPU
// Purpose: Track address flow from debug interface through RAM to execution
// to identify the +1 offset bug

module td4cpu_address_debug (
    input logic clk,
    input logic rst,
    
    // Debug interface signals (from Register_Block)
    input logic [15:0] dbg_mem_addr,
    input logic [15:0] dbg_mem_wdata,
    input logic        dbg_mem_write_req_pulse,
    
    // RAM internal signals (from td4cpu_core)
    input logic        ram_wr_en,
    input logic [15:0] ram_wr_addr,
    input logic [15:0] ram_wr_data,
    
    input logic        ram_rd_en,
    input logic [15:0] ram_addr_reg,     // Registered address (for debug tracing)
    input logic [15:0] ram_addr_next,    // Next address wire (timing-correct value)
    input logic [15:0] ram_rd_data,
    
    // CPU fetch/execute signals
    input logic [15:0] pc,
    input logic [15:0] fetch_pc,
    input logic [15:0] insn_fetched_pc,
    input logic [15:0] insn_decoded_pc,
    input logic [15:0] insn_fetched,
    input logic [15:0] insn_decoded_reg,
    input logic        insn_valid,
    input logic        insn_decoded_valid,
    
    input logic        halted,
    input logic        running
);

    // ========================================
    // Debug Write Address Tracking
    // ========================================
    
    // ASSERTION 1: Debug write address must match RAM write address
    property p_debug_write_addr_match;
        @(posedge clk) disable iff (rst)
        (dbg_mem_write_req_pulse && halted) |-> ##1 (ram_wr_addr == $past(dbg_mem_addr));
    endproperty
    
    assert property (p_debug_write_addr_match)
    else $error("[ADDR_DBG] Debug write address mismatch: dbg_mem_addr=%0h, ram_wr_addr=%0h",
                $past(dbg_mem_addr), ram_wr_addr);
    
    // ASSERTION 2: Debug write data must match RAM write data
    property p_debug_write_data_match;
        @(posedge clk) disable iff (rst)
        (dbg_mem_write_req_pulse && halted) |-> ##1 (ram_wr_data == $past(dbg_mem_wdata));
    endproperty
    
    assert property (p_debug_write_data_match)
    else $error("[ADDR_DBG] Debug write data mismatch: dbg_mem_wdata=%04h, ram_wr_data=%04h",
                $past(dbg_mem_wdata), ram_wr_data);
    
    // ========================================
    // Fetch Address Tracking
    // ========================================
    
    // ASSERTION 3: RAM read address for instruction fetch must match PC
    // UPDATED: Check ram_addr_next (wire) instead of ram_addr_reg (registered for debug)
    sequence s_normal_fetch;
        (running && !$past(ram_rd_en) && !ram_rd_en) ##1 ram_rd_en;
    endsequence
    
    property p_fetch_addr_matches_pc;
        @(posedge clk) disable iff (rst)
        s_normal_fetch |-> (ram_addr_next == $past(pc, 1));
    endproperty
    
    assert property (p_fetch_addr_matches_pc)
    else $error("[ADDR_DBG] Fetch address mismatch: ram_addr_next=%0h, prev_pc=%0h",
                ram_addr_next, $past(pc, 1));
    
    // ========================================
    // Instruction Capture Tracking
    // ========================================
    
    // ASSERTION 4: insn_fetched_pc must match the fetch_pc at time of fetch
    property p_insn_fetched_pc_capture;
        @(posedge clk) disable iff (rst)
        (ram_rd_en && running) |=> 
        (insn_valid |-> (insn_fetched_pc == $past(fetch_pc, 1)));
    endproperty
    
    assert property (p_insn_fetched_pc_capture)
    else $error("[ADDR_DBG] insn_fetched_pc capture error: insn_fetched_pc=%0h, prev_fetch_pc=%0h",
                insn_fetched_pc, $past(fetch_pc, 1));
    
    // ASSERTION 5: insn_decoded_pc must match insn_fetched_pc when decoding
    property p_insn_decoded_pc_assignment;
        @(posedge clk) disable iff (rst)
        insn_valid |=> (insn_decoded_pc == $past(insn_fetched_pc));
    endproperty
    
    assert property (p_insn_decoded_pc_assignment)
    else $error("[ADDR_DBG] insn_decoded_pc assignment error: insn_decoded_pc=%0h, prev_insn_fetched_pc=%0h",
                insn_decoded_pc, $past(insn_fetched_pc));
    
    // ========================================
    // Debug Write Tracing (Display only)
    // ========================================
    
    always @(posedge clk) begin
        if (dbg_mem_write_req_pulse && halted) begin
            $display("[ADDR_DBG] @%0t DEBUG WRITE REQUEST: addr=0x%04h, data=0x%04h",
                     $time, dbg_mem_addr, dbg_mem_wdata);
        end
        
        if (ram_wr_en) begin
            $display("[ADDR_DBG] @%0t RAM WRITE: ram[0x%04h] <= 0x%04h",
                     $time, ram_wr_addr, ram_wr_data);
        end
        
        if (ram_rd_en && running) begin
            $display("[ADDR_DBG] @%0t RAM READ (fetch): addr=0x%04h (pc=%0h, fetch_pc=%0h)",
                     $time, ram_addr_reg, pc, fetch_pc);
        end
        
        if (insn_valid) begin
            $display("[ADDR_DBG] @%0t INSN VALID: insn=0x%04h, insn_fetched_pc=%0h",
                     $time, insn_fetched, insn_fetched_pc);
        end
        
        if (insn_decoded_valid) begin
            $display("[ADDR_DBG] @%0t INSN EXECUTE: PC=%0h, insn=0x%04h",
                     $time, insn_decoded_pc, insn_decoded_reg);
        end
    end
    
    // ========================================
    // RAM Content Verification
    // ========================================
    
    // Track what was written to each address
    logic [15:0] expected_ram_content [0:15];  // Track first 16 addresses
    logic        address_written [0:15];
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < 16; i++) begin
                expected_ram_content[i] <= 16'hXXXX;
                address_written[i] <= 1'b0;
            end
        end else begin
            if (ram_wr_en && ram_wr_addr < 16) begin
                expected_ram_content[ram_wr_addr] <= ram_wr_data;
                address_written[ram_wr_addr] <= 1'b1;
                $display("[ADDR_DBG] @%0t TRACKING: expected_ram_content[%0h] = 0x%04h",
                         $time, ram_wr_addr, ram_wr_data);
            end
            
            // When instruction is fetched, verify it matches what we wrote
            if (insn_valid && insn_fetched_pc < 16 && address_written[insn_fetched_pc]) begin
                if (insn_fetched !== expected_ram_content[insn_fetched_pc]) begin
                    $error("[ADDR_DBG] @%0t RAM CONTENT MISMATCH at fetch_pc=%0h: fetched=0x%04h, expected=0x%04h",
                           $time, insn_fetched_pc, insn_fetched, expected_ram_content[insn_fetched_pc]);
                end else begin
                    $display("[ADDR_DBG] @%0t RAM CONTENT OK: addr=%0h, insn=0x%04h matches expected",
                             $time, insn_fetched_pc, insn_fetched);
                end
            end
        end
    end

endmodule

// Bind statement to connect to td4cpu_core
bind td4cpu_core td4cpu_address_debug u_addr_debug (
    .clk(clk),
    .rst(rst),
    
    // Debug interface signals
    .dbg_mem_addr(dbg_mem_addr),
    .dbg_mem_wdata(dbg_mem_wdata),
    .dbg_mem_write_req_pulse(dbg_mem_write_req_pulse),
    
    // RAM internal signals
    .ram_wr_en(ram_wr_en),
    .ram_wr_addr(ram_wr_addr),
    .ram_wr_data(ram_wr_data),
    
    .ram_rd_en(ram_rd_en),
    .ram_addr_reg(ram_addr_reg),
    .ram_addr_next(ram_addr_next),  // Add wire for timing-correct address
    .ram_rd_data(ram_rd_data),
    
    // CPU fetch/execute signals
    .pc(pc),
    .fetch_pc(fetch_pc),
    .insn_fetched_pc(insn_fetched_pc),
    .insn_decoded_pc(insn_decoded_pc),
    .insn_fetched(insn_fetched),
    .insn_decoded_reg(insn_decoded_reg),
    .insn_valid(insn_valid),
    .insn_decoded_valid(insn_decoded_valid),
    
    .halted(halted),
    .running(running)
);
