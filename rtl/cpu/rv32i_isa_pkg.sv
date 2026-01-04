`timescale 1ns / 1ps

//==============================================================================
// RISC-V RV32I ISA Package
//==============================================================================
// Auto-generated from isa/rv32i_isa.json
// RV32I Base Integer Instruction Set (Version 2.1)
// 
// Architecture: 5-stage pipeline (IF/ID/EX/MEM/WB)
// Registers: 32 x 32-bit (x0 hardwired to zero)
// Memory: Byte-addressed, 8KB internal RAM
// Branch: Stall + flush (no speculation, no delay slots)
//==============================================================================

package rv32i_isa_pkg;

    //==========================================================================
    // Architecture Parameters
    //==========================================================================
    
    parameter int DATA_WIDTH = 32;
    parameter int ADDR_WIDTH = 32;
    parameter int INSN_WIDTH = 32;
    parameter int REG_COUNT = 32;
    parameter int REG_ADDR_WIDTH = 5;
    
    //==========================================================================
    // Instruction Formats
    //==========================================================================
    
    // R-type: Register-register operations
    typedef struct packed {
        logic [6:0]  funct7;
        logic [4:0]  rs2;
        logic [4:0]  rs1;
        logic [2:0]  funct3;
        logic [4:0]  rd;
        logic [6:0]  opcode;
    } r_type_t;
    
    // I-type: Immediate operations, loads
    typedef struct packed {
        logic [11:0] imm;
        logic [4:0]  rs1;
        logic [2:0]  funct3;
        logic [4:0]  rd;
        logic [6:0]  opcode;
    } i_type_t;
    
    // S-type: Store operations
    typedef struct packed {
        logic [6:0]  imm_11_5;
        logic [4:0]  rs2;
        logic [4:0]  rs1;
        logic [2:0]  funct3;
        logic [4:0]  imm_4_0;
        logic [6:0]  opcode;
    } s_type_t;
    
    // B-type: Branch operations
    typedef struct packed {
        logic        imm_12;
        logic [5:0]  imm_10_5;
        logic [4:0]  rs2;
        logic [4:0]  rs1;
        logic [2:0]  funct3;
        logic [3:0]  imm_4_1;
        logic        imm_11;
        logic [6:0]  opcode;
    } b_type_t;
    
    // U-type: Upper immediate (LUI, AUIPC)
    typedef struct packed {
        logic [19:0] imm;
        logic [4:0]  rd;
        logic [6:0]  opcode;
    } u_type_t;
    
    // J-type: Jump operations (JAL)
    typedef struct packed {
        logic        imm_20;
        logic [9:0]  imm_10_1;
        logic        imm_11;
        logic [7:0]  imm_19_12;
        logic [4:0]  rd;
        logic [6:0]  opcode;
    } j_type_t;
    
    //==========================================================================
    // Opcode Definitions (7-bit)
    //==========================================================================
    
    typedef enum logic [6:0] {
        OPC_LOAD     = 7'b0000011,  // LB, LH, LW, LBU, LHU
        OPC_MISC_MEM = 7'b0001111,  // FENCE, FENCE.I
        OPC_OP_IMM   = 7'b0010011,  // ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
        OPC_AUIPC    = 7'b0010111,  // AUIPC
        OPC_STORE    = 7'b0100011,  // SB, SH, SW
        OPC_OP       = 7'b0110011,  // ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
        OPC_LUI      = 7'b0110111,  // LUI
        OPC_BRANCH   = 7'b1100011,  // BEQ, BNE, BLT, BGE, BLTU, BGEU
        OPC_JALR     = 7'b1100111,  // JALR
        OPC_JAL      = 7'b1101111,  // JAL
        OPC_SYSTEM   = 7'b1110011   // ECALL, EBREAK, CSR*
    } opcode_e;
    
    //==========================================================================
    // Funct3 Definitions
    //==========================================================================
    
    // ALU Immediate Operations (OP-IMM)
    typedef enum logic [2:0] {
        F3_ADDI  = 3'b000,
        F3_SLTI  = 3'b010,
        F3_SLTIU = 3'b011,
        F3_XORI  = 3'b100,
        F3_ORI   = 3'b110,
        F3_ANDI  = 3'b111,
        F3_SLLI  = 3'b001,
        F3_SRLI  = 3'b101  // SRLI/SRAI distinguished by funct7
    } funct3_op_imm_e;
    
    // ALU Register Operations (OP)
    typedef enum logic [2:0] {
        F3_ADD  = 3'b000,  // ADD/SUB distinguished by funct7
        F3_SLL  = 3'b001,
        F3_SLT  = 3'b010,
        F3_SLTU = 3'b011,
        F3_XOR  = 3'b100,
        F3_SRL  = 3'b101,  // SRL/SRA distinguished by funct7
        F3_OR   = 3'b110,
        F3_AND  = 3'b111
    } funct3_op_e;
    
    // Load Operations (LOAD)
    typedef enum logic [2:0] {
        F3_LB  = 3'b000,
        F3_LH  = 3'b001,
        F3_LW  = 3'b010,
        F3_LBU = 3'b100,
        F3_LHU = 3'b101
    } funct3_load_e;
    
    // Store Operations (STORE)
    typedef enum logic [2:0] {
        F3_SB = 3'b000,
        F3_SH = 3'b001,
        F3_SW = 3'b010
    } funct3_store_e;
    
    // Branch Operations (BRANCH)
    typedef enum logic [2:0] {
        F3_BEQ  = 3'b000,
        F3_BNE  = 3'b001,
        F3_BLT  = 3'b100,
        F3_BGE  = 3'b101,
        F3_BLTU = 3'b110,
        F3_BGEU = 3'b111
    } funct3_branch_e;
    
    // System Operations (SYSTEM)
    typedef enum logic [2:0] {
        F3_PRIV  = 3'b000,  // ECALL, EBREAK, MRET, etc.
        F3_CSRRW = 3'b001,
        F3_CSRRS = 3'b010,
        F3_CSRRC = 3'b011,
        F3_CSRRWI = 3'b101,
        F3_CSRRSI = 3'b110,
        F3_CSRRCI = 3'b111
    } funct3_system_e;
    
    // CSR Operations
    typedef enum logic [2:0] {
        CSR_RW  = 3'd0,  // CSRRW:  Atomic Read/Write
        CSR_RS  = 3'd1,  // CSRRS:  Atomic Read and Set Bits
        CSR_RC  = 3'd2,  // CSRRC:  Atomic Read and Clear Bits
        CSR_RWI = 3'd3,  // CSRRWI: Immediate variant of CSRRW
        CSR_RSI = 3'd4,  // CSRRSI: Immediate variant of CSRRS
        CSR_RCI = 3'd5   // CSRRCI: Immediate variant of CSRRC
    } csr_op_e;
    
    //==========================================================================
    // Funct7 Definitions
    //==========================================================================
    
    typedef enum logic [6:0] {
        F7_NORMAL = 7'b0000000,  // ADD, SRL, SLL, etc.
        F7_ALT    = 7'b0100000   // SUB, SRA
    } funct7_e;
    
    //==========================================================================
    // Special System Instructions
    //==========================================================================
    
    localparam logic [31:0] INSN_MRET = 32'h30200073;  // Machine Return
    
    //==========================================================================
    // Complete Instruction Encodings (for exact matching)
    //==========================================================================
    
    localparam logic [31:0] INSN_ECALL  = 32'h00000073;  // ECALL
    localparam logic [31:0] INSN_EBREAK = 32'h00100073;  // EBREAK
    localparam logic [31:0] INSN_FENCE  = 32'h0000000F;  // FENCE (simplified)
    localparam logic [31:0] INSN_NOP    = 32'h00000013;  // ADDI x0, x0, 0
    
    //==========================================================================
    // Control Signal Types
    //==========================================================================
    
    // ALU operation types
    typedef enum logic [3:0] {
        ALU_ADD  = 4'd0,
        ALU_SUB  = 4'd1,
        ALU_SLL  = 4'd2,
        ALU_SLT  = 4'd3,
        ALU_SLTU = 4'd4,
        ALU_XOR  = 4'd5,
        ALU_SRL  = 4'd6,
        ALU_SRA  = 4'd7,
        ALU_OR   = 4'd8,
        ALU_AND  = 4'd9,
        ALU_COPY_RS1 = 4'd10,  // Pass rs1 through (for AUIPC base)
        ALU_COPY_IMM = 4'd11   // Pass immediate through (for LUI)
    } alu_op_e;
    
    // Branch comparison types
    typedef enum logic [2:0] {
        BR_EQ  = 3'd0,  // BEQ
        BR_NE  = 3'd1,  // BNE
        BR_LT  = 3'd2,  // BLT
        BR_GE  = 3'd3,  // BGE
        BR_LTU = 3'd4,  // BLTU
        BR_GEU = 3'd5   // BGEU
    } branch_op_e;
    
    // Memory access width
    typedef enum logic [1:0] {
        MEM_BYTE = 2'd0,  // 8-bit
        MEM_HALF = 2'd1,  // 16-bit
        MEM_WORD = 2'd2   // 32-bit
    } mem_width_e;
    
    // Writeback source selection
    typedef enum logic [1:0] {
        WB_ALU = 2'd0,   // ALU result
        WB_MEM = 2'd1,   // Memory data
        WB_PC4 = 2'd2,   // PC + 4 (for JAL/JALR)
        WB_CSR = 2'd3    // CSR data (for CSR instructions)
    } wb_src_e;
    
    //==========================================================================
    // Decoder Control Signals Structure
    //==========================================================================
    
    typedef struct packed {
        // Register file
        logic        rf_wen;          // Register file write enable
        logic [4:0]  rd_addr;         // Destination register
        logic [4:0]  rs1_addr;        // Source register 1
        logic [4:0]  rs2_addr;        // Source register 2
        
        // ALU
        logic        alu_src1_pc;     // ALU source 1: 0=rs1, 1=PC
        logic        alu_src2_imm;    // ALU source 2: 0=rs2, 1=immediate
        alu_op_e     alu_op;          // ALU operation
        
        // Memory
        logic        mem_read;        // Memory read enable
        logic        mem_write;       // Memory write enable
        mem_width_e  mem_width;       // Memory access width
        logic        mem_sign_ext;    // Sign-extend loaded data
        
        // Branch/Jump
        logic        is_branch;       // Is branch instruction
        logic        is_jump;         // Is jump instruction (JAL/JALR)
        logic        is_jalr;         // Is JALR (base from register)
        branch_op_e  branch_op;       // Branch comparison type
        
        // Writeback
        wb_src_e     wb_src;          // Writeback source selection
        
        // System
        logic        is_ecall;        // ECALL instruction
        logic        is_ebreak;       // EBREAK instruction (breakpoint)
        logic        is_fence;        // FENCE instruction
        logic        is_mret;         // MRET instruction (machine return)
        
        // CSR
        logic        is_csr;          // CSR instruction (any variant)
        csr_op_e     csr_op;          // CSR operation type
        logic [11:0] csr_addr;        // CSR address (12 bits)
        logic        csr_imm_mode;    // CSR uses immediate (CSRRWI/CSRRSI/CSRRCI)
        
        // Immediate value (sign-extended)
        logic [31:0] immediate;
        
        // Illegal instruction
        logic        illegal;
    } decode_ctrl_t;
    
    //==========================================================================
    // Helper Functions
    //==========================================================================
    
    // Extract immediate from I-type instruction
    function automatic logic [31:0] get_i_imm(logic [31:0] insn);
        i_type_t i_insn;
        i_insn = insn;
        return {{20{i_insn.imm[11]}}, i_insn.imm};  // Sign-extend
    endfunction
    
    // Extract immediate from S-type instruction
    function automatic logic [31:0] get_s_imm(logic [31:0] insn);
        s_type_t s_insn;
        s_insn = insn;
        return {{20{s_insn.imm_11_5[6]}}, s_insn.imm_11_5, s_insn.imm_4_0};
    endfunction
    
    // Extract immediate from B-type instruction
    function automatic logic [31:0] get_b_imm(logic [31:0] insn);
        b_type_t b_insn;
        b_insn = insn;
        return {{19{b_insn.imm_12}}, b_insn.imm_12, b_insn.imm_11, 
                b_insn.imm_10_5, b_insn.imm_4_1, 1'b0};
    endfunction
    
    // Extract immediate from U-type instruction
    function automatic logic [31:0] get_u_imm(logic [31:0] insn);
        u_type_t u_insn;
        u_insn = insn;
        return {u_insn.imm, 12'b0};  // Upper 20 bits, lower 12 bits = 0
    endfunction
    
    // Extract immediate from J-type instruction
    function automatic logic [31:0] get_j_imm(logic [31:0] insn);
        j_type_t j_insn;
        j_insn = insn;
        return {{11{j_insn.imm_20}}, j_insn.imm_20, j_insn.imm_19_12,
                j_insn.imm_11, j_insn.imm_10_1, 1'b0};
    endfunction
    
    // Decode instruction to control signals
    function automatic decode_ctrl_t decode_insn(logic [31:0] insn);
        decode_ctrl_t ctrl;
        r_type_t r_insn;
        i_type_t i_insn;
        s_type_t s_insn;
        b_type_t b_insn;
        u_type_t u_insn;
        j_type_t j_insn;
        
        // Default values (NOP-like behavior)
        ctrl = '{
            rf_wen: 1'b0,
            rd_addr: 5'b0,
            rs1_addr: 5'b0,
            rs2_addr: 5'b0,
            alu_src1_pc: 1'b0,
            alu_src2_imm: 1'b0,
            alu_op: ALU_ADD,
            mem_read: 1'b0,
            mem_write: 1'b0,
            mem_width: MEM_WORD,
            mem_sign_ext: 1'b0,
            is_branch: 1'b0,
            is_jump: 1'b0,
            is_jalr: 1'b0,
            branch_op: BR_EQ,
            wb_src: WB_ALU,
            is_ecall: 1'b0,
            is_ebreak: 1'b0,
            is_fence: 1'b0,
            immediate: 32'b0,
            illegal: 1'b0
        };
        
        // Parse instruction formats
        r_insn = insn;
        i_insn = insn;
        s_insn = insn;
        b_insn = insn;
        u_insn = insn;
        j_insn = insn;
        
        // Common register addresses
        ctrl.rd_addr = i_insn.rd;
        ctrl.rs1_addr = i_insn.rs1;
        ctrl.rs2_addr = r_insn.rs2;
        
        // Decode by opcode
        case (i_insn.opcode)
            OPC_LUI: begin
                ctrl.rf_wen = 1'b1;
                ctrl.alu_op = ALU_COPY_IMM;
                ctrl.alu_src2_imm = 1'b1;
                ctrl.immediate = get_u_imm(insn);
            end
            
            OPC_AUIPC: begin
                ctrl.rf_wen = 1'b1;
                ctrl.alu_op = ALU_ADD;
                ctrl.alu_src1_pc = 1'b1;
                ctrl.alu_src2_imm = 1'b1;
                ctrl.immediate = get_u_imm(insn);
            end
            
            OPC_JAL: begin
                ctrl.rf_wen = 1'b1;
                ctrl.is_jump = 1'b1;
                ctrl.wb_src = WB_PC4;
                ctrl.immediate = get_j_imm(insn);
            end
            
            OPC_JALR: begin
                ctrl.rf_wen = 1'b1;
                ctrl.is_jump = 1'b1;
                ctrl.is_jalr = 1'b1;
                ctrl.wb_src = WB_PC4;
                ctrl.immediate = get_i_imm(insn);
            end
            
            OPC_BRANCH: begin
                ctrl.is_branch = 1'b1;
                ctrl.immediate = get_b_imm(insn);
                case (i_insn.funct3)
                    F3_BEQ:  ctrl.branch_op = BR_EQ;
                    F3_BNE:  ctrl.branch_op = BR_NE;
                    F3_BLT:  ctrl.branch_op = BR_LT;
                    F3_BGE:  ctrl.branch_op = BR_GE;
                    F3_BLTU: ctrl.branch_op = BR_LTU;
                    F3_BGEU: ctrl.branch_op = BR_GEU;
                    default: ctrl.illegal = 1'b1;
                endcase
            end
            
            OPC_LOAD: begin
                ctrl.rf_wen = 1'b1;
                ctrl.mem_read = 1'b1;
                ctrl.alu_src2_imm = 1'b1;
                ctrl.wb_src = WB_MEM;
                ctrl.immediate = get_i_imm(insn);
                case (i_insn.funct3)
                    F3_LB: begin
                        ctrl.mem_width = MEM_BYTE;
                        ctrl.mem_sign_ext = 1'b1;
                    end
                    F3_LH: begin
                        ctrl.mem_width = MEM_HALF;
                        ctrl.mem_sign_ext = 1'b1;
                    end
                    F3_LW: begin
                        ctrl.mem_width = MEM_WORD;
                    end
                    F3_LBU: begin
                        ctrl.mem_width = MEM_BYTE;
                        ctrl.mem_sign_ext = 1'b0;
                    end
                    F3_LHU: begin
                        ctrl.mem_width = MEM_HALF;
                        ctrl.mem_sign_ext = 1'b0;
                    end
                    default: ctrl.illegal = 1'b1;
                endcase
            end
            
            OPC_STORE: begin
                ctrl.mem_write = 1'b1;
                ctrl.alu_src2_imm = 1'b1;
                ctrl.immediate = get_s_imm(insn);
                case (i_insn.funct3)
                    F3_SB: ctrl.mem_width = MEM_BYTE;
                    F3_SH: ctrl.mem_width = MEM_HALF;
                    F3_SW: ctrl.mem_width = MEM_WORD;
                    default: ctrl.illegal = 1'b1;
                endcase
            end
            
            OPC_OP_IMM: begin
                ctrl.rf_wen = 1'b1;
                ctrl.alu_src2_imm = 1'b1;
                ctrl.immediate = get_i_imm(insn);
                case (i_insn.funct3)
                    F3_ADDI:  ctrl.alu_op = ALU_ADD;
                    F3_SLTI:  ctrl.alu_op = ALU_SLT;
                    F3_SLTIU: ctrl.alu_op = ALU_SLTU;
                    F3_XORI:  ctrl.alu_op = ALU_XOR;
                    F3_ORI:   ctrl.alu_op = ALU_OR;
                    F3_ANDI:  ctrl.alu_op = ALU_AND;
                    F3_SLLI: begin
                        ctrl.alu_op = ALU_SLL;
                        if (r_insn.funct7 != F7_NORMAL) ctrl.illegal = 1'b1;
                    end
                    F3_SRLI: begin
                        if (r_insn.funct7 == F7_NORMAL)
                            ctrl.alu_op = ALU_SRL;
                        else if (r_insn.funct7 == F7_ALT)
                            ctrl.alu_op = ALU_SRA;
                        else
                            ctrl.illegal = 1'b1;
                    end
                    default: ctrl.illegal = 1'b1;
                endcase
            end
            
            OPC_OP: begin
                ctrl.rf_wen = 1'b1;
                case (i_insn.funct3)
                    F3_ADD: begin
                        if (r_insn.funct7 == F7_NORMAL)
                            ctrl.alu_op = ALU_ADD;
                        else if (r_insn.funct7 == F7_ALT)
                            ctrl.alu_op = ALU_SUB;
                        else
                            ctrl.illegal = 1'b1;
                    end
                    F3_SLL: begin
                        ctrl.alu_op = ALU_SLL;
                        if (r_insn.funct7 != F7_NORMAL) ctrl.illegal = 1'b1;
                    end
                    F3_SLT: begin
                        ctrl.alu_op = ALU_SLT;
                        if (r_insn.funct7 != F7_NORMAL) ctrl.illegal = 1'b1;
                    end
                    F3_SLTU: begin
                        ctrl.alu_op = ALU_SLTU;
                        if (r_insn.funct7 != F7_NORMAL) ctrl.illegal = 1'b1;
                    end
                    F3_XOR: begin
                        ctrl.alu_op = ALU_XOR;
                        if (r_insn.funct7 != F7_NORMAL) ctrl.illegal = 1'b1;
                    end
                    F3_SRL: begin
                        if (r_insn.funct7 == F7_NORMAL)
                            ctrl.alu_op = ALU_SRL;
                        else if (r_insn.funct7 == F7_ALT)
                            ctrl.alu_op = ALU_SRA;
                        else
                            ctrl.illegal = 1'b1;
                    end
                    F3_OR: begin
                        ctrl.alu_op = ALU_OR;
                        if (r_insn.funct7 != F7_NORMAL) ctrl.illegal = 1'b1;
                    end
                    F3_AND: begin
                        ctrl.alu_op = ALU_AND;
                        if (r_insn.funct7 != F7_NORMAL) ctrl.illegal = 1'b1;
                    end
                    default: ctrl.illegal = 1'b1;
                endcase
            end
            
            OPC_MISC_MEM: begin
                // FENCE - treat as NOP in simple implementation
                ctrl.is_fence = 1'b1;
            end
            
            OPC_SYSTEM: begin
                if (insn == INSN_ECALL) begin
                    ctrl.is_ecall = 1'b1;
                end else if (insn == INSN_EBREAK) begin
                    ctrl.is_ebreak = 1'b1;
                end else if (insn == INSN_MRET) begin
                    ctrl.is_mret = 1'b1;
                end else begin
                    // CSR instructions
                    case (i_insn.funct3)
                        F3_CSRRW, F3_CSRRS, F3_CSRRC: begin
                            ctrl.is_csr = 1'b1;
                            ctrl.rf_wen = 1'b1;  // rd gets old CSR value
                            ctrl.wb_src = WB_CSR;
                            ctrl.csr_addr = i_insn.imm[11:0];  // CSR address from immediate field
                            ctrl.csr_imm_mode = 1'b0;  // Register source (rs1)
                            
                            case (i_insn.funct3)
                                F3_CSRRW: ctrl.csr_op = CSR_RW;
                                F3_CSRRS: ctrl.csr_op = CSR_RS;
                                F3_CSRRC: ctrl.csr_op = CSR_RC;
                                default:  ctrl.csr_op = CSR_RW;
                            endcase
                        end
                        
                        F3_CSRRWI, F3_CSRRSI, F3_CSRRCI: begin
                            ctrl.is_csr = 1'b1;
                            ctrl.rf_wen = 1'b1;  // rd gets old CSR value
                            ctrl.wb_src = WB_CSR;
                            ctrl.csr_addr = i_insn.imm[11:0];  // CSR address from immediate field
                            ctrl.csr_imm_mode = 1'b1;  // Immediate source (rs1 field as 5-bit uimm)
                            
                            case (i_insn.funct3)
                                F3_CSRRWI: ctrl.csr_op = CSR_RWI;
                                F3_CSRRSI: ctrl.csr_op = CSR_RSI;
                                F3_CSRRCI: ctrl.csr_op = CSR_RCI;
                                default:   ctrl.csr_op = CSR_RWI;
                            endcase
                            
                            // For immediate variants, rs1 field contains 5-bit zero-extended immediate
                            // Store in immediate field for pipeline (zero-extended, not sign-extended)
                            ctrl.immediate = {27'b0, i_insn.rs1};
                        end
                        
                        default: begin
                            ctrl.illegal = 1'b1;
                        end
                    endcase
                end
            end
            
            default: begin
                ctrl.illegal = 1'b1;
            end
        endcase
        
        // x0 writes are legal but ignored (handled in register file)
        
        return ctrl;
    endfunction
    
    //==========================================================================
    // ABI Register Names (for debug/trace)
    //==========================================================================
    
    function automatic string get_reg_name(logic [4:0] reg_addr);
        case (reg_addr)
            5'd0:  return "zero";
            5'd1:  return "ra";
            5'd2:  return "sp";
            5'd3:  return "gp";
            5'd4:  return "tp";
            5'd5:  return "t0";
            5'd6:  return "t1";
            5'd7:  return "t2";
            5'd8:  return "s0/fp";
            5'd9:  return "s1";
            5'd10: return "a0";
            5'd11: return "a1";
            5'd12: return "a2";
            5'd13: return "a3";
            5'd14: return "a4";
            5'd15: return "a5";
            5'd16: return "a6";
            5'd17: return "a7";
            5'd18: return "s2";
            5'd19: return "s3";
            5'd20: return "s4";
            5'd21: return "s5";
            5'd22: return "s6";
            5'd23: return "s7";
            5'd24: return "s8";
            5'd25: return "s9";
            5'd26: return "s10";
            5'd27: return "s11";
            5'd28: return "t3";
            5'd29: return "t4";
            5'd30: return "t5";
            5'd31: return "t6";
            default: return "??";
        endcase
    endfunction

endpackage : rv32i_isa_pkg
