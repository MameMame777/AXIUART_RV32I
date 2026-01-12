`timescale 1ns / 1ps

//==============================================================================
// RV32I Pipeline Register Package
//==============================================================================
// Defines structures for pipeline registers between stages:
//   IF/ID  - Instruction Fetch to Decode
//   ID/EX  - Decode to Execute
//   EX/MEM - Execute to Memory
//   MEM/WB - Memory to Write Back
//
// These structures are instantiated as registers in rv32i_top.sv
// Modules contain only combinational logic; all sequential logic in top
//==============================================================================

package rv32i_pipeline_pkg;
    
    import rv32i_isa_pkg::*;
    
    //==========================================================================
    // IF/ID Pipeline Register
    //==========================================================================
    typedef struct packed {
        logic [31:0] pc;        // Program counter
        logic [31:0] insn;      // Instruction word
        logic        valid;     // Instruction valid (0 = bubble)
    } if_id_reg_t;
    
    //==========================================================================
    // ID/EX Pipeline Register
    //==========================================================================
    typedef struct packed {
        logic [31:0]   pc;           // Program counter (for AUIPC, JAL)
        logic [31:0]   insn;         // Instruction word (for debug)
        logic [31:0]   rs1_data;     // RS1 register value
        logic [31:0]   rs2_data;     // RS2 register value
        logic [31:0]   imm;          // Sign-extended immediate
        logic [31:0]   csr_rdata;    // CSR read value (for CSR instructions)
        logic [1:0]    forward_rs1;  // Forwarding control RS1 (00=RF, 01=EX, 10=MEM, 11=WB)
        logic [1:0]    forward_rs2;  // Forwarding control RS2 (00=RF, 01=EX, 10=MEM, 11=WB)
        decode_ctrl_t  ctrl;         // Control signals from decoder
        logic          valid;        // Instruction valid
    } id_ex_reg_t;
    
    //==========================================================================
    // EX/MEM Pipeline Register
    //==========================================================================
    typedef struct packed {
        logic [31:0]   pc;           // Program counter
        logic [31:0]   insn;         // Instruction word
        logic [31:0]   alu_result;   // ALU computation result (address for load/store)
        logic [31:0]   rs2_data;     // RS2 forwarded data (for stores)
        logic [31:0]   csr_rdata;    // CSR read value (pass-through)
        logic          branch_taken; // Branch condition result
        logic [31:0]   branch_target;// Branch/jump target address
        decode_ctrl_t  ctrl;         // Control signals
        logic          valid;        // Instruction valid
        // Debug trace fields (propagate to WB stage)
        logic [31:0]   rs1_value_debug;  // Source operand 1 (after forwarding)
        logic [31:0]   rs2_value_debug;  // Source operand 2 (after forwarding)
        logic [4:0]    rs1_addr_debug;   // Source register 1 address
        logic [4:0]    rs2_addr_debug;   // Source register 2 address
        logic [1:0]    forward_rs1_debug;// Forwarding control rs1
        logic [1:0]    forward_rs2_debug;// Forwarding control rs2
    } ex_mem_reg_t;
    
    //==========================================================================
    // MEM/WB Pipeline Register
    //==========================================================================
    typedef struct packed {
        logic [31:0]   pc;           // Program counter
        logic [31:0]   insn;         // Instruction word
        logic [31:0]   mem_data;     // Load result (aligned and sign-extended)
        logic [31:0]   alu_result;   // ALU result (pass-through)
        logic [31:0]   csr_rdata;    // CSR read value (pass-through)
        decode_ctrl_t  ctrl;         // Control signals
        logic          valid;        // Instruction valid
        logic          branch_taken; // Branch taken (for trace)
        // Debug trace fields (from EX stage)
        logic [31:0]   rs1_value_debug;  // Source operand 1 (after forwarding)
        logic [31:0]   rs2_value_debug;  // Source operand 2 (after forwarding)
        logic [4:0]    rs1_addr_debug;   // Source register 1 address
        logic [4:0]    rs2_addr_debug;   // Source register 2 address
        logic [1:0]    forward_rs1_debug;// Forwarding control rs1
        logic [1:0]    forward_rs2_debug;// Forwarding control rs2
    } mem_wb_reg_t;
    
    //==========================================================================
    // Forwarding Control Encoding
    //==========================================================================
    // Used by rv32i_hazard to control forwarding multiplexers in rv32i_ex
    typedef enum logic [1:0] {
        FWD_RF  = 2'b00,  // Forward from register file (ID stage, no hazard)
        FWD_EX  = 2'b01,  // Forward from EX stage result
        FWD_MEM = 2'b10,  // Forward from MEM stage result
        FWD_WB  = 2'b11   // Forward from WB stage result
    } forward_sel_e;
    
    //==========================================================================
    // Helper Functions
    //==========================================================================
    
    // Create bubble (NOP) for pipeline flush
    function automatic if_id_reg_t if_id_bubble();
        if_id_bubble.pc    = 32'h0;
        if_id_bubble.insn  = 32'h0000_0013;  // NOP (ADDI x0, x0, 0)
        if_id_bubble.valid = 1'b0;
    endfunction
    
    function automatic id_ex_reg_t id_ex_bubble();
        id_ex_bubble.pc           = 32'h0;
        id_ex_bubble.insn         = 32'h0000_0013;
        id_ex_bubble.rs1_data     = 32'h0;
        id_ex_bubble.rs2_data     = 32'h0;
        id_ex_bubble.imm          = 32'h0;
        id_ex_bubble.csr_rdata    = 32'h0;
        id_ex_bubble.forward_rs1  = 2'b00;
        id_ex_bubble.forward_rs2  = 2'b00;
        id_ex_bubble.ctrl         = '0;
        id_ex_bubble.valid        = 1'b0;
    endfunction
    
    function automatic ex_mem_reg_t ex_mem_bubble();
        ex_mem_bubble.pc            = 32'h0;
        ex_mem_bubble.insn          = 32'h0000_0013;
        ex_mem_bubble.alu_result    = 32'h0;
        ex_mem_bubble.rs2_data      = 32'h0;
        ex_mem_bubble.csr_rdata     = 32'h0;
        ex_mem_bubble.branch_taken  = 1'b0;
        ex_mem_bubble.branch_target = 32'h0;
        ex_mem_bubble.ctrl          = '0;
        ex_mem_bubble.valid         = 1'b0;
        // Debug trace fields
        ex_mem_bubble.rs1_value_debug   = 32'h0;
        ex_mem_bubble.rs2_value_debug   = 32'h0;
        ex_mem_bubble.rs1_addr_debug    = 5'h0;
        ex_mem_bubble.rs2_addr_debug    = 5'h0;
        ex_mem_bubble.forward_rs1_debug = 2'b00;
        ex_mem_bubble.forward_rs2_debug = 2'b00;
    endfunction
    
    function automatic mem_wb_reg_t mem_wb_bubble();
        mem_wb_bubble.pc         = 32'h0;
        mem_wb_bubble.insn       = 32'h0000_0013;
        mem_wb_bubble.mem_data   = 32'h0;
        mem_wb_bubble.alu_result = 32'h0;
        mem_wb_bubble.csr_rdata  = 32'h0;
        mem_wb_bubble.ctrl       = '0;
        mem_wb_bubble.valid      = 1'b0;
        mem_wb_bubble.branch_taken = 1'b0;
        // Debug trace fields
        mem_wb_bubble.rs1_value_debug   = 32'h0;
        mem_wb_bubble.rs2_value_debug   = 32'h0;
        mem_wb_bubble.rs1_addr_debug    = 5'h0;
        mem_wb_bubble.rs2_addr_debug    = 5'h0;
        mem_wb_bubble.forward_rs1_debug = 2'b00;
        mem_wb_bubble.forward_rs2_debug = 2'b00;
    endfunction
    
endpackage : rv32i_pipeline_pkg
