`timescale 1ns / 1ps

// Debug assertion module for exec_pc vs insn_fetched_pc tracking
// Monitors the relationship between global exec_pc and per-instruction insn_fetched_pc
// during BR instruction capture to detect timing bugs in br_insn_pc assignment
//
// KEY INSIGHT: exec_pc is a global "next fetch" tracker that updates continuously,
// while insn_fetched_pc is captured atomically with each instruction's RAM data.
// BR instruction PC capture MUST use insn_fetched_pc to avoid exec_pc advancement errors.
module td4cpu_exec_pc_tracking_assertions (
    input logic clk,
    input logic rst,
    input logic running,
    
    // PC tracking signals
    input logic [15:0] pc,               // Current PC (increments during fetch)
    input logic [15:0] exec_pc,          // Global execution PC (updates every fetch)
    input logic [15:0] insn_fetched_pc,  // Per-instruction PC (captured with RAM data)
    input logic [15:0] br_insn_pc,       // Branch instruction PC (for target calculation)
    
    // Fetch/decode signals
    input logic [15:0] ram_rd_data,      // RAM read data (instruction bits)
    input logic        insn_valid,       // Instruction valid (fetch completed)
    input logic        ram_rd_en         // RAM read enable
);

    // Helper signals
    logic is_br_insn_fetched;
    logic [15:0] prev_insn_fetched_pc;
    
    assign is_br_insn_fetched = (ram_rd_data[15:12] == 4'h5);  // OP_BR = 0x5
    
    // Track previous insn_fetched_pc for comparison
    always_ff @(posedge clk) begin
        if (rst) begin
            prev_insn_fetched_pc <= 16'h0;
        end else if (insn_valid) begin
            prev_insn_fetched_pc <= insn_fetched_pc;
        end
    end
    
    // ========================================
    // ASSERTION 1: BR instruction PC capture correctness
    // When BR instruction fetch completes, br_insn_pc MUST equal insn_fetched_pc
    // (not exec_pc, which may have advanced during pipeline progression)
    // ========================================
    property p_br_insn_pc_equals_fetched_pc;
        @(posedge clk) disable iff (rst || !running)
        (ram_rd_en && running && is_br_insn_fetched) |=> 
        (br_insn_pc == $past(insn_fetched_pc));
    endproperty
    
    ast_br_insn_pc_equals_fetched_pc: assert property (p_br_insn_pc_equals_fetched_pc)
        else $error("[AST_EXEC_PC] BR capture bug: br_insn_pc=%0d != insn_fetched_pc=%0d (exec_pc=%0d). Using exec_pc causes +1 offset in branch targets!",
                    br_insn_pc, $past(insn_fetched_pc), exec_pc);
    
    // ========================================
    // ASSERTION 2: exec_pc consistency during normal fetch
    // exec_pc should track pc correctly (excluding branch/delay-slot cases)
    // This validates that exec_pc updates are synchronized with fetch operations
    // ========================================
    property p_exec_pc_consistency;
        @(posedge clk) disable iff (rst || !running)
        (ram_rd_en) |-> (exec_pc inside {pc, $past(pc), $past(pc, 2)});
    endproperty
    
    ast_exec_pc_consistency: assert property (p_exec_pc_consistency)
        else $error("[AST_EXEC_PC] exec_pc=%0d out of range: pc=%0d, pc(-1)=%0d, pc(-2)=%0d",
                    exec_pc, pc, $past(pc), $past(pc, 2));
    
    // ========================================
    // ASSERTION 3: insn_fetched_pc captures correctly
    // When instruction becomes valid, insn_fetched_pc should have captured
    // a recent exec_pc value (within 2-3 cycles of fetch initiation)
    // ========================================
    property p_insn_fetched_pc_capture;
        @(posedge clk) disable iff (rst || !running)
        (insn_valid && $past(ram_rd_en, 1)) |-> 
        (insn_fetched_pc == $past(exec_pc, 1));
    endproperty
    
    ast_insn_fetched_pc_capture: assert property (p_insn_fetched_pc_capture)
        else $error("[AST_EXEC_PC] insn_fetched_pc=%0d != exec_pc(at capture)=%0d",
                    insn_fetched_pc, $past(exec_pc, 1));
    
    // ========================================
    // DEBUG: Display PC values when BR instruction detected
    // Helps visualize the timing relationship during debug
    // ========================================
    `ifdef ENABLE_ASSERTIONS
    always @(posedge clk) begin
        if (running && ram_rd_en && is_br_insn_fetched) begin
            $display("[DEBUG_EXEC_PC] @%0t BR detected: pc=%0d, exec_pc=%0d, insn_fetched_pc=%0d, br_insn_pc=%0d",
                     $time, pc, exec_pc, insn_fetched_pc, br_insn_pc);
        end
    end
    `endif

endmodule

// Bind statement
bind td4cpu_core td4cpu_exec_pc_tracking_assertions u_exec_pc_tracking (
    .clk(clk),
    .rst(rst),
    .running(running),
    .pc(pc),
    .exec_pc(exec_pc),
    .insn_fetched_pc(insn_fetched_pc),
    .br_insn_pc(br_insn_pc),
    .ram_rd_data(ram_rd_data),
    .insn_valid(insn_valid),
    .ram_rd_en(ram_rd_en)
);
