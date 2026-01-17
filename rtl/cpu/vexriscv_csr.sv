`timescale 1ns/1ps
//==============================================================================
// VexRiscv CSR Plugin Module
//
// Control and Status Register management:
// - CSR read/write operations
// - Machine mode CSRs (mstatus, mtvec, mepc, mcause, mtval, etc.)
// - Interrupt and exception handling
// - Privilege mode control
// - Cycle and instruction counters
//
// Extracted from VexRiscv_GenSmallAndProductive.v
// Original lines: ~567-650, 2478-2650 (distributed across file)
//==============================================================================

module vexriscv_csr
    import vexriscv_pkg::*;
(
    input  logic        clk,
    input  logic        reset,
    
    // External interrupts
    input  logic        externalInterrupt,
    input  logic        timerInterrupt,
    input  logic        softwareInterrupt,
    
    // Execute stage inputs
    input  logic        execute_arbitration_isValid,
    input  logic        execute_arbitration_isStuck,
    input  logic [31:0] execute_INSTRUCTION,
    input  logic        execute_IS_CSR,
    input  logic        execute_CSR_WRITE_OPCODE,
    input  logic        execute_CSR_READ_OPCODE,
    input  logic [31:0] execute_SRC1,
    input  logic        execute_ENV_CTRL_isXRET,
    
    // Memory/WriteBack stage inputs
    input  logic        memory_arbitration_isValid,
    input  logic        writeBack_arbitration_isValid,
    input  logic        writeBack_arbitration_isFiring,
    input  logic [31:0] writeBack_INSTRUCTION,
    input  logic [31:0] writeBack_PC,
    
    // Decode stage control
    input  logic        decode_arbitration_isValid,
    input  logic        decode_arbitration_removeIt,
    output logic        decode_arbitration_haltByOther_csr,
    
    // Pipeline control
    input  logic        execute_arbitration_isStuckByOthers,
    input  logic        memory_arbitration_isStuck,
    input  logic        writeBack_arbitration_isStuck,
    
    // Exception/Interrupt outputs
    output logic        CsrPlugin_jumpInterface_valid,
    output logic [31:0] CsrPlugin_jumpInterface_payload,
    output logic        CsrPlugin_interruptJump,
    output logic        CsrPlugin_hadException,
    
    // CSR read output
    output logic [31:0] CsrPlugin_csrMapping_readDataSignal,
    output logic        execute_CsrPlugin_illegalAccess,
    output logic        execute_CsrPlugin_illegalInstruction
);

    //==========================================================================
    // CSR Registers - Machine Mode
    //==========================================================================
    
    // misa - Machine ISA
    logic [1:0]  CsrPlugin_misa_base;
    logic [25:0] CsrPlugin_misa_extensions;
    
    // mtvec - Machine Trap Vector
    logic [1:0]  CsrPlugin_mtvec_mode;
    logic [29:0] CsrPlugin_mtvec_base;
    
    // mepc - Machine Exception PC
    logic [31:0] CsrPlugin_mepc;
    
    // mstatus - Machine Status
    logic        CsrPlugin_mstatus_MIE;
    logic        CsrPlugin_mstatus_MPIE;
    logic [1:0]  CsrPlugin_mstatus_MPP;
    
    // mip - Machine Interrupt Pending
    logic        CsrPlugin_mip_MEIP;
    logic        CsrPlugin_mip_MTIP;
    logic        CsrPlugin_mip_MSIP;
    
    // mie - Machine Interrupt Enable
    logic        CsrPlugin_mie_MEIE;
    logic        CsrPlugin_mie_MTIE;
    logic        CsrPlugin_mie_MSIE;
    
    // mcause - Machine Cause
    logic        CsrPlugin_mcause_interrupt;
    logic [3:0]  CsrPlugin_mcause_exceptionCode;
    
    // mtval - Machine Trap Value
    logic [31:0] CsrPlugin_mtval;
    
    // mcycle/minstret - Performance counters
    logic [63:0] CsrPlugin_mcycle;
    logic [63:0] CsrPlugin_minstret;
    
    //==========================================================================
    // Interrupt Logic
    //==========================================================================
    
    logic        CsrPlugin_interrupt_valid;
    logic [3:0]  CsrPlugin_interrupt_code;
    logic [1:0]  CsrPlugin_interrupt_targetPrivilege;
    
    logic        when_CsrPlugin_l1296;
    logic        when_CsrPlugin_l1302;
    logic        when_CsrPlugin_l1302_1;
    logic        when_CsrPlugin_l1302_2;
    
    logic        interrupt_MTIP;
    logic        interrupt_MSIP;
    logic        interrupt_MEIP;
    
    //==========================================================================
    // Pipeline Liberator (for interrupt handling)
    //==========================================================================
    
    logic        CsrPlugin_pipelineLiberator_pcValids_0;
    logic        CsrPlugin_pipelineLiberator_pcValids_1;
    logic        CsrPlugin_pipelineLiberator_pcValids_2;
    logic        CsrPlugin_pipelineLiberator_active;
    logic        CsrPlugin_pipelineLiberator_done;
    logic        CsrPlugin_allowInterrupts;
    
    //==========================================================================
    // Trap Handling
    //==========================================================================
    
    logic [1:0]  CsrPlugin_targetPrivilege;
    logic [3:0]  CsrPlugin_trapCause;
    logic [1:0]  CsrPlugin_xtvec_mode;
    logic [29:0] CsrPlugin_xtvec_base;
    
    logic        when_CsrPlugin_l1390;
    logic        when_CsrPlugin_l1398;
    logic        when_CsrPlugin_l1456;
    
    //==========================================================================
    // CSR Access Control
    //==========================================================================
    
    logic        execute_CsrPlugin_writeInstruction;
    logic        execute_CsrPlugin_readInstruction;
    logic        execute_CsrPlugin_writeEnable;
    logic        execute_CsrPlugin_readEnable;
    logic [31:0] execute_CsrPlugin_readToWriteData;
    logic [31:0] CsrPlugin_csrMapping_writeDataSignal;
    logic [11:0] execute_CsrPlugin_csrAddress;
    
    logic        execute_CsrPlugin_csr_768;  // mstatus
    logic        execute_CsrPlugin_csr_836;  // mip
    logic        execute_CsrPlugin_csr_772;  // mie
    logic        execute_CsrPlugin_csr_834;  // mcause
    logic        execute_CsrPlugin_csr_3857; // mcycle
    logic        execute_CsrPlugin_csr_3858; // minstret
    logic        execute_CsrPlugin_csr_341;  // mepc
    logic        execute_CsrPlugin_csr_342;  // mtval
    
    //==========================================================================
    // Constant Configuration
    //==========================================================================
    
    assign CsrPlugin_misa_base = 2'b01;  // RV32
    assign CsrPlugin_misa_extensions = 26'h0000042;  // I extension
    assign CsrPlugin_mtvec_mode = 2'b00;  // Direct mode
    assign CsrPlugin_mtvec_base = 30'h00000008;  // Vector base address
    
    //==========================================================================
    // Interrupt Detection
    //==========================================================================
    
    assign interrupt_MTIP = (CsrPlugin_mip_MTIP && CsrPlugin_mie_MTIE);
    assign interrupt_MSIP = (CsrPlugin_mip_MSIP && CsrPlugin_mie_MSIE);
    assign interrupt_MEIP = (CsrPlugin_mip_MEIP && CsrPlugin_mie_MEIE);
    
    assign when_CsrPlugin_l1296 = CsrPlugin_mstatus_MIE;  // Simplified privilege check
    assign when_CsrPlugin_l1302 = (interrupt_MTIP && 1'b1);
    assign when_CsrPlugin_l1302_1 = (interrupt_MSIP && 1'b1);
    assign when_CsrPlugin_l1302_2 = (interrupt_MEIP && 1'b1);
    
    always_comb begin
        CsrPlugin_interrupt_valid = 1'b0;
        CsrPlugin_interrupt_code = 4'h0;
        CsrPlugin_interrupt_targetPrivilege = 2'b11;
        
        if (when_CsrPlugin_l1296) begin
            if (when_CsrPlugin_l1302) begin
                CsrPlugin_interrupt_valid = 1'b1;
                CsrPlugin_interrupt_code = 4'h7;  // MTI
                CsrPlugin_interrupt_targetPrivilege = 2'b11;
            end
            if (when_CsrPlugin_l1302_1) begin
                CsrPlugin_interrupt_valid = 1'b1;
                CsrPlugin_interrupt_code = 4'h3;  // MSI
                CsrPlugin_interrupt_targetPrivilege = 2'b11;
            end
            if (when_CsrPlugin_l1302_2) begin
                CsrPlugin_interrupt_valid = 1'b1;
                CsrPlugin_interrupt_code = 4'hb;  // MEI
                CsrPlugin_interrupt_targetPrivilege = 2'b11;
            end
        end
    end
    
    //==========================================================================
    // Pipeline Liberator Logic
    //==========================================================================
    
    assign CsrPlugin_allowInterrupts = 1'b1;  // Simplified - always allow
    assign CsrPlugin_pipelineLiberator_active = ((CsrPlugin_interrupt_valid && CsrPlugin_allowInterrupts) && 
                                                   decode_arbitration_isValid);
    
    always_comb begin
        CsrPlugin_pipelineLiberator_done = CsrPlugin_pipelineLiberator_pcValids_2;
        if (CsrPlugin_hadException) begin
            CsrPlugin_pipelineLiberator_done = 1'b0;
        end
    end
    
    assign CsrPlugin_interruptJump = ((CsrPlugin_interrupt_valid && CsrPlugin_pipelineLiberator_done) && 
                                       CsrPlugin_allowInterrupts);
    
    assign decode_arbitration_haltByOther_csr = CsrPlugin_pipelineLiberator_active;
    
    //==========================================================================
    // Trap Vector Calculation
    //==========================================================================
    
    assign CsrPlugin_targetPrivilege = CsrPlugin_interrupt_targetPrivilege;
    assign CsrPlugin_trapCause = CsrPlugin_interrupt_code;
    
    always_comb begin
        CsrPlugin_xtvec_mode = 2'b00;
        case (CsrPlugin_targetPrivilege)
            2'b11: CsrPlugin_xtvec_mode = CsrPlugin_mtvec_mode;
            default: CsrPlugin_xtvec_mode = 2'b00;
        endcase
    end
    
    always_comb begin
        CsrPlugin_xtvec_base = 30'h0;
        case (CsrPlugin_targetPrivilege)
            2'b11: CsrPlugin_xtvec_base = CsrPlugin_mtvec_base;
            default: CsrPlugin_xtvec_base = 30'h0;
        endcase
    end
    
    //==========================================================================
    // Exception/Trap Entry
    //==========================================================================
    
    assign when_CsrPlugin_l1390 = (CsrPlugin_hadException || CsrPlugin_interruptJump);
    assign when_CsrPlugin_l1398 = 1'b1;  // Simplified - no debug mode
    assign when_CsrPlugin_l1456 = (writeBack_arbitration_isValid && execute_ENV_CTRL_isXRET);
    
    assign CsrPlugin_jumpInterface_valid = (when_CsrPlugin_l1390 || when_CsrPlugin_l1456);
    
    always_comb begin
        if (when_CsrPlugin_l1390) begin
            CsrPlugin_jumpInterface_payload = {CsrPlugin_xtvec_base, 2'b00};
        end else if (when_CsrPlugin_l1456) begin
            CsrPlugin_jumpInterface_payload = CsrPlugin_mepc;
        end else begin
            CsrPlugin_jumpInterface_payload = 32'h0;
        end
    end
    
    //==========================================================================
    // CSR Address Decode
    //==========================================================================
    
    assign execute_CsrPlugin_csrAddress = execute_INSTRUCTION[31:20];
    
    assign execute_CsrPlugin_csr_768 = (execute_CsrPlugin_csrAddress == 12'h300);  // mstatus
    assign execute_CsrPlugin_csr_836 = (execute_CsrPlugin_csrAddress == 12'h344);  // mip
    assign execute_CsrPlugin_csr_772 = (execute_CsrPlugin_csrAddress == 12'h304);  // mie
    assign execute_CsrPlugin_csr_834 = (execute_CsrPlugin_csrAddress == 12'h342);  // mcause
    assign execute_CsrPlugin_csr_341 = (execute_CsrPlugin_csrAddress == 12'h341);  // mepc
    assign execute_CsrPlugin_csr_342 = (execute_CsrPlugin_csrAddress == 12'h343);  // mtval
    
    //==========================================================================
    // CSR Read Logic
    //==========================================================================
    
    always_comb begin
        CsrPlugin_csrMapping_readDataSignal = 32'h0;
        
        if (execute_CsrPlugin_csr_768) begin  // mstatus
            CsrPlugin_csrMapping_readDataSignal[3] = CsrPlugin_mstatus_MIE;
            CsrPlugin_csrMapping_readDataSignal[7] = CsrPlugin_mstatus_MPIE;
            CsrPlugin_csrMapping_readDataSignal[12:11] = CsrPlugin_mstatus_MPP;
        end
        if (execute_CsrPlugin_csr_836) begin  // mip
            CsrPlugin_csrMapping_readDataSignal[3] = CsrPlugin_mip_MSIP;
            CsrPlugin_csrMapping_readDataSignal[7] = CsrPlugin_mip_MTIP;
            CsrPlugin_csrMapping_readDataSignal[11] = CsrPlugin_mip_MEIP;
        end
        if (execute_CsrPlugin_csr_772) begin  // mie
            CsrPlugin_csrMapping_readDataSignal[3] = CsrPlugin_mie_MSIE;
            CsrPlugin_csrMapping_readDataSignal[7] = CsrPlugin_mie_MTIE;
            CsrPlugin_csrMapping_readDataSignal[11] = CsrPlugin_mie_MEIE;
        end
        if (execute_CsrPlugin_csr_834) begin  // mcause
            CsrPlugin_csrMapping_readDataSignal[31] = CsrPlugin_mcause_interrupt;
            CsrPlugin_csrMapping_readDataSignal[3:0] = CsrPlugin_mcause_exceptionCode;
        end
        if (execute_CsrPlugin_csr_341) begin  // mepc
            CsrPlugin_csrMapping_readDataSignal = CsrPlugin_mepc;
        end
        if (execute_CsrPlugin_csr_342) begin  // mtval
            CsrPlugin_csrMapping_readDataSignal = CsrPlugin_mtval;
        end
    end
    
    //==========================================================================
    // CSR Write Logic
    //==========================================================================
    
    assign execute_CsrPlugin_readToWriteData = CsrPlugin_csrMapping_readDataSignal;
    
    always_comb begin
        if (execute_INSTRUCTION[13]) begin
            // Set/Clear operations
            if (execute_INSTRUCTION[12]) begin
                CsrPlugin_csrMapping_writeDataSignal = (execute_CsrPlugin_readToWriteData & (~execute_SRC1));
            end else begin
                CsrPlugin_csrMapping_writeDataSignal = (execute_CsrPlugin_readToWriteData | execute_SRC1);
            end
        end else begin
            // Direct write
            CsrPlugin_csrMapping_writeDataSignal = execute_SRC1;
        end
    end
    
    //==========================================================================
    // CSR Access Control
    //==========================================================================
    
    always_comb begin
        execute_CsrPlugin_illegalAccess = 1'b1;
        if (execute_CsrPlugin_csr_768 || execute_CsrPlugin_csr_836 || 
            execute_CsrPlugin_csr_772 || execute_CsrPlugin_csr_834 ||
            execute_CsrPlugin_csr_341 || execute_CsrPlugin_csr_342) begin
            execute_CsrPlugin_illegalAccess = 1'b0;
        end
    end
    
    assign execute_CsrPlugin_illegalInstruction = 1'b0;  // Simplified
    
    always_comb begin
        execute_CsrPlugin_writeInstruction = ((execute_arbitration_isValid && execute_IS_CSR) && 
                                               execute_CSR_WRITE_OPCODE);
        execute_CsrPlugin_readInstruction = ((execute_arbitration_isValid && execute_IS_CSR) && 
                                              execute_CSR_READ_OPCODE);
    end
    
    assign execute_CsrPlugin_writeEnable = (execute_CsrPlugin_writeInstruction && (!execute_arbitration_isStuck));
    assign execute_CsrPlugin_readEnable = (execute_CsrPlugin_readInstruction && (!execute_arbitration_isStuck));
    
    //==========================================================================
    // Sequential Logic - CSR Registers
    //==========================================================================
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            CsrPlugin_mepc <= 32'h0;
            CsrPlugin_mstatus_MIE <= 1'b0;
            CsrPlugin_mstatus_MPIE <= 1'b0;
            CsrPlugin_mstatus_MPP <= 2'b11;
            CsrPlugin_mip_MEIP <= 1'b0;
            CsrPlugin_mip_MTIP <= 1'b0;
            CsrPlugin_mip_MSIP <= 1'b0;
            CsrPlugin_mie_MEIE <= 1'b0;
            CsrPlugin_mie_MTIE <= 1'b0;
            CsrPlugin_mie_MSIE <= 1'b0;
            CsrPlugin_mcause_interrupt <= 1'b0;
            CsrPlugin_mcause_exceptionCode <= 4'h0;
            CsrPlugin_mtval <= 32'h0;
            CsrPlugin_mcycle <= 64'h0;
            CsrPlugin_minstret <= 64'h0;
            CsrPlugin_hadException <= 1'b0;
        end else begin
            // Cycle counter
            CsrPlugin_mcycle <= CsrPlugin_mcycle + 64'h1;
            
            // Instruction counter
            if (writeBack_arbitration_isFiring) begin
                CsrPlugin_minstret <= CsrPlugin_minstret + 64'h1;
            end
            
            // Exception/Interrupt entry
            if (when_CsrPlugin_l1390) begin
                if (when_CsrPlugin_l1398) begin
                    CsrPlugin_mepc <= writeBack_PC;
                    CsrPlugin_mcause_interrupt <= CsrPlugin_interruptJump;
                    CsrPlugin_mcause_exceptionCode <= CsrPlugin_trapCause;
                    CsrPlugin_mstatus_MPIE <= CsrPlugin_mstatus_MIE;
                    CsrPlugin_mstatus_MIE <= 1'b0;
                end
            end
            
            // XRET (return from trap)
            if (when_CsrPlugin_l1456) begin
                CsrPlugin_mstatus_MIE <= CsrPlugin_mstatus_MPIE;
                CsrPlugin_mstatus_MPIE <= 1'b1;
            end
            
            // CSR write operations
            if (execute_CsrPlugin_writeEnable) begin
                if (execute_CsrPlugin_csr_768) begin  // mstatus
                    CsrPlugin_mstatus_MIE <= CsrPlugin_csrMapping_writeDataSignal[3];
                    CsrPlugin_mstatus_MPIE <= CsrPlugin_csrMapping_writeDataSignal[7];
                    CsrPlugin_mstatus_MPP <= CsrPlugin_csrMapping_writeDataSignal[12:11];
                end
                if (execute_CsrPlugin_csr_772) begin  // mie
                    CsrPlugin_mie_MSIE <= CsrPlugin_csrMapping_writeDataSignal[3];
                    CsrPlugin_mie_MTIE <= CsrPlugin_csrMapping_writeDataSignal[7];
                    CsrPlugin_mie_MEIE <= CsrPlugin_csrMapping_writeDataSignal[11];
                end
                if (execute_CsrPlugin_csr_341) begin  // mepc
                    CsrPlugin_mepc <= CsrPlugin_csrMapping_writeDataSignal;
                end
                if (execute_CsrPlugin_csr_342) begin  // mtval
                    CsrPlugin_mtval <= CsrPlugin_csrMapping_writeDataSignal;
                end
            end
            
            // External interrupt inputs
            CsrPlugin_mip_MEIP <= externalInterrupt;
            CsrPlugin_mip_MTIP <= timerInterrupt;
            CsrPlugin_mip_MSIP <= softwareInterrupt;
            
            CsrPlugin_hadException <= 1'b0;  // Reset each cycle
        end
    end
    
    //==========================================================================
    // Sequential Logic - Pipeline Liberator
    //==========================================================================
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            CsrPlugin_pipelineLiberator_pcValids_0 <= 1'b0;
            CsrPlugin_pipelineLiberator_pcValids_1 <= 1'b0;
            CsrPlugin_pipelineLiberator_pcValids_2 <= 1'b0;
        end else begin
            if ((!execute_arbitration_isStuck)) begin
                CsrPlugin_pipelineLiberator_pcValids_0 <= 1'b1;
            end
            if ((!memory_arbitration_isStuck)) begin
                CsrPlugin_pipelineLiberator_pcValids_1 <= CsrPlugin_pipelineLiberator_pcValids_0;
            end
            if ((!writeBack_arbitration_isStuck)) begin
                CsrPlugin_pipelineLiberator_pcValids_2 <= CsrPlugin_pipelineLiberator_pcValids_1;
            end
            
            if (((!CsrPlugin_pipelineLiberator_active) || decode_arbitration_removeIt)) begin
                CsrPlugin_pipelineLiberator_pcValids_0 <= 1'b0;
                CsrPlugin_pipelineLiberator_pcValids_1 <= 1'b0;
                CsrPlugin_pipelineLiberator_pcValids_2 <= 1'b0;
            end
        end
    end

endmodule : vexriscv_csr
