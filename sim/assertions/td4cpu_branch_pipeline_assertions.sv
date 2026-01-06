`timescale 1ns / 1ps

// Debug assertion module for branch pipeline flush verification
// Monitors pipeline state during branch application to ensure stale instructions
// are properly flushed and do not execute after branch target fetch
//
// KEY REQUIREMENT: When branch_pending transitions from 1→0 (branch applied),
// both insn_valid and insn_decoded_valid MUST be cleared to prevent execution
// of the instruction fetched during the delay slot (PC+1 after branch).
module td4cpu_branch_pipeline_assertions (
    input logic clk,
    input logic rst,
    input logic running,
    
    // Branch control signals
    input logic        branch_pending,
    input logic        branch_delay_slot_active,
    input logic [15:0] branch_target_pending,
    
    // Pipeline control signals
    input logic        insn_valid,
    input logic        insn_decoded_valid,
    
    // PC tracking
    input logic [15:0] pc,
    input logic [15:0] exec_pc,
    input logic [15:0] insn_fetched_pc,
    input logic [15:0] insn_decoded_pc,
    
    // Instruction data
    input logic [15:0] insn_fetched,
    input logic [15:0] insn_decoded_reg,
    
    // RAM control
    input logic [15:0] ram_addr_next,
    input logic        ram_rd_en
);

    // Track previous cycle values for edge detection
    logic prev_branch_pending;
    logic prev_branch_delay_slot_active;
    logic [15:0] prev_pc;
    logic [15:0] saved_delay_slot_pc;
    logic [15:0] expected_target_fetch_addr;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            prev_branch_pending <= 1'b0;
            prev_branch_delay_slot_active <= 1'b0;
            prev_pc <= 16'h0;
            saved_delay_slot_pc <= 16'h0;
            expected_target_fetch_addr <= 16'h0;
        end else begin
            prev_branch_pending <= branch_pending;
            prev_branch_delay_slot_active <= branch_delay_slot_active;
            prev_pc <= pc;
            
            // Save delay slot PC when entering delay slot state
            if (!prev_branch_delay_slot_active && branch_delay_slot_active) begin
                saved_delay_slot_pc <= pc;
            end
            
            // Calculate expected target fetch address when branch applies
            if (prev_branch_pending && !branch_pending) begin
                expected_target_fetch_addr <= (branch_target_pending <= 16'd1) ? 16'd0 : (branch_target_pending - 16'd1);
            end
        end
    end
    
    // ========================================
    // ASSERTION 1: Pipeline flush on branch application
    // When branch_pending transitions 1→0, both pipeline stages must be cleared
    // to prevent stale instruction (fetched during delay slot) from executing
    // ========================================
    property p_pipeline_flush_on_branch;
        @(posedge clk) disable iff (rst || !running)
        (prev_branch_pending && !branch_pending) |-> (!insn_valid && !insn_decoded_valid);
    endproperty
    
    ast_pipeline_flush_on_branch: assert property (p_pipeline_flush_on_branch)
        else $error("[AST_BR_PIPE] Pipeline NOT flushed on branch apply: branch_pending 1→0, but insn_valid=%b, insn_decoded_valid=%b. Stale instruction will execute!",
                    insn_valid, insn_decoded_valid);
    
    // ========================================
    // ASSERTION 2: Branch target fetch address correctness
    // When branch applies, RAM fetch address must match target PC mapping
    // (target PC=T fetches from ram[T-1], except PC≤1 fetches ram[0])
    // ========================================
    property p_branch_target_fetch_addr;
        @(posedge clk) disable iff (rst || !running)
        (prev_branch_pending && !branch_pending && ram_rd_en) |-> 
        (ram_addr_next == expected_target_fetch_addr);
    endproperty
    
    ast_branch_target_fetch_addr: assert property (p_branch_target_fetch_addr)
        else $error("[AST_BR_PIPE] Branch target fetch address wrong: ram_addr_next=%0d, expected=%0d (target_pc=%0d)",
                    ram_addr_next, expected_target_fetch_addr, branch_target_pending);
    
    // ========================================
    // ASSERTION 3: PC updated to target on branch application
    // When branch_pending clears, PC must equal branch_target_pending
    // ========================================
    property p_pc_equals_target_on_apply;
        @(posedge clk) disable iff (rst || !running)
        (prev_branch_pending && !branch_pending) |-> (pc == $past(branch_target_pending));
    endproperty
    
    ast_pc_equals_target_on_apply: assert property (p_pc_equals_target_on_apply)
        else $error("[AST_BR_PIPE] PC not updated to target: pc=%0d, expected target=%0d",
                    pc, $past(branch_target_pending));
    
    // ========================================
    // ASSERTION 4: No instruction execution during branch application
    // When branch applies (branch_pending 1→0), insn_decoded_valid must be 0
    // to prevent the delay-slot-fetched instruction from executing
    // ========================================
    property p_no_exec_during_branch_apply;
        @(posedge clk) disable iff (rst || !running)
        ($fell(branch_pending)) |-> (!insn_decoded_valid throughout ##1 insn_valid);
    endproperty
    
    ast_no_exec_during_branch_apply: assert property (p_no_exec_during_branch_apply)
        else $error("[AST_BR_PIPE] Instruction executed during branch apply: insn_decoded_valid=%b, insn_decoded_pc=%0d, insn=0x%04x",
                    insn_decoded_valid, insn_decoded_pc, insn_decoded_reg);
    
    // ========================================
    // ASSERTION 5: Delay slot executes exactly once
    // Between branch decode (delay_slot_active rise) and branch apply (pending fall),
    // exactly one instruction should execute at delay slot PC
    // ========================================
    int delay_slot_exec_count;
    logic [15:0] delay_slot_target_pc;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            delay_slot_exec_count <= 0;
            delay_slot_target_pc <= 16'h0;
        end else if (running) begin
            // Reset counter when entering delay slot
            if ($rose(branch_delay_slot_active)) begin
                delay_slot_exec_count <= 0;
                delay_slot_target_pc <= pc;  // Save delay slot PC
            end
            
            // Count executions during delay slot period
            if (branch_delay_slot_active && insn_decoded_valid && (insn_decoded_pc == delay_slot_target_pc)) begin
                delay_slot_exec_count <= delay_slot_exec_count + 1;
            end
            
            // Check count when branch applies
            if ($fell(branch_pending)) begin
                if (delay_slot_exec_count != 1) begin
                    $error("[AST_BR_PIPE] Delay slot execution count wrong: count=%0d, expected=1 (delay_slot_pc=%0d)",
                           delay_slot_exec_count, delay_slot_target_pc);
                end
            end
        end
    end
    
    // ========================================
    // DEBUG: Display branch pipeline transitions
    // ========================================
    `ifdef ENABLE_ASSERTIONS
    always @(posedge clk) begin
        if (running) begin
            if ($rose(branch_delay_slot_active)) begin
                $display("[DEBUG_BR_PIPE] @%0t Delay slot active: pc=%0d, target=%0d",
                         $time, pc, branch_target_pending);
            end
            if ($rose(branch_pending)) begin
                $display("[DEBUG_BR_PIPE] @%0t Branch pending: delay slot fetch complete, pc=%0d",
                         $time, pc);
            end
            if ($fell(branch_pending)) begin
                $display("[DEBUG_BR_PIPE] @%0t Branch applied: pc=%0d→%0d, insn_valid=%b, insn_decoded_valid=%b",
                         $time, prev_pc, pc, insn_valid, insn_decoded_valid);
            end
        end
    end
    `endif

endmodule

// Bind statement
bind td4cpu_core td4cpu_branch_pipeline_assertions u_branch_pipeline (
    .clk(clk),
    .rst(rst),
    .running(running),
    .branch_pending(branch_pending),
    .branch_delay_slot_active(branch_delay_slot_active),
    .branch_target_pending(branch_target_pending),
    .insn_valid(insn_valid),
    .insn_decoded_valid(insn_decoded_valid),
    .pc(pc),
    .exec_pc(exec_pc),
    .insn_fetched_pc(insn_fetched_pc),
    .insn_decoded_pc(insn_decoded_pc),
    .insn_fetched(insn_fetched),
    .insn_decoded_reg(insn_decoded_reg),
    .ram_addr_next(ram_addr_next),
    .ram_rd_en(ram_rd_en)
);
