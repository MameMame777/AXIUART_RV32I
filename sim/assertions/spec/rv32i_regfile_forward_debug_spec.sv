`timescale 1ns / 1ps

//==============================================================================
// Register File & Forwarding Debug Assertion Module
//==============================================================================
// Critical debug module for investigating register addressing bugs
// Monitors register file reads/writes and forwarding paths
// Logs discrepancies between expected and actual register values
//==============================================================================

module rv32i_regfile_forward_debug_spec (
    input logic clk,
    input logic rst,
    
    // ID Stage - Decoder outputs
    input logic [31:0] id_pc,
    input logic [31:0] id_insn,
    input logic        id_valid,
    input logic [4:0]  id_rs1_addr,
    input logic [4:0]  id_rs2_addr,
    input logic [4:0]  id_rd_addr,
    input logic [31:0] id_rs1_data,
    input logic [31:0] id_rs2_data,
    
    // Forwarding control
    input logic [1:0]  forward_rs1_sel,
    input logic [1:0]  forward_rs2_sel,
    
    // EX Stage - Forwarded operands
    input logic [31:0] ex_pc,
    input logic [31:0] ex_insn,
    input logic        ex_valid,
    input logic [4:0]  ex_rs1_addr,
    input logic [4:0]  ex_rs2_addr,
    input logic [31:0] ex_rs1_forwarded,
    input logic [31:0] ex_rs2_forwarded,
    input logic [31:0] ex_alu_result,
    
    // Hazard detection
    input logic        id_rs1_match_ex,
    input logic        id_rs1_match_mem,
    input logic        id_rs1_match_wb,
    input logic        id_rs2_match_ex,
    input logic        id_rs2_match_mem,
    input logic        id_rs2_match_wb,
    
    // Producer stages
    input logic [4:0]  ex_rd_addr,
    input logic        ex_rf_wen,
    input logic [4:0]  mem_rd_addr,
    input logic        mem_rf_wen,
    input logic [4:0]  wb_rd_addr,
    input logic        wb_rf_wen,
    
    // WB Stage - Register writes
    input logic [4:0]  wb_waddr,
    input logic [31:0] wb_wdata,
    input logic        wb_wen,
    
    // Register file values (for reference)
    input logic [31:0] regfile_x23,
    input logic [31:0] regfile_x24
);

    //==========================================================================
    // CSV Logging for Pipeline Register Flow
    //==========================================================================
    
    integer fd_regfile;
    
    initial begin
        fd_regfile = $fopen("regfile_debug.csv", "w");
        $fwrite(fd_regfile, "Time,Stage,PC,Insn,rs1_addr,rs1_data,rs2_addr,rs2_data,rd_addr,fwd_rs1,fwd_rs2,x23_RF,x24_RF\n");
    end
    
    // Log ID stage register reads
    always @(posedge clk) begin
        if (!rst && id_valid) begin
            $fwrite(fd_regfile, "%0t,ID,0x%08h,0x%08h,%0d,0x%08h,%0d,0x%08h,%0d,%0d,%0d,0x%08h,0x%08h\n",
                    $time, id_pc, id_insn, id_rs1_addr, id_rs1_data, id_rs2_addr, id_rs2_data, 
                    id_rd_addr, forward_rs1_sel, forward_rs2_sel, regfile_x23, regfile_x24);
        end
    end
    
    // Log EX stage forwarded values
    always @(posedge clk) begin
        if (!rst && ex_valid) begin
            $fwrite(fd_regfile, "%0t,EX,0x%08h,0x%08h,%0d,0x%08h,%0d,0x%08h,0x%08h,,,0x%08h,0x%08h\n",
                    $time, ex_pc, ex_insn, ex_rs1_addr, ex_rs1_forwarded, ex_rs2_addr, ex_rs2_forwarded,
                    ex_alu_result, regfile_x23, regfile_x24);
        end
    end
    
    // Log WB stage register writes
    always @(posedge clk) begin
        if (!rst && wb_wen) begin
            $fwrite(fd_regfile, "%0t,WB,,,,,,%0d,0x%08h,,,0x%08h,0x%08h\n",
                    $time, wb_waddr, wb_wdata, regfile_x23, regfile_x24);
        end
    end
    
    //==========================================================================
    // Critical Bug Detection: x23/x24 Confusion
    //==========================================================================
    
    // Track when x23 is written
    logic x23_written;
    logic [31:0] x23_expected_value;
    
    always @(posedge clk) begin
        if (rst) begin
            x23_written <= 0;
            x23_expected_value <= 32'h0;
        end else if (wb_wen && wb_waddr == 5'd23) begin
            x23_written <= 1;
            x23_expected_value <= wb_wdata;
        end
    end
    
    // Detect if store instruction uses x23 but gets x24's value
    property p_store_uses_wrong_register;
        @(posedge clk) disable iff (rst)
        (ex_valid && ex_insn[6:0] == 7'b0100011 && // S-type (store)
         ex_rs1_addr == 5'd23 && x23_written) |->
        (ex_rs1_forwarded == x23_expected_value || 
         ex_rs1_forwarded == regfile_x23);
    endproperty
    
    assert property (p_store_uses_wrong_register) else
        $error("[REGFILE_BUG] Store at PC=0x%08h uses rs1=x%0d but got value 0x%08h (expected x23=0x%08h, RF_x23=0x%08h, RF_x24=0x%08h)",
               ex_pc, ex_rs1_addr, ex_rs1_forwarded, x23_expected_value, regfile_x23, regfile_x24);
    
    //==========================================================================
    // Decoder Verification: Ensure rs1/rs2 extracted correctly
    //==========================================================================
    
    property p_decoder_rs1_matches_instruction;
        @(posedge clk) disable iff (rst)
        id_valid |-> (id_rs1_addr == id_insn[19:15]);
    endproperty
    
    assert property (p_decoder_rs1_matches_instruction) else
        $error("[DECODER_BUG] PC=0x%08h: id_rs1_addr=%0d but insn[19:15]=%0d",
               id_pc, id_rs1_addr, id_insn[19:15]);
    
    property p_decoder_rs2_matches_instruction;
        @(posedge clk) disable iff (rst)
        id_valid |-> (id_rs2_addr == id_insn[24:20]);
    endproperty
    
    assert property (p_decoder_rs2_matches_instruction) else
        $error("[DECODER_BUG] PC=0x%08h: id_rs2_addr=%0d but insn[24:20]=%0d",
               id_pc, id_rs2_addr, id_insn[24:20]);
    
    property p_decoder_rd_matches_instruction;
        @(posedge clk) disable iff (rst)
        id_valid |-> (id_rd_addr == id_insn[11:7]);
    endproperty
    
    assert property (p_decoder_rd_matches_instruction) else
        $error("[DECODER_BUG] PC=0x%08h: id_rd_addr=%0d but insn[11:7]=%0d",
               id_pc, id_rd_addr, id_insn[11:7]);
    
    //==========================================================================
    // Forwarding Logic Verification
    //==========================================================================
    
    property p_forward_rs1_ex_implies_match;
        @(posedge clk) disable iff (rst)
        (forward_rs1_sel == 2'b01) |-> id_rs1_match_ex;
    endproperty
    
    assert property (p_forward_rs1_ex_implies_match) else
        $error("[FWD_BUG] PC=0x%08h: forward_rs1_sel=EX but id_rs1_match_ex=0 (rs1=%0d, ex_rd=%0d)",
               id_pc, id_rs1_addr, ex_rd_addr);
    
    property p_forward_rs1_match_implies_equal_addr;
        @(posedge clk) disable iff (rst)
        id_rs1_match_ex |-> (id_rs1_addr == ex_rd_addr && ex_rf_wen);
    endproperty
    
    assert property (p_forward_rs1_match_implies_equal_addr) else
        $error("[HAZARD_BUG] PC=0x%08h: id_rs1_match_ex=1 but rs1=%0d != ex_rd=%0d or ex_rf_wen=%0b",
               id_pc, id_rs1_addr, ex_rd_addr, ex_rf_wen);
    
    //==========================================================================
    // Register Write Address Verification
    //==========================================================================
    
    property p_wb_waddr_matches_wb_rd;
        @(posedge clk) disable iff (rst)
        wb_wen |-> (wb_waddr == wb_rd_addr);
    endproperty
    
    assert property (p_wb_waddr_matches_wb_rd) else
        $error("[WB_BUG] WB write address mismatch: wb_waddr=%0d but wb_rd_addr=%0d, writing 0x%08h",
               wb_waddr, wb_rd_addr, wb_wdata);
    
    //==========================================================================
    // Specific x23/x24 Value Tracking
    //==========================================================================
    
    // Detect if x24 write corrupts x23
    always @(posedge clk) begin
        if (!rst && wb_wen && wb_waddr == 5'd24) begin
            if (regfile_x23 != x23_expected_value && x23_written) begin
                $display("[CORRUPTION] Time=%0t: Writing x24=0x%08h caused x23 to change from 0x%08h to 0x%08h",
                         $time, wb_wdata, x23_expected_value, regfile_x23);
            end
        end
    end
    
    // Monitor x23 initialization sequence
    always @(posedge clk) begin
        if (!rst && wb_wen) begin
            if (wb_waddr == 5'd23) begin
                $display("[X23_WRITE] Time=%0t: x23 written with 0x%08h (prev=0x%08h)",
                         $time, wb_wdata, regfile_x23);
            end
            if (wb_waddr == 5'd24) begin
                $display("[X24_WRITE] Time=%0t: x24 written with 0x%08h (prev=0x%08h, x23=0x%08h)",
                         $time, wb_wdata, regfile_x24, regfile_x23);
            end
        end
    end
    
    //==========================================================================
    // Store Instruction Detailed Logging
    //==========================================================================
    
    always @(posedge clk) begin
        if (!rst && ex_valid && ex_insn[6:0] == 7'b0100011) begin
            $display("[STORE_DEBUG] Time=%0t PC=0x%08h Insn=0x%08h rs1=x%0d rs1_fwd=0x%08h rs2=x%0d rs2_fwd=0x%08h RF[23]=0x%08h RF[24]=0x%08h",
                     $time, ex_pc, ex_insn, ex_rs1_addr, ex_rs1_forwarded, ex_rs2_addr, ex_rs2_forwarded,
                     regfile_x23, regfile_x24);
        end
    end
    
    final begin
        $fclose(fd_regfile);
    end

endmodule : rv32i_regfile_forward_debug_spec
