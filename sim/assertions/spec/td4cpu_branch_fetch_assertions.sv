`timescale 1ns / 1ps

//==============================================================================
// TD4 CPU Branch and Fetch Address Assertion Module
//==============================================================================

module td4cpu_branch_fetch_assertions #(
    parameter RAM_SIZE = 1024
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        running,
    input  logic        halted,
    input  logic [15:0] pc,
    input  logic [15:0] ram_addr_next,
    input  logic [15:0] fetch_pc,
    input  logic        ram_rd_en,
    input  logic        branch_pending,
    input  logic [15:0] branch_target_pending,
    input  logic [15:0] br_insn_pc
);

    // Helper functions
    function automatic logic is_valid(logic [15:0] addr);
        return (addr < RAM_SIZE);
    endfunction


    //==========================================================================
    // ASSERTION 1: Branch Fetch Address
    //==========================================================================
    
    property p_branch_fetch_addr;
        @(posedge clk) disable iff (!rst_n || halted || !running)
        (branch_pending && is_valid(branch_target_pending)) |=>
        (ram_addr_next == (branch_target_pending - 16'd1));
    endproperty
    
    ast_branch_fetch_addr: assert property (p_branch_fetch_addr)
        else $error("[ASSERTION FAIL] Branch fetch addr: target=%0d, expected addr=%0d, got %0d",
                    $past(branch_target_pending), $past(branch_target_pending)-1, ram_addr_next);


    //==========================================================================
    // ASSERTION 2: PC After Branch
    //==========================================================================
    
    property p_pc_after_branch;
        logic [15:0] target;
        @(posedge clk) disable iff (!rst_n || halted || !running)
        (branch_pending, target = branch_target_pending) |=> (pc == target);
    endproperty
    
    ast_pc_after_branch: assert property (p_pc_after_branch)
        else $error("[ASSERTION FAIL] PC after branch: expected %0d, got %0d",
                    $past(branch_target_pending), pc);


    //==========================================================================
    // ASSERTION 3: Normal Fetch Address
    //==========================================================================
    
    property p_normal_fetch_addr;
        logic [15:0] exp_addr;
        @(posedge clk) disable iff (!rst_n || halted || !running)
        (!branch_pending && ram_rd_en && is_valid(pc), 
         exp_addr = (pc <= 16'd1) ? 16'd0 : (pc - 16'd1))
        |-> (ram_addr_next == exp_addr);
    endproperty
    
    ast_normal_fetch_addr: assert property (p_normal_fetch_addr)
        else $error("[ASSERTION FAIL] Normal fetch addr PC=%0d: expected %0d, got %0d",
                    pc, (pc <= 16'd1) ? 16'd0 : (pc - 16'd1), ram_addr_next);


    //==========================================================================
    // INFO: Branch Tracker
    //==========================================================================
    
    always @(posedge clk) begin
        if (rst_n && running && !halted && branch_pending) begin
            $display("[ASSERT_INFO] @%0t Branch: insn_pc=%0d target=%0d ram_addr=%0d", 
                     $time, br_insn_pc, branch_target_pending, ram_addr_next);
        end
    end

endmodule


//==============================================================================
// Bind
//==============================================================================

bind td4cpu_core td4cpu_branch_fetch_assertions #(
    .RAM_SIZE(1024)
) u_branch_fetch_assert (
    .clk(clk),
    .rst_n(rst_n),
    .running(running),
    .halted(halted),
    .pc(pc),
    .ram_addr_next(ram_addr_next),
    .fetch_pc(fetch_pc),
    .ram_rd_en(ram_rd_en),
    .branch_pending(branch_pending),
    .branch_target_pending(branch_target_pending),
    .br_insn_pc(br_insn_pc)
);
