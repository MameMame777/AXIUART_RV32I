`timescale 1ns / 1ps
//==============================================================================
// RV32I Memory Stage Timing Assertions
//==============================================================================
// SystemVerilog Assertions for Memory Access Stage
// Verifies load/store byte alignment, MMIO LED register, exception detection,
// and memory access control according to rv32i_mem_spec.md
//
// Bind this module to rv32i_mem instance:
//   bind rv32i_mem rv32i_mem_timing_spec u_mem_assertions (.*);
//==============================================================================

module rv32i_mem_timing_spec
    import rv32i_isa_pkg::*;
    import rv32i_pipeline_pkg::*;
(
    input logic        clk,
    input logic        rst_n,
    
    // Pipeline inputs
    input logic [31:0] pc_in,
    input logic [31:0] insn_in,
    input logic [31:0] alu_result_in,
    input logic [31:0] rs2_data_in,
    input logic [31:0] csr_rdata_in,
    input decode_ctrl_t ctrl_in,
    input logic        valid_in,
    
    // RAM interface
    input logic [31:0] data_ram_rdata,
    input logic [10:0] data_ram_addr,
    input logic [31:0] data_ram_wdata,
    input logic [3:0]  data_ram_we,
    
    // Outputs
    input logic [31:0] mem_data,
    input logic [3:0]  led_out,
    input logic        exception_trap,
    input logic [31:0] exception_pc,
    input logic [4:0]  exception_code,
    input logic [31:0] exception_tval
);

    //==========================================================================
    // SPEC-MEM-1: Load Byte Sign Extension
    //==========================================================================
    // Verify LB (load byte signed) sign-extends from bit 7
    
    logic [31:0] mem_addr;
    assign mem_addr = alu_result_in;
    
    property load_byte_sign_ext;
        logic [7:0] byte_data;
        logic [31:0] expected_data;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && ctrl_in.mem_read && (ctrl_in.mem_width == MEM_BYTE) && ctrl_in.mem_sign_ext,
         byte_data = (mem_addr[1:0] == 2'b00) ? data_ram_rdata[7:0] :
                     (mem_addr[1:0] == 2'b01) ? data_ram_rdata[15:8] :
                     (mem_addr[1:0] == 2'b10) ? data_ram_rdata[23:16] :
                                                 data_ram_rdata[31:24],
         expected_data = {{24{byte_data[7]}}, byte_data})
        |-> ##1 (mem_data == expected_data);
    endproperty
    
    assert_lb_sign: assert property (load_byte_sign_ext)
        else $error("[SPEC-MEM-1] LB sign extension failed: addr=0x%08h byte=0x%02h expected=0x%08h got=0x%08h",
                    mem_addr, mem_addr[1:0], {{24{mem_data[7]}}, mem_data[7:0]}, mem_data);

    //==========================================================================
    // SPEC-MEM-2: Store Byte Write Enable
    //==========================================================================
    // Verify SB (store byte) asserts correct byte write enable
    
    property store_byte_we_pattern;
        logic [3:0] expected_we;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && ctrl_in.mem_write && (ctrl_in.mem_width == MEM_BYTE),
         expected_we = (mem_addr[1:0] == 2'b00) ? 4'b0001 :
                       (mem_addr[1:0] == 2'b01) ? 4'b0010 :
                       (mem_addr[1:0] == 2'b10) ? 4'b0100 :
                                                   4'b1000)
        |-> (data_ram_we == expected_we);
    endproperty
    
    assert_sb_we: assert property (store_byte_we_pattern)
        else $error("[SPEC-MEM-2] SB write enable wrong: addr=0x%08h offset=%0d expected_we=%b got_we=%b",
                    mem_addr, mem_addr[1:0], 
                    (mem_addr[1:0] == 2'b00) ? 4'b0001 :
                    (mem_addr[1:0] == 2'b01) ? 4'b0010 :
                    (mem_addr[1:0] == 2'b10) ? 4'b0100 : 4'b1000,
                    data_ram_we);

    //==========================================================================
    // SPEC-MEM-3: MMIO LED Register Update
    //==========================================================================
    // Verify write to address 0x407C updates led_out register
    
    property mmio_led_write;
        logic [3:0] expected_led;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && ctrl_in.mem_write && (mem_addr == 32'h0000_407C),
         expected_led = rs2_data_in[3:0])
        |-> ##1 (led_out == expected_led);
    endproperty
    
    assert_mmio_led: assert property (mmio_led_write)
        else $error("[SPEC-MEM-3] MMIO LED not updated: addr=0x%08h data=0x%08h expected_led=%h got_led=%h",
                    mem_addr, rs2_data_in, rs2_data_in[3:0], led_out);

    //==========================================================================
    // SPEC-MEM-4: Load Halfword Misalignment Detection
    //==========================================================================
    // Verify LH/LHU on odd address triggers exception code 4
    
    property load_half_misalign;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && ctrl_in.mem_read && (ctrl_in.mem_width == MEM_HALF) && mem_addr[0])
        |-> (exception_trap && (exception_code == 5'd4));
    endproperty
    
    assert_lh_misalign: assert property (load_half_misalign)
        else $error("[SPEC-MEM-4] LH misalignment not detected: addr=0x%08h exception_trap=%b code=%0d (expected 4)",
                    mem_addr, exception_trap, exception_code);

    //==========================================================================
    // SPEC-MEM-5: RAM Write Enable Zero for MMIO Access
    //==========================================================================
    // Verify MMIO writes don't assert RAM write enable
    
    property mmio_no_ram_write;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && ctrl_in.mem_write && (mem_addr == 32'h0000_407C))
        |-> (data_ram_we == 4'b0000);
    endproperty
    
    assert_mmio_no_ram: assert property (mmio_no_ram_write)
        else $error("[SPEC-MEM-5] MMIO write asserted RAM WE: addr=0x%08h we=%b (expected 0000)",
                    mem_addr, data_ram_we);

    //==========================================================================
    // SPEC-MEM-6: Load Access Fault Detection
    //==========================================================================
    // Verify load from invalid address (≥0x2000, !=0x407C) triggers exception code 5
    
    property load_access_fault;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && ctrl_in.mem_read && (mem_addr >= 32'h0000_2000) && (mem_addr != 32'h0000_407C))
        |-> (exception_trap && (exception_code == 5'd5));
    endproperty
    
    assert_load_fault: assert property (load_access_fault)
        else $error("[SPEC-MEM-6] Load access fault not detected: addr=0x%08h exception_trap=%b code=%0d (expected 5)",
                    mem_addr, exception_trap, exception_code);

    //==========================================================================
    // Coverage: Load Type and Offset Coverage
    //==========================================================================
    
    covergroup load_access_cg @(posedge clk);
        option.per_instance = 1;
        option.name = "mem_load_access";
        
        load_width: coverpoint ctrl_in.mem_width iff (valid_in && ctrl_in.mem_read) {
            bins byte = {MEM_BYTE};
            bins half = {MEM_HALF};
            bins word = {MEM_WORD};
        }
        
        load_offset: coverpoint mem_addr[1:0] iff (valid_in && ctrl_in.mem_read) {
            bins offset_0 = {2'b00};
            bins offset_1 = {2'b01};
            bins offset_2 = {2'b10};
            bins offset_3 = {2'b11};
        }
        
        sign_extend: coverpoint ctrl_in.mem_sign_ext iff (valid_in && ctrl_in.mem_read) {
            bins unsigned_load = {1'b0};
            bins signed_load   = {1'b1};
        }
        
        // Cross coverage: load width × offset × sign extension
        load_pattern: cross load_width, load_offset, sign_extend;
    endgroup
    
    load_access_cg load_cov = new();
    
    //==========================================================================
    // Coverage: Store Type and Offset Coverage
    //==========================================================================
    
    covergroup store_access_cg @(posedge clk);
        option.per_instance = 1;
        option.name = "mem_store_access";
        
        store_width: coverpoint ctrl_in.mem_width iff (valid_in && ctrl_in.mem_write) {
            bins byte = {MEM_BYTE};
            bins half = {MEM_HALF};
            bins word = {MEM_WORD};
        }
        
        store_offset: coverpoint mem_addr[1:0] iff (valid_in && ctrl_in.mem_write) {
            bins offset_0 = {2'b00};
            bins offset_1 = {2'b01};
            bins offset_2 = {2'b10};
            bins offset_3 = {2'b11};
        }
        
        // Cross coverage: store width × offset
        store_pattern: cross store_width, store_offset;
    endgroup
    
    store_access_cg store_cov = new();
    
    //==========================================================================
    // Coverage: Exception Type Coverage
    //==========================================================================
    
    covergroup exception_cg @(posedge clk);
        option.per_instance = 1;
        option.name = "mem_exception_types";
        
        exception_type: coverpoint exception_code iff (exception_trap) {
            bins illegal_insn     = {5'd2};
            bins ebreak           = {5'd3};
            bins load_misalign    = {5'd4};
            bins load_fault       = {5'd5};
            bins store_misalign   = {5'd6};
            bins store_fault      = {5'd7};
            bins ecall            = {5'd11};
        }
    endgroup
    
    exception_cg exception_cov = new();

endmodule : rv32i_mem_timing_spec
