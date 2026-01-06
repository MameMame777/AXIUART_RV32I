`timescale 1ns / 1ps

//==============================================================================
// RV32I LED MMIO Write Specification (SVA)
//==============================================================================
// This module defines the expected behavior for LED MMIO writes in RV32I core.
// Assertions verify store transactions to LED register at address 0x407C.
//
// Expected Behavior:
// 1. When SW instruction stores to 0x407C in MEM stage, led_reg updates
// 2. LED register captures lower 4 bits of store data
// 3. Write occurs on positive clock edge following address match
//==============================================================================

module rv32i_mmio_led_spec
    import rv32i_isa_pkg::*;
(
    input logic        clk,
    input logic        rst_n,
    
    // MEM stage signals
    input logic [31:0] mem_addr,
    input logic        mem_write,
    input logic [31:0] mem_store_data,
    input logic        mem_valid,
    input logic        mem_is_mmio,
    
    // LED register
    input logic [3:0]  led_reg,
    
    // Control signals
    input decode_ctrl_t mem_ctrl
);

    //==========================================================================
    // Constants
    //==========================================================================
    
    localparam logic [31:0] LED_ADDR = 32'h0000_407C;
    
    //==========================================================================
    // Helper Signals
    //==========================================================================
    
    // LED write transaction detected
    logic led_write_detected;
    assign led_write_detected = mem_valid && 
                                 mem_ctrl.mem_write && 
                                 (mem_addr == LED_ADDR) &&
                                 mem_is_mmio;
    
    //==========================================================================
    // ASSERTION 1: LED Write Transaction
    //==========================================================================
    // When store targets LED address, led_reg must update on next cycle
    
    property led_write_updates;
        logic [3:0] expected_value;
        @(posedge clk) disable iff (!rst_n)
        (led_write_detected, expected_value = mem_store_data[3:0]) 
        |-> 
        ##1 (led_reg == expected_value);
    endproperty
    
    assert_led_write_updates: assert property (led_write_updates)
        else $error("[LED_SPEC] ASSERTION FAILED: LED write to 0x%h with data 0x%h did not update led_reg (got 0x%h)",
                    mem_addr, mem_store_data[3:0], led_reg);
    
    cover_led_write_updates: cover property (led_write_updates)
        $display("[LED_SPEC] COVER: LED write transaction completed successfully @ %0t", $time);
    
    //==========================================================================
    // ASSERTION 2: LED Write Address Match
    //==========================================================================
    // LED write must only occur when exact address matches
    
    property led_write_address_exact;
        @(posedge clk) disable iff (!rst_n)
        (mem_valid && mem_ctrl.mem_write && mem_is_mmio && (mem_addr != LED_ADDR))
        |->
        ##1 ($stable(led_reg));
    endproperty
    
    assert_led_write_address_exact: assert property (led_write_address_exact)
        else $error("[LED_SPEC] ASSERTION FAILED: LED register changed for non-LED address 0x%h", mem_addr);
    
    //==========================================================================
    // ASSERTION 3: LED Write Signal Dependencies
    //==========================================================================
    // LED write requires all control signals asserted
    
    property led_write_requires_mem_write;
        @(posedge clk) disable iff (!rst_n)
        (mem_valid && (mem_addr == LED_ADDR) && !mem_ctrl.mem_write)
        |->
        ##1 ($stable(led_reg));
    endproperty
    
    assert_led_write_requires_mem_write: assert property (led_write_requires_mem_write);
    
    //==========================================================================
    // DEBUG: Continuous Monitoring
    //==========================================================================
    
    `ifdef ENABLE_ASSERTIONS
    always @(posedge clk) begin
        // Report ALL MEM stage activity for debugging
        if (mem_valid) begin
            $display("[LED_SPEC] @ %0t: MEM valid - addr=0x%h, mem_write=%b, ctrl.mem_write=%b, is_mmio=%b, data=0x%h",
                     $time, mem_addr, mem_write, mem_ctrl.mem_write, mem_is_mmio, mem_store_data);
        end
        
        if (mem_valid && mem_ctrl.mem_write && mem_is_mmio) begin
            $display("[LED_SPEC] @ %0t: MEM stage store to MMIO addr=0x%h, data=0x%h, is_led=%b",
                     $time, mem_addr, mem_store_data, (mem_addr == LED_ADDR));
        end
        
        if (led_write_detected) begin
            $display("[LED_SPEC] @ %0t: LED write detected! addr=0x%h, data=0x%h (led_reg will be 0x%h)",
                     $time, mem_addr, mem_store_data[3:0], mem_store_data[3:0]);
        end
    end
    `endif
    
    //==========================================================================
    // COVERAGE: LED Write Scenarios
    //==========================================================================
    
    covergroup led_write_coverage @(posedge clk);
        option.per_instance = 1;
        option.name = "led_write_cov";
        
        led_values: coverpoint mem_store_data[3:0] iff (led_write_detected) {
            bins zero = {4'h0};
            bins one_to_seven = {[4'h1:4'h7]};
            bins eight_to_fifteen = {[4'h8:4'hF]};
        }
        
        led_transitions: coverpoint led_reg {
            bins valid_values[] = {[4'h0:4'hF]};
        }
    endgroup
    
    led_write_coverage led_cov = new();

endmodule : rv32i_mmio_led_spec
