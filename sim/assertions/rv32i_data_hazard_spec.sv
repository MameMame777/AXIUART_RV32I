`timescale 1ns / 1ps

//==============================================================================
// RV32I Data Hazard & Forwarding Specification (SVA)
//==============================================================================
// Verifies RAW (Read-After-Write) hazard detection and forwarding correctness.
// Ensures pipeline forwarding paths maintain data coherency.
//==============================================================================

module rv32i_data_hazard_spec
    import rv32i_isa_pkg::*;
(
    input logic        clk,
    input logic        rst_n,
    
    // ID stage (register read)
    input logic [4:0]  id_rs1_addr,
    input logic [4:0]  id_rs2_addr,
    input logic        id_valid,
    
    // EX stage (ALU operation)
    input logic [31:0] ex_rs1_forwarded,
    input logic [31:0] ex_rs2_forwarded,
    input logic [31:0] ex_alu_result,
    input logic [4:0]  ex_rd_addr,
    input logic        ex_rf_wen,
    input logic        ex_valid,
    
    // MEM stage (memory access)
    input logic [31:0] mem_alu_result,
    input logic [31:0] mem_rs2_data,
    input logic [4:0]  mem_rd_addr,
    input logic        mem_rf_wen,
    input logic        mem_valid,
    
    // WB stage (writeback)
    input logic [31:0] wb_result,
    input logic [4:0]  wb_rd_addr,
    input logic        wb_rf_wen,
    input logic        wb_valid,
    
    // Register file
    input logic [31:0] regfile [0:31],
    
    // Forwarding control
    input logic [1:0]  forward_rs1,
    input logic [1:0]  forward_rs2
);

    //==========================================================================
    // ASSERTION 1: Register File Writeback Coherency
    //==========================================================================
    // When WB writes to register, next cycle read must see new value
    
    property wb_write_visible;
        logic [4:0] rd_addr_capture;
        logic [31:0] wr_data_capture;
        
        @(posedge clk) disable iff (!rst_n)
        (wb_rf_wen && wb_valid && wb_rd_addr != 5'b0, 
         rd_addr_capture = wb_rd_addr, 
         wr_data_capture = wb_result)
        |=>
        (regfile[rd_addr_capture] == wr_data_capture);
    endproperty
    
    assert_wb_write_visible: assert property (wb_write_visible)
        else $error("[HAZARD_SPEC] WB write to x%0d with 0x%h not visible in regfile", 
                    wb_rd_addr, wb_result);

    //==========================================================================
    // ASSERTION 2: EX-to-EX Forwarding Correctness
    //==========================================================================
    // When EX stage writes and next instruction reads same register,
    // forwarding must provide EX stage result
    
    sequence ex_writes_register(logic [4:0] rd);
        ex_rf_wen && ex_valid && (ex_rd_addr == rd) && (rd != 5'b0);
    endsequence
    
    property ex_forward_rs1_correct;
        logic [31:0] expected_value;
        logic [4:0] rd_capture;
        
        @(posedge clk) disable iff (!rst_n)
        (ex_writes_register(id_rs1_addr), 
         rd_capture = ex_rd_addr,
         expected_value = ex_alu_result)
        |=>
        ((id_rs1_addr == rd_capture) && id_valid) |-> (forward_rs1 == 2'b01);
    endproperty
    
    assert_ex_forward_rs1: assert property (ex_forward_rs1_correct)
        else $error("[HAZARD_SPEC] EX-to-EX forwarding failed for rs1=x%0d", id_rs1_addr);

    //==========================================================================
    // ASSERTION 3: MEM-to-EX Forwarding Correctness
    //==========================================================================
    
    property mem_forward_rs1_correct;
        @(posedge clk) disable iff (!rst_n)
        (mem_rf_wen && mem_valid && (mem_rd_addr == id_rs1_addr) && 
         (id_rs1_addr != 5'b0) && id_valid &&
         !(ex_writes_register(id_rs1_addr)))  // No EX stage conflict (higher priority)
        |->
        (forward_rs1 == 2'b10);
    endproperty
    
    assert_mem_forward_rs1: assert property (mem_forward_rs1_correct)
        else $error("[HAZARD_SPEC] MEM-to-EX forwarding failed for rs1=x%0d", id_rs1_addr);

    //==========================================================================
    // ASSERTION 4: Store Data Integrity
    //==========================================================================
    // For store instructions, rs2_data in MEM stage must equal forwarded rs2 from EX
    
    property store_data_integrity;
        logic [31:0] expected_rs2;
        
        @(posedge clk) disable iff (!rst_n)
        (ex_valid, expected_rs2 = ex_rs2_forwarded)
        |=>
        (mem_valid |-> (mem_rs2_data == expected_rs2));
    endproperty
    
    assert_store_data_integrity: assert property (store_data_integrity)
        else $error("[HAZARD_SPEC] @ %0t: Store rs2 mismatch - expected 0x%h, got 0x%h",
                    $time, $past(ex_rs2_forwarded), mem_rs2_data);

    //==========================================================================
    // ASSERTION 5: Address Calculation for Store Instructions
    //==========================================================================
    // ALU result must equal rs1 + immediate for store operations
    // This catches address calculation bugs
    
    `ifdef ENABLE_ASSERTIONS
    always @(posedge clk) begin
        if (ex_valid) begin
            // Log all EX stage operations with forwarded values
            $display("[HAZARD_SPEC] @ %0t: EX stage - rs1_fwd=0x%h, rs2_fwd=0x%h, alu_result=0x%h, rd=x%0d",
                     $time, ex_rs1_forwarded, ex_rs2_forwarded, ex_alu_result, ex_rd_addr);
        end
        
        if (mem_valid) begin
            // Log MEM stage addresses and data
            $display("[HAZARD_SPEC] @ %0t: MEM stage - addr=0x%h, rs2_data=0x%h, rd=x%0d",
                     $time, mem_alu_result, mem_rs2_data, mem_rd_addr);
        end
    end
    `endif

    //==========================================================================
    // COVERAGE: Forwarding Path Usage
    //==========================================================================
    
    cover_ex_forward_rs1: cover property (
        @(posedge clk) disable iff (!rst_n)
        forward_rs1 == 2'b01
    );
    
    cover_mem_forward_rs1: cover property (
        @(posedge clk) disable iff (!rst_n)
        forward_rs1 == 2'b10
    );
    
    cover_ex_forward_rs2: cover property (
        @(posedge clk) disable iff (!rst_n)
        forward_rs2 == 2'b01
    );
    
    cover_mem_forward_rs2: cover property (
        @(posedge clk) disable iff (!rst_n)
        forward_rs2 == 2'b10
    );

endmodule : rv32i_data_hazard_spec
