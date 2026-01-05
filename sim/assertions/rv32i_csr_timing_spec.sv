`timescale 1ns / 1ps

//=============================================================================
// Module: rv32i_csr_timing_spec
// Description: Timing assertions for CSR write operations
//              Verifies CSR write completion, mtvec initialization, and
//              trap_vector connection to PC redirect logic
//=============================================================================

module rv32i_csr_timing_spec (
    input logic clk,
    input logic rst,
    
    // CSR write interface
    input logic        csr_wen,
    input logic [11:0] csr_waddr,
    input logic [31:0] csr_wdata,
    
    // CSR registers
    input logic [31:0] mtvec_reg,
    input logic [31:0] mepc_reg,
    input logic [31:0] mcause_reg,
    input logic [31:0] mtval_reg,
    
    // CSR outputs
    input logic [31:0] trap_vector,
    input logic [31:0] mret_pc,
    
    // Pipeline stage information
    input logic        mem_wb_valid,
    input logic        mem_wb_is_csr,
    
    // Exception signals
    input logic        exception_trap,
    input logic [31:0] exception_pc
);

    //=========================================================================
    // Constants
    //=========================================================================
    localparam CSR_MTVEC   = 12'h305;
    localparam CSR_MEPC    = 12'h341;
    localparam CSR_MCAUSE  = 12'h342;
    localparam CSR_MTVAL   = 12'h343;

    //=========================================================================
    // Helper Signals
    //=========================================================================
    logic mtvec_write_detected;
    logic [31:0] expected_mtvec_value;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mtvec_write_detected <= 1'b0;
            expected_mtvec_value <= 32'h0;
        end else begin
            if (csr_wen && csr_waddr == CSR_MTVEC) begin
                mtvec_write_detected <= 1'b1;
                expected_mtvec_value <= csr_wdata;
            end
        end
    end

    //=========================================================================
    // Assertion 1: CSR Write Enable During WB Stage
    // When CSR instruction is in WB stage and address is mtvec, wen must assert
    //=========================================================================
    property csr_write_enable_asserts;
        @(posedge clk) disable iff (rst)
        (mem_wb_valid && mem_wb_is_csr && csr_waddr == CSR_MTVEC)
        |-> csr_wen;
    endproperty
    
    assert_csr_wen: assert property(csr_write_enable_asserts)
    else begin
        $error("[CSR_TIMING] CSR write enable not asserted for mtvec write");
        $display("  Time: %0t | addr=0x%03X | data=0x%08X | wen=%0b", 
                 $time, csr_waddr, csr_wdata, csr_wen);
    end

    //=========================================================================
    // Assertion 2: mtvec Register Update on Write
    // When csr_wen asserts for mtvec, register must update in next cycle
    //=========================================================================
    property mtvec_updates_correctly;
        logic [31:0] write_data;
        @(posedge clk) disable iff (rst)
        (csr_wen && csr_waddr == CSR_MTVEC, write_data = csr_wdata)
        |=> (mtvec_reg == write_data);
    endproperty
    
    assert_mtvec_update: assert property(mtvec_updates_correctly)
    else begin
        $error("[CSR_TIMING] mtvec_reg not updated correctly");
        $display("  Time: %0t | Expected: 0x%08X | Got: 0x%08X", 
                 $time, $past(csr_wdata), mtvec_reg);
    end

    //=========================================================================
    // Assertion 3: trap_vector Reflects mtvec_reg
    // trap_vector output must always equal mtvec_reg (combinational connection)
    //=========================================================================
    property trap_vector_matches_mtvec;
        @(posedge clk) disable iff (rst)
        trap_vector == mtvec_reg;
    endproperty
    
    assert_trap_vector_connection: assert property(trap_vector_matches_mtvec)
    else begin
        $error("[CSR_TIMING] trap_vector does not match mtvec_reg");
        $display("  Time: %0t | mtvec_reg=0x%08X | trap_vector=0x%08X", 
                 $time, mtvec_reg, trap_vector);
    end

    //=========================================================================
    // Assertion 4: trap_vector Must Be Initialized at Exception
    // When exception occurs, trap_vector must not be zero (mtvec initialized)
    //=========================================================================
    property trap_vector_initialized_at_exception;
        @(posedge clk) disable iff (rst)
        exception_trap |-> (trap_vector != 32'h0);
    endproperty
    
    assert_trap_vector_init: assert property(trap_vector_initialized_at_exception)
    else begin
        $error("[CSR_TIMING] trap_vector is ZERO at exception - mtvec not initialized!");
        $display("  Time: %0t | exception_pc=0x%08X | trap_vector=0x%08X | mtvec_reg=0x%08X",
                 $time, exception_pc, trap_vector, mtvec_reg);
        $display("  Previous mtvec write: detected=%0b, expected_value=0x%08X",
                 mtvec_write_detected, expected_mtvec_value);
    end

    //=========================================================================
    // Assertion 5: mepc Updates on Exception Trap
    // When exception occurs, mepc must capture exception_pc in next cycle
    //=========================================================================
    property mepc_captures_exception_pc;
        logic [31:0] trapped_pc;
        @(posedge clk) disable iff (rst)
        (exception_trap, trapped_pc = exception_pc)
        |=> (mepc_reg == trapped_pc);
    endproperty
    
    assert_mepc_capture: assert property(mepc_captures_exception_pc)
    else begin
        $error("[CSR_TIMING] mepc did not capture exception PC correctly");
        $display("  Time: %0t | exception_pc=0x%08X | mepc_reg=0x%08X",
                 $time, $past(exception_pc), mepc_reg);
    end

    //=========================================================================
    // Assertion 6: mret_pc Reflects mepc_reg
    // mret_pc output must always equal mepc_reg (combinational connection)
    //=========================================================================
    property mret_pc_matches_mepc;
        @(posedge clk) disable iff (rst)
        mret_pc == mepc_reg;
    endproperty
    
    assert_mret_pc_connection: assert property(mret_pc_matches_mepc)
    else begin
        $error("[CSR_TIMING] mret_pc does not match mepc_reg");
        $display("  Time: %0t | mepc_reg=0x%08X | mret_pc=0x%08X",
                 $time, mepc_reg, mret_pc);
    end

    //=========================================================================
    // Coverage: Track CSR Writes
    //=========================================================================
    covergroup csr_write_coverage @(posedge clk);
        option.name = "csr_write_cov";
        
        mtvec_write: coverpoint (csr_wen && csr_waddr == CSR_MTVEC) {
            bins written = {1};
        }
        
        mepc_write: coverpoint (csr_wen && csr_waddr == CSR_MEPC) {
            bins written = {1};
        }
        
        mcause_write: coverpoint (csr_wen && csr_waddr == CSR_MCAUSE) {
            bins written = {1};
        }
        
        mtval_write: coverpoint (csr_wen && csr_waddr == CSR_MTVAL) {
            bins written = {1};
        }
    endgroup
    
    csr_write_coverage cov_inst = new();

    //=========================================================================
    // Debug Logging
    //=========================================================================
    always @(posedge clk) begin
        if (!rst) begin
            // Log CSR writes
            if (csr_wen) begin
                case (csr_waddr)
                    CSR_MTVEC: begin
                        $display("[CSR_TIMING] @%0t: mtvec write: 0x%08X → 0x%08X",
                                 $time, mtvec_reg, csr_wdata);
                    end
                    CSR_MEPC: begin
                        $display("[CSR_TIMING] @%0t: mepc write: 0x%08X (exception_pc capture)",
                                 $time, csr_wdata);
                    end
                    CSR_MCAUSE: begin
                        $display("[CSR_TIMING] @%0t: mcause write: 0x%08X",
                                 $time, csr_wdata);
                    end
                    CSR_MTVAL: begin
                        $display("[CSR_TIMING] @%0t: mtval write: 0x%08X",
                                 $time, csr_wdata);
                    end
                endcase
            end
            
            // Log exception trap with CSR state
            if (exception_trap) begin
                $display("[CSR_TIMING] @%0t: EXCEPTION TRAP", $time);
                $display("  exception_pc  = 0x%08X", exception_pc);
                $display("  trap_vector   = 0x%08X (from mtvec)", trap_vector);
                $display("  mtvec_reg     = 0x%08X", mtvec_reg);
                $display("  mepc_reg      = 0x%08X (before update)", mepc_reg);
                if (trap_vector == 32'h0) begin
                    $display("  ⚠️  WARNING: trap_vector is ZERO - mtvec not initialized!");
                end
            end
        end
    end

endmodule
