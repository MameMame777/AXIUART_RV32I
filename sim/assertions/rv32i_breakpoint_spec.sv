`timescale 1ns / 1ps

//==============================================================================
// RV32I Hardware Breakpoint Specification (SVA)
//==============================================================================
// Defines expected behavior of hardware breakpoint feature
// Bound to rv32i_core for runtime verification
//
// Expected Behavior:
// 1. bp_match asserts when PC equals any enabled breakpoint address
// 2. CPU halts within 1 cycle of breakpoint match
// 3. dbg_bp_hit[N] is set for matched breakpoint N
// 4. cpu_break_reg and cpu_break assert on hardware breakpoint
// 5. PC should not advance beyond breakpoint address
//==============================================================================

module rv32i_breakpoint_spec (
    input logic clk,
    input logic rst_n,
    
    // CPU state
    input logic running,
    input logic cpu_halted,
    input logic cpu_break,
    input logic [31:0] pc_if,
    
    // Breakpoint interface
    input logic [3:0] dbg_bp_enable,
    input logic [31:0] dbg_bp_addr[0:3],
    input logic [3:0] dbg_bp_hit,
    
    // Internal signals
    input logic bp_match,
    input logic cpu_break_reg,
    input logic bp_skip_once,
    input logic bp_just_resumed,
    input logic if_valid,
    input logic at_any_bp_addr,
    
    // Pipeline state
    input logic id_ex_reg_valid,
    input logic ex_mem_reg_valid,
    input logic mem_wb_reg_valid,
    
    // Flush signals
    input logic if_flush,
    input logic id_flush,
    input logic ex_flush,
    input logic bp_flush,
    
    // Register file monitoring
    input logic [4:0] rf_waddr,
    input logic [31:0] rf_wdata,
    input logic rf_write_en,
    input logic [31:0] regfile_x3
);

    //==========================================================================
    // Helper Signals
    //==========================================================================
    
    logic bp0_match, bp1_match, bp2_match, bp3_match;
    
    assign bp0_match = dbg_bp_enable[0] && (pc_if == dbg_bp_addr[0]);
    assign bp1_match = dbg_bp_enable[1] && (pc_if == dbg_bp_addr[1]);
    assign bp2_match = dbg_bp_enable[2] && (pc_if == dbg_bp_addr[2]);
    assign bp3_match = dbg_bp_enable[3] && (pc_if == dbg_bp_addr[3]);
    
    logic any_bp_match;
    assign any_bp_match = bp0_match || bp1_match || bp2_match || bp3_match;
    
    //==========================================================================
    // PC Change Tracking (for Resume Debugging)
    //==========================================================================
    
    logic [31:0] pc_prev;
    logic pc_changed;
    int instruction_after_resume;
    int cycles_after_resume;
    logic resume_detected;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            pc_prev <= 32'h0;
            instruction_after_resume <= 0;
            cycles_after_resume <= 0;
            resume_detected <= 1'b0;
        end else begin
            pc_prev <= pc_if;
            pc_changed <= (pc_if != pc_prev);
            
            // Detect CPU resume from halt
            if ($rose(running) && $past(cpu_halted)) begin
                resume_detected <= 1'b1;
                instruction_after_resume <= 0;
                cycles_after_resume <= 0;
                $display("[BP_SPEC] @%0t: === CPU RESUMED === PC=0x%08h, bp_skip_once=%b, bp_just_resumed=%b, if_valid=%b",
                         $time, pc_if, bp_skip_once, bp_just_resumed, if_valid);
            end
            
            // Track PC changes and state after resume
            if (resume_detected) begin
                cycles_after_resume <= cycles_after_resume + 1;
                
                if (pc_changed) begin
                    instruction_after_resume <= instruction_after_resume + 1;
                    $display("[BP_SPEC] @%0t: [CYCLE %0d] PC CHANGED - PC: 0x%08h -> 0x%08h | if_valid=%b, bp_match=%b, bp_skip_once=%b, bp_just_resumed=%b",
                             $time, cycles_after_resume, pc_prev, pc_if, if_valid, bp_match, bp_skip_once, bp_just_resumed);
                end else if (running) begin
                    $display("[BP_SPEC] @%0t: [CYCLE %0d] PC STUCK - PC=0x%08h | if_valid=%b, bp_match=%b, bp_skip_once=%b, running=%b, cpu_halted=%b",
                             $time, cycles_after_resume, pc_if, if_valid, bp_match, bp_skip_once, running, cpu_halted);
                end
                
                // Monitor for 20 cycles after resume
                if (cycles_after_resume >= 20) begin
                    resume_detected <= 1'b0;
                    $display("[BP_SPEC] @%0t: Resume monitoring complete - %0d PC changes in %0d cycles", 
                             $time, instruction_after_resume, cycles_after_resume);
                end
            end
            
            // Track bp_skip_once changes
            if ($fell(bp_skip_once)) begin
                $display("[BP_SPEC] @%0t: bp_skip_once CLEARED - PC=0x%08h, bp_just_resumed=%b, at_any_bp_addr=%b, running=%b, if_valid=%b",
                         $time, pc_if, bp_just_resumed, at_any_bp_addr, running, if_valid);
            end
            
            if ($rose(bp_skip_once)) begin
                $display("[BP_SPEC] @%0t: bp_skip_once SET - PC=0x%08h, bp_hit=%b",
                         $time, pc_if, dbg_bp_hit);
            end
            
            // Track instruction completion in pipeline
            if (mem_wb_reg_valid && running && resume_detected && cycles_after_resume < 20) begin
                $display("[BP_SPEC] @%0t: [CYCLE %0d] Instruction completed in WB stage",
                         $time, cycles_after_resume);
            end
        end
    end

    
    //==========================================================================
    // ASSERTION 1: Breakpoint Match Logic Correctness
    //==========================================================================
    
    property bp_match_is_correct;
        @(posedge clk) disable iff (!rst_n)
        (bp_match == any_bp_match);
    endproperty
    
    assert_bp_match_correct: assert property (bp_match_is_correct)
        else $error("[BP_SPEC] ASSERTION FAILED: bp_match mismatch - bp_match=%b, expected=%b, PC=0x%08h, BP0_EN=%b, BP0_ADDR=0x%08h",
                    bp_match, any_bp_match, pc_if, dbg_bp_enable[0], dbg_bp_addr[0]);
    
    //==========================================================================
    // ASSERTION 2: CPU Halts on Breakpoint
    //==========================================================================
    
    property bp_causes_halt;
        @(posedge clk) disable iff (!rst_n)
        (bp_match && running) |=> cpu_halted;
    endproperty
    
    assert_bp_causes_halt: assert property (bp_causes_halt)
        else $error("[BP_SPEC] ASSERTION FAILED: CPU did not halt after breakpoint at PC=0x%08h", $past(pc_if));
    
    cover_bp_causes_halt: cover property (bp_causes_halt)
        $display("[BP_SPEC] COVER: Breakpoint triggered halt at PC=0x%08h @ %0t", $past(pc_if), $time);
    
    //==========================================================================
    // ASSERTION 3: Breakpoint Hit Flags Set
    //==========================================================================
    
    generate
        for (genvar i = 0; i < 4; i++) begin : gen_bp_hit_assertions
            property bp_hit_flag_set;
                @(posedge clk) disable iff (!rst_n)
                (dbg_bp_enable[i] && (pc_if == dbg_bp_addr[i]) && running) |=> dbg_bp_hit[i];
            endproperty
            
            assert_bp_hit: assert property (bp_hit_flag_set)
                else $error("[BP_SPEC] ASSERTION FAILED: BP%0d hit flag not set - PC=0x%08h, BP_ADDR=0x%08h",
                            i, $past(pc_if), dbg_bp_addr[i]);
        end
    endgenerate
    
    //==========================================================================
    // ASSERTION 4: cpu_break_reg Set on Hardware Breakpoint
    //==========================================================================
    
    property bp_sets_break_reg;
        @(posedge clk) disable iff (!rst_n)
        (bp_match && running) |=> cpu_break_reg;
    endproperty
    
    assert_bp_sets_break_reg: assert property (bp_sets_break_reg)
        else $error("[BP_SPEC] ASSERTION FAILED: cpu_break_reg not set after breakpoint at PC=0x%08h", $past(pc_if));
    
    //==========================================================================
    // ASSERTION 5: cpu_break Reflects cpu_break_reg
    //==========================================================================
    
    property break_signal_matches_reg;
        @(posedge clk) disable iff (!rst_n)
        (cpu_break == cpu_break_reg);
    endproperty
    
    assert_break_signal: assert property (break_signal_matches_reg)
        else $error("[BP_SPEC] ASSERTION FAILED: cpu_break=%b != cpu_break_reg=%b", cpu_break, cpu_break_reg);
    
    //==========================================================================
    // ASSERTION 6: PC Freeze on Breakpoint Hit
    //==========================================================================
    // PC should not advance once breakpoint triggers and CPU halts
    
    property pc_frozen_when_halted;
        @(posedge clk) disable iff (!rst_n)
        ($rose(cpu_halted) && bp_match) |=> $stable(pc_if) [*1:$];
    endproperty
    
    // This is informational - PC may change on cpu_run
    cover_pc_frozen: cover property (pc_frozen_when_halted)
        $display("[BP_SPEC] COVER: PC frozen after breakpoint at 0x%08h @ %0t", pc_if, $time);
    
    //==========================================================================
    // RUNTIME MONITORING
    //==========================================================================
    
    always @(posedge clk) begin
        if (rst_n) begin
            // Breakpoint match detection
            if ($rose(bp_match) && running) begin
                $display("[BP_SPEC] @%0t: Breakpoint MATCH detected - PC=0x%08h, BP_HIT_NEXT=%b",
                         $time, pc_if, 
                         {dbg_bp_enable[3] && (pc_if == dbg_bp_addr[3]),
                          dbg_bp_enable[2] && (pc_if == dbg_bp_addr[2]),
                          dbg_bp_enable[1] && (pc_if == dbg_bp_addr[1]),
                          dbg_bp_enable[0] && (pc_if == dbg_bp_addr[0])});
            end
            
            // CPU halted due to breakpoint
            if ($rose(cpu_halted) && $past(bp_match) && $past(running)) begin
                $display("[BP_SPEC] @%0t: CPU HALTED by breakpoint - PC=0x%08h, BP_HIT=%b, cpu_break=%b",
                         $time, pc_if, dbg_bp_hit, cpu_break);
            end
            
            // cpu_break assertion
            if ($rose(cpu_break)) begin
                $display("[BP_SPEC] @%0t: cpu_break ASSERTED - PC=0x%08h, source=%s",
                         $time, pc_if, cpu_break_reg ? "hw_breakpoint" : "unknown");
            end
            
            // Breakpoint address tracking
            if (dbg_bp_enable[0]) begin
                if (pc_if == dbg_bp_addr[0] - 32'd4) begin
                    $display("[BP_SPEC] @%0t: PC approaching BP0 - PC=0x%08h, BP0_ADDR=0x%08h (next cycle)",
                             $time, pc_if, dbg_bp_addr[0]);
                end
            end
        end
    end

    //==========================================================================
    // RESUME CYCLE DETAILED MONITORING
    //==========================================================================
    
    logic [31:0] x3_prev;
    int resume_cycle_count;
    logic monitoring_resume;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            x3_prev <= 32'h0;
            resume_cycle_count <= 0;
            monitoring_resume <= 1'b0;
        end else begin
            x3_prev <= regfile_x3;
            
            // Start monitoring on resume detection
            if ($rose(bp_skip_once) && bp_just_resumed) begin
                monitoring_resume <= 1'b1;
                resume_cycle_count <= 0;
                $display("[BP_SPEC] @%0t: === RESUME MONITORING START ===", $time);
                $display("[BP_SPEC] @%0t:   Initial State: PC=0x%08h, x3=0x%08h", 
                         $time, pc_if, regfile_x3);
            end
            
            // Monitor for 5 cycles after resume
            if (monitoring_resume) begin
                resume_cycle_count <= resume_cycle_count + 1;
                
                $display("[BP_SPEC] @%0t: [RESUME CYCLE %0d]", $time, resume_cycle_count);
                $display("[BP_SPEC] @%0t:   PC: 0x%08h", $time, pc_if);
                $display("[BP_SPEC] @%0t:   Pipeline Valid: IF=%b, ID=%b, EX=%b, MEM=%b, WB=%b",
                         $time, if_valid, id_ex_reg_valid, ex_mem_reg_valid, mem_wb_reg_valid);
                $display("[BP_SPEC] @%0t:   Flush Signals: IF=%b, ID=%b, EX=%b, BP=%b",
                         $time, if_flush, id_flush, ex_flush, bp_flush);
                $display("[BP_SPEC] @%0t:   BP Control: bp_skip_once=%b, bp_just_resumed=%b, bp_match=%b",
                         $time, bp_skip_once, bp_just_resumed, bp_match);
                $display("[BP_SPEC] @%0t:   x3 register: 0x%08h", $time, regfile_x3);
                
                // Track register writes
                if (rf_write_en && rf_waddr == 5'd3) begin
                    $display("[BP_SPEC] @%0t:   *** x3 WRITE DETECTED: old=0x%08h, new=0x%08h ***",
                             $time, x3_prev, rf_wdata);
                end
                
                // Check for x3 changes
                if (regfile_x3 != x3_prev) begin
                    $display("[BP_SPEC] @%0t:   *** x3 CHANGED: 0x%08h -> 0x%08h (delta=%0d) ***",
                             $time, x3_prev, regfile_x3, $signed(regfile_x3 - x3_prev));
                end
                
                // Detect pipeline issues
                if (if_flush && if_valid) begin
                    $display("[BP_SPEC] @%0t:   WARNING: IF stage flushed while if_valid=1", $time);
                end
                
                if (id_flush && id_ex_reg_valid) begin
                    $display("[BP_SPEC] @%0t:   WARNING: ID stage flushed while ID/EX valid", $time);
                end
                
                if (ex_flush && ex_mem_reg_valid) begin
                    $display("[BP_SPEC] @%0t:   WARNING: EX stage flushed while EX/MEM valid", $time);
                end
                
                // Stop monitoring after 5 cycles
                if (resume_cycle_count >= 5) begin
                    monitoring_resume <= 1'b0;
                    $display("[BP_SPEC] @%0t: === RESUME MONITORING END ===", $time);
                    $display("[BP_SPEC] @%0t:   Final x3: 0x%08h (expected increment from breakpoint instruction)",
                             $time, regfile_x3);
                end
            end
        end
    end
    
    //==========================================================================
    // X3 INCREMENT ASSERTION
    //==========================================================================
    // At PC=0x10, instruction is ADDI x3, x3, 1
    // After resume and execution, x3 should increment
    
    logic at_bp_addr_0x10;
    assign at_bp_addr_0x10 = (pc_if == 32'h00000010);
    
    // Track if we executed at 0x10
    logic executed_at_0x10;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            executed_at_0x10 <= 1'b0;
        end else begin
            // Mark execution when PC=0x10 and pipeline is active
            if (at_bp_addr_0x10 && if_valid && running && !cpu_halted) begin
                if ($past(bp_just_resumed, 1)) begin
                    executed_at_0x10 <= 1'b1;
                    $display("[BP_SPEC] @%0t: MARKED EXECUTION at PC=0x10 after resume", $time);
                end
            end
            
            // Check for x3 increment after execution
            if (executed_at_0x10 && (regfile_x3 > x3_prev)) begin
                $display("[BP_SPEC] @%0t: ✓ x3 INCREMENT CONFIRMED after executing PC=0x10", $time);
                executed_at_0x10 <= 1'b0;  // Reset flag
            end
            
            // Timeout check - if PC advances beyond 0x14 without x3 increment
            if (executed_at_0x10 && (pc_if > 32'h00000014) && (regfile_x3 == x3_prev)) begin
                $error("[BP_SPEC] @%0t: ✗ x3 DID NOT INCREMENT - instruction at 0x10 may not have executed!", $time);
                executed_at_0x10 <= 1'b0;  // Reset flag
            end
        end
    end

endmodule
