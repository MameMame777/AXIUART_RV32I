`timescale 1ns / 1ps

//==============================================================================
// TD4 CPU Flag Hazard Detection Assertions
//==============================================================================
// Purpose: Detect pipeline data hazards on the CPU flags register
//
// Root Cause: ALU instructions (CMP, ADDI) update flags in Stage 4 (writeback),
//             but BR instructions read flags in Stage 1 (decode), creating a
//             3-cycle data hazard without forwarding.
//
// Hazard Timeline:
//   Cycle N:   CMP/ADDI decoded, flags sampled
//   Cycle N+1: BR decoded, reads flags (STALE VALUE - HAZARD!)
//              ALU Stage 2 active
//   Cycle N+2: BR delay slot executes, ALU Stage 3 computes flags
//   Cycle N+3: Branch taken/not-taken, ALU Stage 4 writes flags (TOO LATE)
//
// Detection Strategy:
//   - Assert #1: No BR immediately after flag-modifying instruction
//   - Assert #2: Flags must be stable during BR decode
//   - Assert #3: Flag forwarding correctness (when implemented)
//
// Usage: Bind to td4cpu_core instance, enable with +define+ENABLE_ASSERTIONS
//==============================================================================

module td4cpu_flag_hazard_assertions
    import td4cpu_isa_pkg::*;
(
    input  logic        clk,
    input  logic        rst,
    
    // Pipeline control signals
    input  logic [15:0] insn_decoded_reg,
    input  logic        insn_decoded_valid,
    input  logic [15:0] insn_fetched,
    input  logic        insn_valid,
    
    // ALU pipeline stages
    input  logic        alu_valid_stage1,
    input  logic        alu_flags_update_en_stage2,
    input  logic        alu_flags_update_en_hold,    // Stage 3/4 flag update pending
    input  logic [2:0]  alu_flags_hold,              // Stage 3 computed flags (not yet written)
    
    // Register write forwarding
    input  logic        reg_write_pending,
    
    // CPU state
    input  logic        running,
    input  logic        halted,
    input  logic [2:0]  flags                        // Committed flags register
);

    //--------------------------------------------------------------------------
    // Local Variables
    //--------------------------------------------------------------------------
    logic [3:0] insn_opcode;
    logic [3:0] fetched_opcode;
    logic [5:0] insn_funct;
    logic       is_flag_modifying_insn;
    logic       is_branch_insn;
    
    assign insn_opcode = insn_decoded_reg[15:12];
    assign fetched_opcode = insn_fetched[15:12];
    assign insn_funct = insn_decoded_reg[5:0];
    
    // Detect instructions that modify flags
    assign is_flag_modifying_insn = insn_decoded_valid && (
        (insn_opcode == OP_R_ALU && insn_funct == FUNCT_CMP) ||  // CMP modifies Z,N,C
        (insn_opcode == OP_ADDI)                                   // ADDI modifies Z,N,C
    );
    
    // Detect branch instructions
    assign is_branch_insn = insn_decoded_valid && (insn_opcode == OP_BR);
    
    //--------------------------------------------------------------------------
    // ASSERTION 1: No BR immediately after flag-modifying instruction
    //--------------------------------------------------------------------------
    // Detects back-to-back CMP→BR or ADDI→BR without flag propagation.
    // This is the PRIMARY hazard detection.
    //
    // Pattern:
    //   Cycle N:   CMP/ADDI decoded (is_flag_modifying_insn=1)
    //   Cycle N+1: BR decoded (is_branch_insn=1)
    //              alu_flags_update_en_hold should be 0 (flags committed)
    //
    // If alu_flags_update_en_hold==1 at Cycle N+1, flags are still in pipeline
    // and BR is reading stale values.
    //--------------------------------------------------------------------------
    property no_br_after_flag_modify;
        @(posedge clk) disable iff (rst || !running)
        (is_flag_modifying_insn)  // Flag-modifying instruction decoded
        ##1 (is_branch_insn)      // Next cycle: branch decoded
        |-> (alu_flags_update_en_hold == 1'b0);  // Flags MUST be committed
    endproperty
    
    ast_no_br_after_flag_modify: assert property (no_br_after_flag_modify)
    else begin
        $error("[FLAG_HAZARD] BR decoded while flags still in ALU pipeline!");
        $error("  Previous insn: opcode=0x%h, funct=0x%h (flag-modifying)", 
               insn_opcode, insn_funct);
        $error("  Current insn:  opcode=0x%h (BR)", insn_decoded_reg[15:12]);
        $error("  alu_flags_update_en_hold=%b (should be 0)", alu_flags_update_en_hold);
        $error("  Committed flags=%b, ALU flags=%b", flags, alu_flags_hold);
    end
    
    //--------------------------------------------------------------------------
    // ASSERTION 2: Flags stable during BR decode
    //--------------------------------------------------------------------------
    // Ensures no ALU Stage 2-4 flag updates are in-flight when BR decodes.
    // This is a more general check than Assert #1.
    //--------------------------------------------------------------------------
    property flags_stable_during_br;
        @(posedge clk) disable iff (rst || !running)
        (is_branch_insn)
        |-> (alu_flags_update_en_stage2 == 1'b0 &&
             alu_flags_update_en_hold == 1'b0);
    endproperty
    
    ast_flags_stable_during_br: assert property (flags_stable_during_br)
    else begin
        $error("[FLAG_HAZARD] Flags being updated during BR decode!");
        $error("  BR insn: 0x%04h", insn_decoded_reg);
        $error("  alu_flags_update_en_stage2=%b", alu_flags_update_en_stage2);
        $error("  alu_flags_update_en_hold=%b", alu_flags_update_en_hold);
    end
    
    //--------------------------------------------------------------------------
    // ASSERTION 3: Flag forwarding correctness (when forwarding implemented)
    //--------------------------------------------------------------------------
    // When flag forwarding is active, ensure forwarded flags match ALU Stage 3.
    // NOTE: This requires adding 'effective_flags' signal to CPU core.
    //       Commented out until forwarding is implemented.
    //--------------------------------------------------------------------------
    // property flag_forward_correct;
    //     @(posedge clk) disable iff (rst || !running)
    //     (is_branch_insn && alu_flags_update_en_hold)
    //     |-> (effective_flags == alu_flags_hold);
    // endproperty
    //
    // ast_flag_forward_correct: assert property (flag_forward_correct)
    // else $error("[FLAG_HAZARD] Flag forwarding mismatch: effective=%b, alu=%b",
    //             effective_flags, alu_flags_hold);
    
    //--------------------------------------------------------------------------
    // COVERAGE: Track hazard scenarios
    //--------------------------------------------------------------------------
    covergroup cg_flag_hazards @(posedge clk);
        option.per_instance = 1;
        
        // Cover CMP→BR sequences
        cp_cmp_br: coverpoint {is_flag_modifying_insn, insn_funct, is_branch_insn} {
            bins cmp_then_br = (4'b1_000110_0 => 4'b0_xxxxxx_1);  // CMP (funct=6) → BR
        }
        
        // Cover ADDI→BR sequences
        cp_addi_br: coverpoint {is_flag_modifying_insn, insn_opcode, is_branch_insn} {
            bins addi_then_br = (4'b1_0011_0 => 4'b0_xxxx_1);    // ADDI (opcode=3) → BR
        }
        
        // Cover hazard with/without forwarding
        cp_hazard_state: coverpoint alu_flags_update_en_hold {
            bins no_hazard = {1'b0};
            bins hazard_pending = {1'b1};
        }
        
        // Cross: hazard state during BR decode
        cx_br_hazard: cross cp_hazard_state, is_branch_insn {
            ignore_bins not_br = binsof(is_branch_insn) intersect {0};
        }
    endgroup
    
    cg_flag_hazards cg_inst = new();
    
    //--------------------------------------------------------------------------
    // DEBUG: Report hazard detections (info only, not an error)
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst && running && is_branch_insn && alu_flags_update_en_hold) begin
            $display("[FLAG_HAZARD_INFO] @%0t: Potential hazard detected", $time);
            $display("  BR decoding while flags in pipeline (Stage 3/4)");
            $display("  Committed flags: Z=%b N=%b C=%b", flags[0], flags[1], flags[2]);
            $display("  ALU Stage 3:     Z=%b N=%b C=%b", alu_flags_hold[0], alu_flags_hold[1], alu_flags_hold[2]);
            $display("  NOTE: If flag forwarding is implemented, this is OK. Otherwise, HAZARD!");
        end
    end

endmodule
