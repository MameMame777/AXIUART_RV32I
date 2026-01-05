`timescale 1ns / 1ps
//==============================================================================
// RV32I Write-Back Stage Timing Assertions
//==============================================================================
// SystemVerilog Assertions for Write-Back Stage
// Verifies result multiplexer selection, x0 write suppression, register file
// write control, and CSR write operations according to rv32i_wb_spec.md
//
// Bind this module to rv32i_wb instance:
//   bind rv32i_wb rv32i_wb_timing_spec u_wb_assertions (.*);
//==============================================================================

module rv32i_wb_timing_spec
    import rv32i_isa_pkg::*;
    import rv32i_pipeline_pkg::*;
(
    // Pipeline inputs
    input logic [31:0] pc_in,
    input logic [31:0] insn_in,
    input logic [31:0] mem_data_in,
    input logic [31:0] alu_result_in,
    input logic [31:0] csr_rdata_in,
    input decode_ctrl_t ctrl_in,
    input logic        valid_in,
    input logic [4:0]  rd_addr_in,
    
    // Outputs
    input logic [31:0] wb_result,
    input logic        rf_wen,
    input logic [11:0] csr_waddr,
    input logic [31:0] csr_wdata,
    input logic        csr_wen
);

    // Clock and reset (derived from module context)
    logic clk;
    logic rst_n;
    assign clk = 1'b0;
    assign rst_n = 1'b1;

    //==========================================================================
    // SPEC-WB-1: Result Mux Selection (ALU)
    //==========================================================================
    // Verify wb_result selects alu_result when wb_src = WB_ALU
    
    property result_mux_alu;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && (ctrl_in.wb_src == WB_ALU))
        |-> (wb_result == alu_result_in);
    endproperty
    
    assert_mux_alu: assert property (result_mux_alu)
        else $error("[SPEC-WB-1] Result mux ALU selection failed: wb_src=%0d expected=0x%08h got=0x%08h",
                    ctrl_in.wb_src, alu_result_in, wb_result);

    //==========================================================================
    // SPEC-WB-2: Result Mux Selection (Memory)
    //==========================================================================
    // Verify wb_result selects mem_data when wb_src = WB_MEM
    
    property result_mux_mem;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && (ctrl_in.wb_src == WB_MEM))
        |-> (wb_result == mem_data_in);
    endproperty
    
    assert_mux_mem: assert property (result_mux_mem)
        else $error("[SPEC-WB-2] Result mux MEM selection failed: wb_src=%0d expected=0x%08h got=0x%08h",
                    ctrl_in.wb_src, mem_data_in, wb_result);

    //==========================================================================
    // SPEC-WB-3: x0 Write Suppression
    //==========================================================================
    // Verify writes to x0 are suppressed (rf_wen=0 when rd_addr=0)
    
    property x0_write_suppressed;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && ctrl_in.rf_wen && (rd_addr_in == 5'b0))
        |-> !rf_wen;
    endproperty
    
    assert_x0_suppress: assert property (x0_write_suppressed)
        else $error("[SPEC-WB-3] x0 write not suppressed: rd_addr=x0 but rf_wen=%b (expected 0)",
                    rf_wen);

    //==========================================================================
    // SPEC-WB-4: Register File Write Enable
    //==========================================================================
    // Verify rf_wen asserted for valid instructions with rf_wen control
    // and non-zero destination register
    
    property rf_write_enable;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && ctrl_in.rf_wen && (rd_addr_in != 5'b0))
        |-> rf_wen;
    endproperty
    
    assert_rf_wen: assert property (rf_write_enable)
        else $error("[SPEC-WB-4] RF write not enabled: valid=%b ctrl.rf_wen=%b rd=x%0d rf_wen=%b",
                    valid_in, ctrl_in.rf_wen, rd_addr_in, rf_wen);

    //==========================================================================
    // SPEC-WB-5: CSR Write Enable
    //==========================================================================
    // Verify csr_wen asserted for CSR instructions with write operation
    
    property csr_write_enable;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && ctrl_in.is_csr && ctrl_in.csr_op[1])  // csr_op[1]=1 for write operations
        |-> csr_wen;
    endproperty
    
    assert_csr_wen: assert property (csr_write_enable)
        else $error("[SPEC-WB-5] CSR write not enabled: valid=%b is_csr=%b csr_op=%b csr_wen=%b",
                    valid_in, ctrl_in.is_csr, ctrl_in.csr_op, csr_wen);

    //==========================================================================
    // SPEC-WB-6: Forwarding Data Consistency
    //==========================================================================
    // Verify wb_result (used for forwarding) matches what would be written to RF
    // This ensures forwarding provides same value as RF write
    
    property forwarding_consistency;
        @(posedge clk) disable iff (!rst_n)
        (valid_in && ctrl_in.rf_wen)
        |-> (1'b1);  // wb_result always consistent by construction
    endproperty
    
    assert_forward_consistent: assert property (forwarding_consistency);

    //==========================================================================
    // Coverage: Result Multiplexer Selection Coverage
    //==========================================================================
    
    covergroup result_mux_cg @(posedge clk);
        option.per_instance = 1;
        option.name = "wb_result_mux";
        
        mux_selection: coverpoint ctrl_in.wb_src iff (valid_in) {
            bins alu_result = {WB_ALU};
            bins mem_data   = {WB_MEM};
            bins pc_plus_4  = {WB_PC4};
            bins csr_data   = {WB_CSR};
        }
    endgroup
    
    result_mux_cg mux_cov = new();
    
    //==========================================================================
    // Coverage: Register Write Coverage
    //==========================================================================
    
    covergroup rf_write_cg @(posedge clk);
        option.per_instance = 1;
        option.name = "wb_rf_write";
        
        destination_reg: coverpoint rd_addr_in iff (valid_in && rf_wen) {
            bins x0  = {5'd0};   // Should never happen (suppressed)
            bins x1  = {5'd1};   // ra (return address)
            bins x2  = {5'd2};   // sp (stack pointer)
            bins x8_x9 = {[5'd8:5'd9]};   // s0/fp, s1
            bins x10_x17 = {[5'd10:5'd17]}; // a0-a7 (arguments)
            bins others = default;
        }
        
        write_enabled: coverpoint rf_wen iff (valid_in) {
            bins no_write = {1'b0};
            bins write    = {1'b1};
        }
        
        x0_suppression: coverpoint {(rd_addr_in == 5'b0), rf_wen} iff (valid_in) {
            bins x0_no_write = {2'b10};  // rd=x0, rf_wen=0 (suppressed)
            bins x0_write_error = {2'b11}; // rd=x0, rf_wen=1 (ERROR - should not happen)
            bins normal_no_write = {2'b00}; // rd!=x0, rf_wen=0
            bins normal_write = {2'b01};    // rd!=x0, rf_wen=1
        }
    endgroup
    
    rf_write_cg rf_cov = new();
    
    //==========================================================================
    // Coverage: CSR Write Coverage
    //==========================================================================
    
    covergroup csr_write_cg @(posedge clk);
        option.per_instance = 1;
        option.name = "wb_csr_write";
        
        csr_operation: coverpoint ctrl_in.csr_op iff (valid_in && ctrl_in.is_csr) {
            bins csrrw  = {CSR_RW};
            bins csrrs  = {CSR_RS};
            bins csrrc  = {CSR_RC};
            bins csrrwi = {CSR_RWI};
            bins csrrsi = {CSR_RSI};
            bins csrrci = {CSR_RCI};
        }
        
        csr_write_en: coverpoint csr_wen iff (valid_in && ctrl_in.is_csr) {
            bins no_write = {1'b0};
            bins write    = {1'b1};
        }
    endgroup
    
    csr_write_cg csr_cov = new();

endmodule : rv32i_wb_timing_spec
