`timescale 1ns / 1ps

//=============================================================================
// Module: rv32i_exception_trap_spec
// Description: Assertions for exception trap PC redirection
//              Verifies PC redirect timing, pipeline flush, and trap handling
//=============================================================================

module rv32i_exception_trap_spec (
    input logic clk,
    input logic rst,
    
    // Program Counter
    input logic [31:0] pc_if,
    input logic [31:0] pc_id,
    input logic [31:0] pc_ex,
    input logic [31:0] pc_mem,
    
    // Exception signals
    input logic        exception_trap,
    input logic [31:0] exception_pc,
    input logic [4:0]  exception_code,
    input logic [31:0] exception_tval,
    input logic [31:0] trap_vector,
    
    // MRET signals
    input logic        mret_detected,
    input logic [31:0] mret_pc,
    
    // Pipeline flush signals
    input logic        if_flush,
    input logic        id_flush,
    input logic        ex_flush,
    
    // Pipeline stage valid signals
    input logic        if_id_valid,
    input logic        id_ex_valid,
    input logic        ex_mem_valid,
    input logic        mem_wb_valid,
    
    // Debug mode
    input logic        debug_mode_enable
);

    //=========================================================================
    // Constants
    //=========================================================================
    localparam CAUSE_INSN_MISALIGN  = 5'd0;
    localparam CAUSE_ILLEGAL_INSN   = 5'd2;
    localparam CAUSE_BREAKPOINT     = 5'd3;
    localparam CAUSE_LOAD_MISALIGN  = 5'd4;
    localparam CAUSE_STORE_MISALIGN = 5'd6;
    localparam CAUSE_ECALL          = 5'd11;

    //=========================================================================
    // Helper Signals
    //=========================================================================
    logic [31:0] last_trap_vector;
    logic [31:0] last_exception_pc;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            last_trap_vector <= 32'h0;
            last_exception_pc <= 32'h0;
        end else begin
            if (exception_trap) begin
                last_trap_vector <= trap_vector;
                last_exception_pc <= exception_pc;
            end
        end
    end

    //=========================================================================
    // Assertion 1: PC Redirects to trap_vector on Exception
    // Next cycle after exception_trap, PC must equal trap_vector
    //=========================================================================
    property pc_redirects_to_trap_vector;
        logic [31:0] expected_pc;
        @(posedge clk) disable iff (rst)
        (exception_trap, expected_pc = trap_vector)
        |=> (pc_if == expected_pc);
    endproperty
    
    assert_pc_redirect: assert property(pc_redirects_to_trap_vector)
    else begin
        $error("[EXCEPTION_TRAP] PC not redirected to trap_vector!");
        $display("  Time: %0t | Expected PC: 0x%08X | Got PC: 0x%08X",
                 $time, $past(trap_vector), pc_if);
        $display("  trap_vector = 0x%08X | exception_pc = 0x%08X",
                 $past(trap_vector), $past(exception_pc));
        if ($past(trap_vector) == 32'h0) begin
            $display("  ❌ CRITICAL: trap_vector was ZERO - mtvec CSR not initialized!");
        end
    end

    //=========================================================================
    // Assertion 2: Pipeline Flush on Exception
    // When exception occurs, all pipeline stages must flush
    //=========================================================================
    property pipeline_flushes_on_exception;
        @(posedge clk) disable iff (rst)
        exception_trap |-> (if_flush && id_flush && ex_flush);
    endproperty
    
    assert_pipeline_flush: assert property(pipeline_flushes_on_exception)
    else begin
        $error("[EXCEPTION_TRAP] Pipeline not fully flushed on exception");
        $display("  Time: %0t | if_flush=%0b | id_flush=%0b | ex_flush=%0b",
                 $time, if_flush, id_flush, ex_flush);
    end

    //=========================================================================
    // Assertion 3: Trap Vector Must Be Non-Zero
    // trap_vector must not be zero when exception occurs (unless intentional)
    //=========================================================================
    property trap_vector_valid_at_exception;
        @(posedge clk) disable iff (rst)
        exception_trap |-> (trap_vector != 32'h0);
    endproperty
    
    assert_trap_vector_valid: assert property(trap_vector_valid_at_exception)
    else begin
        $error("[EXCEPTION_TRAP] trap_vector is ZERO at exception - mtvec not initialized!");
        $display("  Time: %0t | exception_pc=0x%08X | exception_code=%0d",
                 $time, exception_pc, exception_code);
        $display("  This indicates mtvec CSR was not written before exception occurred");
    end

    //=========================================================================
    // Assertion 4: PC Redirects to mret_pc on MRET
    // Next cycle after mret_detected, PC must equal mret_pc
    //=========================================================================
    property pc_redirects_to_mret_pc;
        logic [31:0] expected_pc;
        @(posedge clk) disable iff (rst)
        (mret_detected, expected_pc = mret_pc)
        |=> (pc_if == expected_pc);
    endproperty
    
    assert_mret_redirect: assert property(pc_redirects_to_mret_pc)
    else begin
        $error("[EXCEPTION_TRAP] PC not redirected to mret_pc on MRET");
        $display("  Time: %0t | Expected PC: 0x%08X | Got PC: 0x%08X",
                 $time, $past(mret_pc), pc_if);
    end

    //=========================================================================
    // Assertion 5: Pipeline Flush on MRET
    // When MRET occurs, all pipeline stages must flush
    //=========================================================================
    property pipeline_flushes_on_mret;
        @(posedge clk) disable iff (rst)
        mret_detected |-> (if_flush && id_flush && ex_flush);
    endproperty
    
    assert_mret_pipeline_flush: assert property(pipeline_flushes_on_mret)
    else begin
        $error("[EXCEPTION_TRAP] Pipeline not fully flushed on MRET");
        $display("  Time: %0t | if_flush=%0b | id_flush=%0b | ex_flush=%0b",
                 $time, if_flush, id_flush, ex_flush);
    end

    //=========================================================================
    // Assertion 6: Exception and MRET Are Mutually Exclusive
    // exception_trap and mret_detected must not assert simultaneously
    //=========================================================================
    property exception_and_mret_exclusive;
        @(posedge clk) disable iff (rst)
        not (exception_trap && mret_detected);
    endproperty
    
    assert_exception_mret_exclusive: assert property(exception_and_mret_exclusive)
    else begin
        $error("[EXCEPTION_TRAP] Exception and MRET detected simultaneously!");
        $display("  Time: %0t | This should never happen", $time);
    end

    //=========================================================================
    // Assertion 7: Exception Code Valid
    // When exception occurs, exception_code must be a valid cause code
    //=========================================================================
    property valid_exception_code;
        @(posedge clk) disable iff (rst)
        exception_trap |-> (exception_code inside {
            CAUSE_INSN_MISALIGN,
            CAUSE_ILLEGAL_INSN,
            CAUSE_BREAKPOINT,
            CAUSE_LOAD_MISALIGN,
            CAUSE_STORE_MISALIGN,
            CAUSE_ECALL
        });
    endproperty
    
    assert_valid_exception_code: assert property(valid_exception_code)
    else begin
        $error("[EXCEPTION_TRAP] Invalid exception code: %0d", exception_code);
        $display("  Time: %0t | exception_pc=0x%08X", $time, exception_pc);
    end

    //=========================================================================
    // Assertion 8: EBREAK Behavior Depends on Debug Mode
    // When debug_mode_enable=0, EBREAK should trap (exception_trap)
    // When debug_mode_enable=1, EBREAK should halt (cpu_halted, not checked here)
    //=========================================================================
    property ebreak_traps_in_exception_mode;
        @(posedge clk) disable iff (rst || debug_mode_enable)
        (exception_code == CAUSE_BREAKPOINT) |-> exception_trap;
    endproperty
    
    assert_ebreak_exception_mode: assert property(ebreak_traps_in_exception_mode)
    else begin
        $error("[EXCEPTION_TRAP] EBREAK did not trap in exception mode (debug_mode_enable=0)");
        $display("  Time: %0t | exception_pc=0x%08X", $time, exception_pc);
    end

    //=========================================================================
    // Coverage: Track Exception Types
    //=========================================================================
    covergroup exception_coverage @(posedge clk);
        option.name = "exception_cov";
        
        exception_type: coverpoint exception_code iff (exception_trap) {
            bins insn_misalign  = {CAUSE_INSN_MISALIGN};
            bins illegal_insn   = {CAUSE_ILLEGAL_INSN};
            bins breakpoint     = {CAUSE_BREAKPOINT};
            bins load_misalign  = {CAUSE_LOAD_MISALIGN};
            bins store_misalign = {CAUSE_STORE_MISALIGN};
            bins ecall          = {CAUSE_ECALL};
        }
        
        mret_executed: coverpoint mret_detected {
            bins executed = {1};
        }
        
        trap_and_return: cross exception_type, mret_executed;
    endgroup
    
    exception_coverage cov_inst = new();

    //=========================================================================
    // Debug Logging
    //=========================================================================
    always @(posedge clk) begin
        if (!rst) begin
            // Log exception trap
            if (exception_trap) begin
                $display("[EXCEPTION_TRAP] @%0t: EXCEPTION DETECTED", $time);
                $display("  exception_pc   = 0x%08X", exception_pc);
                $display("  exception_code = %0d (%s)", exception_code, 
                         get_exception_name(exception_code));
                $display("  exception_tval = 0x%08X", exception_tval);
                $display("  trap_vector    = 0x%08X", trap_vector);
                $display("  Pipeline flush: IF=%0b ID=%0b EX=%0b", 
                         if_flush, id_flush, ex_flush);
                
                if (trap_vector == 32'h0) begin
                    $display("  ⚠️  CRITICAL: trap_vector=0x00000000 - mtvec not initialized!");
                    $display("  PC will redirect to 0x00000000 instead of trap handler");
                end
            end
            
            // Log PC redirect after exception
            if ($past(exception_trap) && !rst) begin
                $display("[EXCEPTION_TRAP] @%0t: PC REDIRECT", $time);
                $display("  Previous PC    = 0x%08X", $past(pc_if));
                $display("  New PC         = 0x%08X", pc_if);
                $display("  Expected PC    = 0x%08X (trap_vector)", last_trap_vector);
                
                if (pc_if != last_trap_vector) begin
                    $display("  ❌ ERROR: PC mismatch! Expected 0x%08X, got 0x%08X",
                             last_trap_vector, pc_if);
                end else begin
                    $display("  ✅ SUCCESS: PC correctly redirected to trap handler");
                end
            end
            
            // Log MRET
            if (mret_detected) begin
                $display("[EXCEPTION_TRAP] @%0t: MRET DETECTED", $time);
                $display("  mret_pc        = 0x%08X (return address)", mret_pc);
                $display("  Pipeline flush: IF=%0b ID=%0b EX=%0b",
                         if_flush, id_flush, ex_flush);
            end
            
            // Log PC redirect after MRET
            if ($past(mret_detected) && !rst) begin
                $display("[EXCEPTION_TRAP] @%0t: MRET RETURN", $time);
                $display("  Previous PC    = 0x%08X", $past(pc_if));
                $display("  New PC         = 0x%08X", pc_if);
                $display("  Expected PC    = 0x%08X (mret_pc)", $past(mret_pc));
                
                if (pc_if != $past(mret_pc)) begin
                    $display("  ❌ ERROR: PC mismatch on MRET return!");
                end else begin
                    $display("  ✅ SUCCESS: PC correctly returned to saved address");
                end
            end
        end
    end

    //=========================================================================
    // Helper Function: Get Exception Name
    //=========================================================================
    function string get_exception_name(input logic [4:0] code);
        case (code)
            CAUSE_INSN_MISALIGN:  return "INSN_MISALIGN";
            CAUSE_ILLEGAL_INSN:   return "ILLEGAL_INSN";
            CAUSE_BREAKPOINT:     return "BREAKPOINT";
            CAUSE_LOAD_MISALIGN:  return "LOAD_MISALIGN";
            CAUSE_STORE_MISALIGN: return "STORE_MISALIGN";
            CAUSE_ECALL:          return "ECALL";
            default:              return "UNKNOWN";
        endcase
    endfunction

endmodule
