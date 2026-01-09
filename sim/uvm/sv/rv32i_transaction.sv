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
    
    function bit is_ecall();
        return (insn == 32'h00000073);
    endfunction
    
    function bit is_mret();
        return (insn == 32'h30200073);
    endfunction
    
    function bit writes_register();
        // Check if instruction writes to a destination register
        // Stores, branches, and x0 writes don't count
        if (is_store() || is_branch()) return 0;
        if (rd_addr == 5'b00000) return 0;
        return 1;
    endfunction
    
    //--------------------------------------------------------------------------
    // Detailed Instruction Decoder
    //--------------------------------------------------------------------------
    
    function string decode_instruction();
        bit [6:0] opcode = get_opcode();
        bit [2:0] funct3 = get_funct3();
        bit [6:0] funct7 = get_funct7();
        
        case (opcode)
            7'b0110011: begin // R-type
                case (funct3)
                    3'b000: return (funct7[5]) ? "SUB" : "ADD";
                    3'b001: return "SLL";
                    3'b010: return "SLT";
                    3'b011: return "SLTU";
                    3'b100: return "XOR";
                    3'b101: return (funct7[5]) ? "SRA" : "SRL";
                    3'b110: return "OR";
                    3'b111: return "AND";
                endcase
            end
            7'b0010011: begin // I-type ALU
                case (funct3)
                    3'b000: return "ADDI";
                    3'b001: return "SLLI";
                    3'b010: return "SLTI";
                    3'b011: return "SLTIU";
                    3'b100: return "XORI";
                    3'b101: return (funct7[5]) ? "SRAI" : "SRLI";
                    3'b110: return "ORI";
                    3'b111: return "ANDI";
                endcase
            end
            7'b0000011: begin // Load
                case (funct3)
                    3'b000: return "LB";
                    3'b001: return "LH";
                    3'b010: return "LW";
                    3'b100: return "LBU";
                    3'b101: return "LHU";
                    default: return "LOAD?";
                endcase
            end
            7'b0100011: begin // Store
                case (funct3)
                    3'b000: return "SB";
                    3'b001: return "SH";
                    3'b010: return "SW";
                    default: return "STORE?";
                endcase
            end
            7'b1100011: begin // Branch
                case (funct3)
                    3'b000: return "BEQ";
                    3'b001: return "BNE";
                    3'b100: return "BLT";
                    3'b101: return "BGE";
                    3'b110: return "BLTU";
                    3'b111: return "BGEU";
                    default: return "BRANCH?";
                endcase
            end
            7'b1101111: return "JAL";
            7'b1100111: return "JALR";
            7'b0110111: return "LUI";
            7'b0010111: return "AUIPC";
            7'b0001111: return "FENCE";
            7'b1110011: begin // System
                if (insn == 32'h00000073) return "ECALL";
                if (insn == 32'h00100073) return "EBREAK";
                if (insn == 32'h30200073) return "MRET";
                case (funct3)
                    3'b001: return "CSRRW";
                    3'b010: return "CSRRS";
                    3'b011: return "CSRRC";
                    3'b101: return "CSRRWI";
                    3'b110: return "CSRRSI";
                    3'b111: return "CSRRCI";
                    default: return "SYSTEM?";
                endcase
            end
            default: return "UNKNOWN";
        endcase
    endfunction
    
    function string get_operands();
        bit [6:0] opcode = get_opcode();
        bit [2:0] funct3 = get_funct3();
        bit [4:0] rs1    = insn[19:15];
        bit [4:0] rs2    = insn[24:20];
        bit [4:0] rd     = insn[11:7];
        bit signed [11:0] imm12 = insn[31:20];
        bit signed [12:0] imm13;
        bit signed [20:0] imm21;
        bit [31:0] imm20;
        
        case (opcode)
            7'b0110011: // R-type: rd, rs1, rs2
                return $sformatf("x%0d, x%0d, x%0d", rd, rs1, rs2);
            7'b0010011: // I-type ALU: rd, rs1, imm
                return $sformatf("x%0d, x%0d, %0d", rd, rs1, $signed(imm12));
            7'b0000011: // Load: rd, imm(rs1)
                return $sformatf("x%0d, %0d(x%0d)", rd, $signed(imm12), rs1);
            7'b0100011: begin // Store: rs2, imm(rs1)
                imm12 = {insn[31:25], insn[11:7]};
                return $sformatf("x%0d, %0d(x%0d)", rs2, $signed(imm12), rs1);
            end
            7'b1100011: begin // Branch: rs1, rs2, imm
                imm13 = {insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};
                return $sformatf("x%0d, x%0d, %0d", rs1, rs2, $signed(imm13));
            end
            7'b1101111: begin // JAL: rd, imm
                imm21 = {insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};
                return $sformatf("x%0d, %0d", rd, $signed(imm21));
            end
            7'b1100111: // JALR: rd, imm(rs1)
                return $sformatf("x%0d, %0d(x%0d)", rd, $signed(imm12), rs1);
            7'b0110111, 7'b0010111: begin // LUI/AUIPC: rd, imm
                imm20 = {insn[31:12], 12'h000};
                return $sformatf("x%0d, 0x%05x", rd, imm20[31:12]);
            end
            7'b1110011: begin // System/CSR
                if (insn == 32'h00000073 || insn == 32'h00100073 || insn == 32'h30200073)
                    return "";
                if (funct3[2]) // CSR immediate
                    return $sformatf("x%0d, 0x%03x, %0d", rd, imm12, rs1);
                else // CSR register
                    return $sformatf("x%0d, 0x%03x, x%0d", rd, imm12, rs1);
            end
            default: return "";
        endcase
    endfunction
    
    //--------------------------------------------------------------------------
    // Convert to String
    //--------------------------------------------------------------------------
    
    function string convert2string();
        string s;
        string insn_name = decode_instruction();
        string operands = get_operands();
        
        if (operands != "")
            s = $sformatf("PC=0x%08h: %-6s %s (rd=x%0d=0x%08h)", pc, insn_name, operands, rd_addr, rd_value);
        else
            s = $sformatf("PC=0x%08h: %-6s (rd=x%0d=0x%08h)", pc, insn_name, rd_addr, rd_value);
        
        return s;
    endfunction
    
endclass
