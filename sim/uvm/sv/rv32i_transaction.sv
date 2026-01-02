`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// RV32I Transaction Class
//------------------------------------------------------------------------------
// Represents a single executed instruction captured from the trace buffer
//
// Author: GitHub Copilot
// Date: 2026-01-02
//------------------------------------------------------------------------------

class rv32i_transaction extends uvm_sequence_item;
    
    // Transaction fields
    rand bit [31:0] pc;           // Program counter
    rand bit [31:0] insn;         // Instruction
    rand bit [4:0]  rd_addr;      // Destination register address
    rand bit [31:0] rd_value;     // Destination register value
    bit [63:0]      timestamp;    // Simulation timestamp
    
    // UVM registration
    `uvm_object_utils_begin(rv32i_transaction)
        `uvm_field_int(pc, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(insn, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(rd_addr, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(rd_value, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(timestamp, UVM_ALL_ON | UVM_TIME)
    `uvm_object_utils_end
    
    function new(string name = "rv32i_transaction");
        super.new(name);
    endfunction
    
    //--------------------------------------------------------------------------
    // Helper Functions - Instruction Decoding
    //--------------------------------------------------------------------------
    
    function bit [6:0] get_opcode();
        return insn[6:0];
    endfunction
    
    function bit [2:0] get_funct3();
        return insn[14:12];
    endfunction
    
    function bit [6:0] get_funct7();
        return insn[31:25];
    endfunction
    
    function bit is_alu_op();
        bit [6:0] opcode = get_opcode();
        return (opcode == 7'b0110011) ||  // R-type ALU
               (opcode == 7'b0010011);    // I-type ALU
    endfunction
    
    function bit is_load();
        return (get_opcode() == 7'b0000011);
    endfunction
    
    function bit is_store();
        return (get_opcode() == 7'b0100011);
    endfunction
    
    function bit is_branch();
        return (get_opcode() == 7'b1100011);
    endfunction
    
    function bit is_jal();
        return (get_opcode() == 7'b1101111);
    endfunction
    
    function bit is_jalr();
        return (get_opcode() == 7'b1100111);
    endfunction
    
    function bit is_lui();
        return (get_opcode() == 7'b0110111);
    endfunction
    
    function bit is_auipc();
        return (get_opcode() == 7'b0010111);
    endfunction
    
    function bit is_system();
        return (get_opcode() == 7'b1110011);
    endfunction
    
    function bit is_ebreak();
        return (insn == 32'h00100073);
    endfunction
    
    function bit writes_register();
        // Check if instruction writes to a destination register
        // Stores, branches, and x0 writes don't count
        if (is_store() || is_branch()) return 0;
        if (rd_addr == 5'b00000) return 0;
        return 1;
    endfunction
    
    //--------------------------------------------------------------------------
    // Convert to String
    //--------------------------------------------------------------------------
    
    function string convert2string();
        string s;
        string insn_name;
        
        // Decode instruction name
        if (is_ebreak())      insn_name = "EBREAK";
        else if (is_jal())    insn_name = "JAL";
        else if (is_jalr())   insn_name = "JALR";
        else if (is_lui())    insn_name = "LUI";
        else if (is_auipc())  insn_name = "AUIPC";
        else if (is_load())   insn_name = "LOAD";
        else if (is_store())  insn_name = "STORE";
        else if (is_branch()) insn_name = "BRANCH";
        else if (is_alu_op()) insn_name = "ALU";
        else if (is_system()) insn_name = "SYSTEM";
        else                  insn_name = "UNKNOWN";
        
        s = $sformatf("RV32I Transaction: PC=0x%08h INSN=0x%08h (%s) rd=x%0d rd_value=0x%08h @ %0t",
                      pc, insn, insn_name, rd_addr, rd_value, timestamp);
        
        return s;
    endfunction
    
endclass
