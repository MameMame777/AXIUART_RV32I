`timescale 1ns / 1ps

// High-quality assertion module for TD4 CPU Branch instruction verification
// Focuses on PC capture timing, branch target calculation, and delay slot execution
module td4cpu_br_timing_assertions (
    input logic clk,
    input logic rst,
    input logic running,
    
    // Fetch stage signals
    input logic [15:0] pc,
    input logic [15:0] fetch_pc,
    input logic [15:0] insn_fetched_pc,
    input logic        ram_rd_en,
    
    // Decode stage signals
    input logic [15:0] insn_fetched,
    input logic        insn_valid,
    input logic [15:0] br_insn_pc,
    
    // Execute stage signals
    input logic [15:0] insn_decoded_reg,
    input logic        insn_decoded_valid,
    
    // Branch control signals
    input logic        branch_pending,
    input logic [15:0] branch_target_pending,
    input logic        pc_updated_by_branch
);

    // Helper signals
    logic is_br_insn_fetched;
    logic is_br_insn_decoded;
    logic [15:0] saved_insn_fetched_pc;
    logic [15:0] saved_br_target;
    logic [15:0] expected_delay_slot_pc;
    logic [15:0] pc_sequence [0:7];
    int pc_seq_idx;
    
    assign is_br_insn_fetched = (insn_fetched[15:12] == 4'h5);
    assign is_br_insn_decoded = (insn_decoded_reg[15:12] == 4'h5);
    
    // ========================================
    // ASSERTION 1: fetch_pc captures correct address
    // During branch: captures branch_target_pending
    // Normal: captures pc from previous cycle
    // ========================================
    property p_fetch_pc_capture;
        @(posedge clk) disable iff (rst || !running)
        (ram_rd_en && !$past(branch_pending)) |-> (fetch_pc == $past(pc));
    endproperty
    
    ast_fetch_pc_capture: assert property (p_fetch_pc_capture)
        else $error("[AST_FAIL] fetch_pc=%0d != pc(prev)=%0d at RAM read (normal fetch)", 
                    fetch_pc, $past(pc));
    
    // ========================================
    // ASSERTION 2: insn_fetched_pc captures fetch_pc at instruction valid
    // ========================================
    property p_insn_fetched_pc_capture;
        @(posedge clk) disable iff (rst || !running)
        (ram_rd_en ##1 insn_valid) |-> (insn_fetched_pc == $past(fetch_pc, 1));
    endproperty
    
    ast_insn_fetched_pc_capture: assert property (p_insn_fetched_pc_capture)
        else $error("[AST_FAIL] insn_fetched_pc=%0d != fetch_pc(RAM cycle)=%0d", 
                    insn_fetched_pc, $past(fetch_pc, 1));
    
    // ========================================
    // ASSERTION 3: br_insn_pc captures insn_fetched_pc at BR decode
    // ========================================
    property p_br_insn_pc_capture;
        @(posedge clk) disable iff (rst || !running)
        (insn_valid && is_br_insn_fetched) |=> (br_insn_pc == $past(insn_fetched_pc));
    endproperty
    
    ast_br_insn_pc_capture: assert property (p_br_insn_pc_capture)
        else $error("[AST_FAIL] br_insn_pc=%0d != insn_fetched_pc(prev)=%0d at BR detection", 
                    br_insn_pc, $past(insn_fetched_pc));
    
    // ========================================
    // ASSERTION 4: Delay slot PC must be BR_PC + 1
    // ========================================
    property p_delay_slot_pc;
        @(posedge clk) disable iff (rst || !running)
        (insn_decoded_valid && is_br_insn_decoded && branch_pending) |-> 
        ($past(fetch_pc) == (br_insn_pc + 16'd1));
    endproperty
    
    ast_delay_slot_pc: assert property (p_delay_slot_pc)
        else $error("[AST_FAIL] Delay slot PC incorrect: fetch_pc(prev)=%0d, expected=%0d (br_insn_pc=%0d)", 
                    $past(fetch_pc), br_insn_pc + 16'd1, br_insn_pc);
    
    // ======================================== 
    // ASSERTION 5: PC updated to branch target+1 after branch_pending clears
    // FIXED: PC points to NEXT instruction after fetch (PC is one ahead)
    // When branch_pending transitions 1->0, after fetching from target, PC = target+1
    // ========================================
    property p_pc_no_increment_on_branch_apply;
        @(posedge clk) disable iff (rst || !running)
        ($past(branch_pending) && !branch_pending) |-> (pc == $past(branch_target_pending) + 16'd1);
    endproperty
    
    ast_pc_no_increment_on_branch_apply: assert property (p_pc_no_increment_on_branch_apply)
        else $error("[AST_FAIL] PC not at target+1 after branch: pc=%0d, expected target+1=%0d", 
                    pc, $past(branch_target_pending) + 16'd1);
    
    // ========================================
    // ASSERTION 6: Branch target fetch verification
    // After branch_pending clears, next fetch must be from branch target
    // ========================================
    property p_branch_target_fetch;
        @(posedge clk) disable iff (rst || !running)
        ($past(branch_pending) && !branch_pending && ram_rd_en) |-> 
        (fetch_pc == $past(branch_target_pending));
    endproperty
    
    ast_branch_target_fetch: assert property (p_branch_target_fetch)
        else $error("[AST_FAIL] Branch target fetch incorrect: fetch_pc=%0d, expected target=%0d", 
                    fetch_pc, $past(branch_target_pending));
    
    // ========================================
    // ASSERTION 7: PC sequence continuity check
    // Verifies PC increments by 1 in normal execution (not during/after branch)
    // Excludes: reset recovery (PC<2), branch cycles, and 1 cycle after branch
    // ========================================
    logic past_was_branching;
    always_ff @(posedge clk) begin
        if (rst)
            past_was_branching <= 0;
        else
            past_was_branching <= branch_pending;
    end

    property p_pc_sequence_valid;
        @(posedge clk) disable iff (rst || !running)
        // Only check when: NOT branching, NOT recovering from branch, fetching, and PC > 1
        (ram_rd_en && !branch_pending && !past_was_branching && fetch_pc > 1) |-> 
        (fetch_pc == ($past(fetch_pc) + 16'd1));
    endproperty
    
    ast_pc_sequence_valid: assert property (p_pc_sequence_valid)
        else $error("[AST_FAIL] PC sequence invalid: fetch_pc=%0d, expected=%0d (sequential)", 
                    fetch_pc, $past(fetch_pc) + 16'd1);
    
    // ========================================
    // ASSERTION 8: fetch_pc equals source PC (branch target or incremented PC)
    // During branch: fetch_pc == branch_target_pending (from previous cycle)
    // Normal: fetch_pc == $past(pc)
    // ========================================
    property p_fetch_pc_matches_source;
        @(posedge clk) disable iff (rst || !running)
        (ram_rd_en && $past(branch_pending)) |-> (fetch_pc == $past(branch_target_pending));
    endproperty
    
    ast_fetch_pc_matches_source: assert property (p_fetch_pc_matches_source)
        else $error("[AST_FAIL] CRITICAL: fetch_pc=%0d != branch_target=%0d after branch", 
                    fetch_pc, $past(branch_target_pending));
    
    // ========================================
    // Debug monitoring with detailed output
    // ========================================
    always @(posedge clk) begin
        if (!rst && running) begin
            // Track PC sequence
            if (ram_rd_en || branch_pending) begin
                pc_sequence[pc_seq_idx % 8] <= pc;
                pc_seq_idx++;
            end
            
            // Monitor fetch stage with inline validation
            if (ram_rd_en) begin
                $display("[BR_DBG] @%0t FETCH: pc=%0d, fetch_pc=%0d", $time, pc, fetch_pc);
                // Inline validation to catch mismatches immediately
                if (fetch_pc != $past(pc)) begin
                    $display("[BR_DBG] *** CRITICAL: fetch_pc mismatch! fetch_pc=%0d, expected pc=%0d", 
                             fetch_pc, $past(pc));
                end
            end
            
            // Monitor instruction valid
            if (insn_valid) begin
                $display("[BR_DBG] @%0t VALID: insn=0x%04h, insn_fetched_pc=%0d, is_BR=%b", 
                         $time, insn_fetched, insn_fetched_pc, is_br_insn_fetched);
            end
            
            // Monitor BR detection at decode
            if (insn_valid && is_br_insn_fetched) begin
                saved_insn_fetched_pc <= insn_fetched_pc;
            end
            
            // Monitor BR execution
            if (insn_decoded_valid && is_br_insn_decoded) begin
                logic [8:0] offset;
                logic [15:0] offset_sext;
                logic [15:0] calculated_target;
                
                offset = insn_decoded_reg[8:0];
                offset_sext = {{7{offset[8]}}, offset};
                calculated_target = br_insn_pc + 16'd1 + offset_sext;
                
                $display("[BR_DBG] @%0t BR_EXEC: br_insn_pc=%0d, offset=%0d, calculated_target=%0d", 
                         $time, br_insn_pc, $signed(offset_sext), calculated_target);
                
                if (branch_pending) begin
                    $display("[BR_DBG] @%0t BR_PEND: branch_target_pending=%0d, delay_slot_pc=%0d", 
                             $time, branch_target_pending, fetch_pc);
                    saved_br_target <= branch_target_pending;
                    expected_delay_slot_pc <= br_insn_pc + 16'd1;
                    
                    // Check if delay slot PC is correct
                    if ($past(fetch_pc) != (br_insn_pc + 16'd1)) begin
                        $error("[BR_DBG] DELAY SLOT PC MISMATCH: fetch_pc(prev)=%0d, expected=%0d", 
                               $past(fetch_pc), br_insn_pc + 16'd1);
                    end
                end
            end
            
            // Monitor branch target application
            if ($past(branch_pending) && !branch_pending) begin
                $display("[BR_DBG] @%0t BR_APPLY: pc updated to %0d (expected target was %0d)", 
                         $time, pc, saved_br_target);
                
                if (pc != saved_br_target) begin
                    $error("[BR_DBG] PC UPDATE MISMATCH: pc=%0d, expected_target=%0d", 
                           pc, saved_br_target);
                end
            end
            
            // Monitor PC sequence for anomalies
            if (ram_rd_en && pc_seq_idx > 2) begin
                logic [15:0] pc_prev, pc_prev2;
                pc_prev = pc_sequence[(pc_seq_idx - 1) % 8];
                pc_prev2 = pc_sequence[(pc_seq_idx - 2) % 8];
                
                // Check for unexpected PC jumps (except when branch_pending or pc_updated_by_branch)
                if (!branch_pending && !pc_updated_by_branch && !$past(branch_pending)) begin
                    if (pc != (pc_prev + 16'd1) && pc != pc_prev) begin
                        $display("[BR_DBG] @%0t PC_JUMP: pc=%0d, prev=%0d, diff=%0d", 
                                 $time, pc, pc_prev, pc - pc_prev);
                    end
                end
            end
        end
        
        if (rst) begin
            pc_seq_idx = 0;
        end
    end
    
    // ========================================
    // Coverage: Track branch events
    // ========================================
    covergroup cg_branch_events @(posedge clk);
        option.per_instance = 1;
        
        cp_br_detected: coverpoint (insn_valid && is_br_insn_fetched) {
            bins detected = {1};
        }
        
        cp_branch_pending: coverpoint branch_pending {
            bins pending = {1};
        }
        
        cp_pc_updated: coverpoint pc_updated_by_branch {
            bins updated = {1};
        }
        
        cx_br_flow: cross cp_br_detected, cp_branch_pending;
    endgroup
    
    cg_branch_events cg = new();

endmodule

// Bind statement
bind td4cpu_core td4cpu_br_timing_assertions u_br_timing_assertions (
    .clk(clk),
    .rst(rst),
    .running(running),
    .pc(pc),
    .fetch_pc(fetch_pc),
    .insn_fetched_pc(insn_fetched_pc),
    .ram_rd_en(ram_rd_en),
    .insn_fetched(insn_fetched),
    .insn_valid(insn_valid),
    .br_insn_pc(br_insn_pc),
    .insn_decoded_reg(insn_decoded_reg),
    .insn_decoded_valid(insn_decoded_valid),
    .branch_pending(branch_pending),
    .branch_target_pending(branch_target_pending),
    .pc_updated_by_branch(pc_updated_by_branch)
);
