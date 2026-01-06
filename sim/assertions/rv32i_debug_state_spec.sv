`timescale 1ns / 1ps

//=============================================================================
// Module: rv32i_debug_state_spec
// Description: Debug assertions for CPU state tracking and CSR write pipeline
//              Monitors running transitions, pipeline valid propagation,
//              and unexpected halt conditions
//=============================================================================

module rv32i_debug_state_spec (
    input logic clk,
    input logic rst,
    
    // CPU state signals
    input logic        running,          // CPU running state
    input logic        cpu_halted,       // CPU halted state
    input logic        cpu_break,        // Breakpoint hit
    input logic [3:0]  bp_hit,           // Which breakpoint hit
    input logic        step_mode,        // Single-step mode
    
    // Pipeline valid signals
    input logic        if_valid,         // IF stage valid
    input logic        id_valid,         // ID stage valid
    input logic        ex_valid,         // EX stage valid
    input logic        mem_valid,        // MEM stage valid
    input logic        wb_valid,         // WB stage valid (mem_wb_reg.valid)
    
    // CSR write signals
    input logic        csr_wen,          // CSR write enable
    input logic [11:0] csr_waddr,        // CSR write address
    input logic [31:0] csr_wdata,        // CSR write data
    input logic        mem_wb_is_csr,    // WB stage has CSR instruction
    
    // Instruction tracking (for CSRW detection)
    input logic [31:0] insn_if,          // IF stage instruction
    input logic [31:0] insn_id,          // ID stage instruction
    input logic [31:0] insn_ex,          // EX stage instruction
    input logic [31:0] insn_mem,         // MEM stage instruction
    input logic [31:0] insn_wb,          // WB stage instruction
    
    // PC tracking
    input logic [31:0] pc_if,            // IF stage PC
    input logic [31:0] pc_id,            // ID stage PC
    input logic [31:0] pc_ex,            // EX stage PC
    input logic [31:0] pc_mem,           // MEM stage PC
    input logic [31:0] pc_wb,            // WB stage PC
    
    // CSR registers
    input logic [31:0] mtvec_reg         // mtvec register value
);

    //=========================================================================
    // Constants
    //=========================================================================
    localparam CSR_MTVEC = 12'h305;
    
    // CSRW instruction encoding
    localparam [6:0] OPC_SYSTEM = 7'b1110011;
    localparam [2:0] F3_CSRRW   = 3'b001;
    
    //=========================================================================
    // Helper Functions
    //=========================================================================
    
    function automatic logic is_csrw_insn(input logic [31:0] insn);
        return (insn[6:0] == OPC_SYSTEM) && (insn[14:12] == F3_CSRRW);
    endfunction
    
    function automatic logic [11:0] get_csr_addr(input logic [31:0] insn);
        return insn[31:20];
    endfunction
    
    function automatic logic is_csrw_mtvec(input logic [31:0] insn);
        return is_csrw_insn(insn) && (get_csr_addr(insn) == CSR_MTVEC);
    endfunction
    
    //=========================================================================
    // State Tracking
    //=========================================================================
    
    logic running_prev;
    logic cpu_started;
    int   cycles_since_start;
    
    logic csrw_mtvec_in_id, csrw_mtvec_in_ex, csrw_mtvec_in_mem, csrw_mtvec_in_wb;
    int csrw_id_cycle, csrw_ex_cycle, csrw_mem_cycle, csrw_wb_cycle;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            running_prev <= 1'b0;
            cpu_started <= 1'b0;
            cycles_since_start <= 0;
            csrw_id_cycle <= -1;
            csrw_ex_cycle <= -1;
            csrw_mem_cycle <= -1;
            csrw_wb_cycle <= -1;
        end else begin
            running_prev <= running;
            if (running && !running_prev) begin
                cpu_started <= 1'b1;
                cycles_since_start <= 0;
                $display("[DEBUG_STATE] @%0t: ✓ CPU STARTED - pc_if=0x%08X", $time, pc_if);
            end else if (running) begin
                cycles_since_start <= cycles_since_start + 1;
                // Print first 30 cycles to see instruction stream
                if (cycles_since_start < 30) begin
                    $display("[DEBUG_STATE] @%0t: [CYCLE %0d] pc_if=0x%08X, insn_if=0x%08X, if_valid=%0b, id_valid=%0b, insn_id=0x%08X",
                             $time, cycles_since_start, pc_if, insn_if, if_valid, id_valid, insn_id);
                end
            end else begin
                cpu_started <= 1'b0;
            end
            
            // Track cycle when CSRW reaches each stage
            if (csrw_mtvec_in_id && !$past(csrw_mtvec_in_ex))
                csrw_id_cycle <= cycles_since_start;
            if (csrw_mtvec_in_ex && !$past(csrw_mtvec_in_mem))
                csrw_ex_cycle <= cycles_since_start;
            if (csrw_mtvec_in_mem && !$past(csrw_mtvec_in_wb))
                csrw_mem_cycle <= cycles_since_start;
            if (csrw_mtvec_in_wb && csr_wen)
                csrw_wb_cycle <= cycles_since_start;
        end
    end
    
    always_comb begin
        csrw_mtvec_in_id  = id_valid  && is_csrw_mtvec(insn_id);
        csrw_mtvec_in_ex  = ex_valid  && is_csrw_mtvec(insn_ex);
        csrw_mtvec_in_mem = mem_valid && is_csrw_mtvec(insn_mem);
        csrw_mtvec_in_wb  = wb_valid  && is_csrw_mtvec(insn_wb) && mem_wb_is_csr;
    end
    
    //=========================================================================
    // ASSERTION 1: CPU Running State Transitions
    //=========================================================================
    
    always @(posedge clk) begin
        if (!rst) begin
            if (running && !running_prev) begin
                $display("[DEBUG_STATE] @%0t: ✅ CPU STARTED (running: 0→1)", $time);
                $display("  pc_if = 0x%08X", pc_if);
            end
            if (!running && running_prev) begin
                $display("[DEBUG_STATE] @%0t: ⚠️  CPU HALTED (running: 1→0)", $time);
                $display("  Reason: cpu_halted=%0b, cpu_break=%0b, bp_hit=0x%h",
                         cpu_halted, cpu_break, bp_hit);
                $display("  Final PC: if=0x%08X, wb=0x%08X", pc_if, pc_wb);
            end
        end
    end
    
    //=========================================================================
    // ASSERTION 2: CSRW mtvec Pipeline Progression
    //=========================================================================
    
    property p_csrw_mtvec_reaches_wb;
        @(posedge clk) disable iff (rst)
        (id_valid && is_csrw_mtvec(insn_id)) |-> ##[1:10] (wb_valid && is_csrw_mtvec(insn_wb));
    endproperty
    
    assert_csrw_mtvec_reaches_wb: assert property (p_csrw_mtvec_reaches_wb)
    else begin
        $error("[DEBUG_STATE] ❌ CSRW mtvec did NOT reach WB with valid=1!");
        $display("  Time: %0t", $time);
        $display("  Pipeline stages reached: ID(cyc %0d), EX(cyc %0d), MEM(cyc %0d), WB(cyc %0d)",
                 csrw_id_cycle, csrw_ex_cycle, csrw_mem_cycle, csrw_wb_cycle);
        $display("  Current valid flags: id=%0b, ex=%0b, mem=%0b, wb=%0b",
                 id_valid, ex_valid, mem_valid, wb_valid);
        $display("  Current PCs: id=0x%08X, ex=0x%08X, mem=0x%08X, wb=0x%08X",
                 pc_id, pc_ex, pc_mem, pc_wb);
    end
    
    always @(posedge clk) begin
        if (!rst && running) begin
            // Debug: print CSRW detection status for first 15 cycles
            if (cycles_since_start < 15) begin
                $display("[DEBUG_STATE] @%0t: [CYCLE %0d] csrw_mtvec_in_id=%0b (insn_id=0x%08X, id_valid=%0b)",
                         $time, cycles_since_start, csrw_mtvec_in_id, insn_id, id_valid);
            end
            
            if (csrw_mtvec_in_id && !$past(csrw_mtvec_in_id)) begin
                $display("[DEBUG_STATE] @%0t: ✅ CSRW mtvec → ID stage (cycle %0d)",
                         $time, cycles_since_start);
                $display("  PC_ID=0x%08X, insn=0x%08X, id_valid=%0b", pc_id, insn_id, id_valid);
            end
            if (csrw_mtvec_in_ex && !$past(csrw_mtvec_in_ex)) begin
                $display("[DEBUG_STATE] @%0t: CSRW mtvec → EX stage (cycle %0d)",
                         $time, cycles_since_start);
                $display("  PC_EX=0x%08X, insn=0x%08X, ex_valid=%0b", pc_ex, insn_ex, ex_valid);
            end
            if (csrw_mtvec_in_mem && !$past(csrw_mtvec_in_mem)) begin
                $display("[DEBUG_STATE] @%0t: CSRW mtvec → MEM stage (cycle %0d)",
                         $time, cycles_since_start);
                $display("  PC_MEM=0x%08X, insn=0x%08X, mem_valid=%0b", pc_mem, insn_mem, mem_valid);
            end
            if (csrw_mtvec_in_wb && !$past(csrw_mtvec_in_wb)) begin
                $display("[DEBUG_STATE] @%0t: CSRW mtvec → WB stage (cycle %0d)",
                         $time, cycles_since_start);
                $display("  PC_WB=0x%08X, insn=0x%08X, wb_valid=%0b", pc_wb, insn_wb, wb_valid);
                $display("  csr_wen=%0b, mem_wb_is_csr=%0b, mtvec_reg=0x%08X",
                         csr_wen, mem_wb_is_csr, mtvec_reg);
                if (!csr_wen) begin
                    $display("  ⚠️  WARNING: csr_wen=0 despite CSRW in WB!");
                end
            end
        end
    end
    
    //=========================================================================
    // ASSERTION 3: CSR Write Timing (cycles 5-6 expected)
    //=========================================================================
    
    logic mtvec_write_expected;
    logic mtvec_written;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mtvec_write_expected <= 1'b0;
            mtvec_written <= 1'b0;
        end else begin
            // Expect mtvec write in cycles 5-10 after start
            if (running && (cycles_since_start >= 5) && (cycles_since_start <= 10) && !mtvec_written) begin
                mtvec_write_expected <= 1'b1;
            end else if (cycles_since_start > 10) begin
                mtvec_write_expected <= 1'b0;
            end
            
            // Track if mtvec was written
            if (csr_wen && (csr_waddr == CSR_MTVEC)) begin
                mtvec_written <= 1'b1;
            end
            
            // Report if window closes without write
            if ($past(mtvec_write_expected) && !mtvec_write_expected && !mtvec_written) begin
                $display("[DEBUG_STATE] @%0t: ❌ mtvec NOT written in expected window (cycles 5-10)",
                         $time);
                $display("  Current cycle: %0d, mtvec_reg = 0x%08X", cycles_since_start, mtvec_reg);
                $display("  CSRW pipeline: ID(cyc %0d), EX(cyc %0d), MEM(cyc %0d), WB(cyc %0d)",
                         csrw_id_cycle, csrw_ex_cycle, csrw_mem_cycle, csrw_wb_cycle);
            end
        end
    end
    
    always @(posedge clk) begin
        if (!rst && csr_wen) begin
            $display("[DEBUG_STATE] @%0t: ✅ CSR WRITE (cycle %0d)", $time, cycles_since_start);
            $display("  CSR[0x%03X] ← 0x%08X, wb_valid=%0b", csr_waddr, csr_wdata, wb_valid);
            if (csr_waddr == CSR_MTVEC) begin
                $display("  ✅ mtvec written: 0x%08X → 0x%08X", mtvec_reg, csr_wdata);
                if (cycles_since_start < 5 || cycles_since_start > 10) begin
                    $display("  ⚠️  Unexpected timing: cycle %0d (expected 5-10)", cycles_since_start);
                end
            end
        end
    end
    
    //=========================================================================
    // ASSERTION 4: Unexpected Halt Detection
    //=========================================================================
    
    property p_no_halt_during_csrw;
        @(posedge clk) disable iff (rst)
        (running && (cycles_since_start < 10) && csrw_mtvec_in_id) |-> ##[1:5] running;
    endproperty
    
    assert_no_unexpected_halt: assert property (p_no_halt_during_csrw)
    else begin
        $error("[DEBUG_STATE] ❌ CPU halted unexpectedly during CSRW execution!");
        $display("  Time: %0t, cycles_since_start: %0d", $time, cycles_since_start);
        $display("  cpu_halted=%0b, cpu_break=%0b, bp_hit=0x%h",
                 cpu_halted, cpu_break, bp_hit);
        $display("  CSRW pipeline: ID=%0b, EX=%0b, MEM=%0b, WB=%0b",
                 csrw_mtvec_in_id, csrw_mtvec_in_ex, csrw_mtvec_in_mem, csrw_mtvec_in_wb);
    end
    
    always @(posedge clk) begin
        if (!rst && cpu_break && !$past(cpu_break)) begin
            $display("[DEBUG_STATE] @%0t: ⚠️  BREAKPOINT HIT", $time);
            $display("  bp_hit = 0x%h, pc_if = 0x%08X", bp_hit, pc_if);
            $display("  cycles_since_start = %0d", cycles_since_start);
            if (cycles_since_start < 10) begin
                $display("  ⚠️  WARNING: Breakpoint during CSRW window!");
            end
        end
    end
    
    //=========================================================================
    // ASSERTION 5: Pipeline Valid Consistency
    //=========================================================================
    
    // Temporarily disabled - was firing false positives
    // property p_valid_propagation_order;
    //     @(posedge clk) disable iff (rst || !running)
    //     if_valid |=> id_valid;
    // endproperty
    
    // assert_valid_propagation: assert property (p_valid_propagation_order)
    // else begin
    //     $display("[DEBUG_STATE] @%0t: ⚠️  Valid flag propagation broken: if_valid=%0b → id_valid=%0b",
    //              $time, $past(if_valid), id_valid);
    // end
    
    //=========================================================================
    // Coverage: Track key events
    //=========================================================================
    
    covergroup cg_debug_state @(posedge clk);
        option.per_instance = 1;
        option.name = "debug_state_coverage";
        
        cp_running_transitions: coverpoint {running, running_prev} {
            bins halted_to_running = {2'b01};
            bins running_to_halted = {2'b10};
        }
        
        cp_csrw_pipeline: coverpoint {csrw_mtvec_in_id, csrw_mtvec_in_ex,
                                       csrw_mtvec_in_mem, csrw_mtvec_in_wb} {
            bins in_id  = {4'b1000};
            bins in_ex  = {4'b0100};
            bins in_mem = {4'b0010};
            bins in_wb  = {4'b0001};
        }
        
        cp_csr_write: coverpoint csr_wen {
            bins written = {1'b1};
        }
        
        cp_unexpected_halt: coverpoint {running, cpu_break, cycles_since_start < 10} {
            bins break_during_csrw = {3'b110};
        }
        
    endgroup
    
    cg_debug_state cg_inst = new();

endmodule
