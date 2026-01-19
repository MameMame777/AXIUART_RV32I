`timescale 1ns / 1ps
//==============================================================================
// Bind VexRiscv Fetch Verification Assertions
//==============================================================================
// Binds fetch cycle verification assertions to vexriscv_wrapper for debugging
// instruction fetch issues.
//==============================================================================

bind vexriscv_wrapper vexriscv_fetch_verification u_fetch_verify (
    .clk(clk),
    .rst(rst)
);
