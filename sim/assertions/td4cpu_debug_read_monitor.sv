`timescale 1ns / 1ps

// Debug Memory Read Path Monitor
// Purpose: Investigate why debug reads return data from last write address
// Tracks signal flow: dbg_mem_addr → ram_addr_next → ram_rd_data

module td4cpu_debug_read_monitor (
    input logic clk,
    input logic rst,
    
    // Debug interface (from Register_Block)
    input logic [15:0] dbg_mem_addr,
    input logic [15:0] dbg_mem_rdata,
    input logic        dbg_mem_read_req_pulse,
    input logic        dbg_mem_write_req_pulse,
    input logic [15:0] dbg_mem_wdata,
    
    // RAM signals (from td4cpu_core)
    input logic        ram_rd_en,
    input logic [15:0] ram_addr_reg,     // Registered (may be polluted)
    input logic [15:0] ram_addr_next,    // Wire (timing-correct)
    input logic [15:0] ram_rd_data,
    input logic        ram_wr_en,
    input logic [15:0] ram_wr_addr,
    input logic [15:0] ram_wr_data,
    
    // Control signals
    input logic        halted,
    input logic        mem_busy_q,
    input logic        mem_data_valid
);

    // ========================================
    // Signal Capture for Investigation
    // ========================================
    
    // Capture requested address when debug read starts
    logic [15:0] captured_read_addr;
    logic [15:0] last_write_addr;
    logic        debug_read_active;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            captured_read_addr <= 16'h0;
            last_write_addr <= 16'h0;
            debug_read_active <= 1'b0;
        end else begin
            // Track last write address (suspect for pollution)
            if (ram_wr_en) begin
                last_write_addr <= ram_wr_addr;
                $display("[DBG_READ_MON] @%0t RAM WRITE: ram_wr_addr=0x%04h, ram_wr_data=0x%04h", 
                         $time, ram_wr_addr, ram_wr_data);
            end
            
            // Capture read address when request starts
            if (dbg_mem_read_req_pulse) begin
                captured_read_addr <= dbg_mem_addr;
                debug_read_active <= 1'b1;
                $display("[DBG_READ_MON] @%0t READ REQUEST: dbg_mem_addr=0x%04h", 
                         $time, dbg_mem_addr);
                $display("[DBG_READ_MON]   State: halted=%0b, mem_busy_q=%0b, ram_rd_en=%0b",
                         halted, mem_busy_q, ram_rd_en);
            end
            
            // Monitor address during read enable
            if (ram_rd_en && debug_read_active) begin
                $display("[DBG_READ_MON] @%0t READ CYCLE 1: ram_addr_next=0x%04h, ram_addr_reg=0x%04h",
                         $time, ram_addr_next, ram_addr_reg);
                $display("[DBG_READ_MON]   Expected: 0x%04h, Last Write Addr: 0x%04h",
                         captured_read_addr, last_write_addr);
                
                // Check if ram_addr_next matches request (should match)
                if (ram_addr_next != captured_read_addr) begin
                    $display("[DBG_READ_MON]   *** MISMATCH: ram_addr_next should be 0x%04h but is 0x%04h ***",
                             captured_read_addr, ram_addr_next);
                    if (ram_addr_next == last_write_addr) begin
                        $display("[DBG_READ_MON]   *** POLLUTION: ram_addr_next matches last_write_addr! ***");
                    end
                end
            end
            
            // Monitor data capture
            if (mem_data_valid && debug_read_active) begin
                $display("[DBG_READ_MON] @%0t READ COMPLETE: ram_rd_data=0x%04h",
                         $time, ram_rd_data);
                debug_read_active <= 1'b0;
            end
        end
    end
    
    // ========================================
    // ASSERTION 1: Debug read address propagation
    // ram_addr_next should equal requested address during read cycle
    // ========================================
    
    property p_debug_read_addr_propagation;
        logic [15:0] req_addr;
        @(posedge clk) disable iff (rst)
        (dbg_mem_read_req_pulse && halted, req_addr = dbg_mem_addr) |=> 
        ##[0:1] (ram_rd_en && (ram_addr_next == req_addr));
    endproperty
    
    assert property (p_debug_read_addr_propagation) else
        $error("[ASSERT] Debug read address not propagated correctly");
    
    // ========================================
    // ASSERTION 2: ram_addr_reg pollution detection
    // After debug write, ram_addr_reg should NOT affect subsequent reads
    // ========================================
    
    logic [15:0] prev_write_addr;
    
    always_ff @(posedge clk) begin
        if (ram_wr_en)
            prev_write_addr <= ram_wr_addr;
    end
    
    property p_no_write_pollution;
        logic [15:0] req_addr;
        @(posedge clk) disable iff (rst)
        (dbg_mem_read_req_pulse && halted && (dbg_mem_addr != prev_write_addr), req_addr = dbg_mem_addr) |=>
        ##[0:2] (ram_rd_en && (ram_addr_next == req_addr));
    endproperty
    
    assert property (p_no_write_pollution) else
        $error("[ASSERT] ram_addr_next polluted by previous write address: ram_addr_next=0x%04h, prev_write=0x%04h",
               ram_addr_next, prev_write_addr);
    
    // ========================================
    // ASSERTION 3: ram_addr_next stability during read
    // Address should remain stable during multi-cycle read
    // ========================================
    
    property p_addr_stability_during_read;
        logic [15:0] stable_addr;
        @(posedge clk) disable iff (rst)
        (ram_rd_en && halted, stable_addr = ram_addr_next) |=> 
        (ram_rd_en |-> (ram_addr_next == stable_addr));
    endproperty
    
    assert property (p_addr_stability_during_read) else
        $error("[ASSERT] ram_addr_next changed during read cycle");
    
    // ========================================
    // ASSERTION 4: Control signal correlation
    // When debug read starts, expect specific control sequence
    // ========================================
    
    property p_debug_read_control_sequence;
        @(posedge clk) disable iff (rst)
        (dbg_mem_read_req_pulse && halted) |=> 
        ##1 (ram_rd_en && mem_busy_q);
    endproperty
    
    assert property (p_debug_read_control_sequence) else
        $error("[ASSERT] Debug read control sequence incorrect: ram_rd_en=%0b, mem_busy_q=%0b",
               ram_rd_en, mem_busy_q);

endmodule

// Bind to td4cpu_core instance in testbench
bind td4cpu_core td4cpu_debug_read_monitor debug_read_mon (
    .clk(clk),
    .rst(rst),
    
    // Debug interface
    .dbg_mem_addr(dbg_mem_addr),
    .dbg_mem_rdata(dbg_mem_rdata),
    .dbg_mem_read_req_pulse(dbg_mem_read_req_pulse),
    .dbg_mem_write_req_pulse(dbg_mem_write_req_pulse),
    .dbg_mem_wdata(dbg_mem_wdata),
    
    // RAM signals
    .ram_rd_en(ram_rd_en),
    .ram_addr_reg(ram_addr_reg),
    .ram_addr_next(ram_addr_next),
    .ram_rd_data(ram_rd_data),
    .ram_wr_en(ram_wr_en),
    .ram_wr_addr(ram_wr_addr),
    .ram_wr_data(ram_wr_data),
    
    // Control
    .halted(halted),
    .mem_busy_q(mem_busy_q),
    .mem_data_valid(mem_data_valid)
);
