`timescale 1ns / 1ps
//==============================================================================
// VexRiscv tohost Monitor Bind File (PLACEHOLDER)
//==============================================================================
// Description:
//   The vexriscv_tohost_monitor is a UVM component, not a module, so it
//   cannot be bound using the 'bind' statement. Instead, it should be
//   instantiated within the UVM environment or test class.
//
// Usage in vexriscv_base_test.sv:
//   vexriscv_tohost_monitor_blockram monitor;
//   monitor = vexriscv_tohost_monitor_blockram::type_id::create("monitor", this);
//   monitor.tohost_addr = 32'h00001000;
//   fork
//       monitor.monitor_tohost();  // Background task
//   join_none
//
// Hierarchical Path for BlockRAM:
//   The monitor uses backdoor access to:
//   mem_crossbar.blockram_inst.mem[tohost_addr[12:2]]
//
// Author: GitHub Copilot (Claude Sonnet 4.5)
// Date: January 18, 2026
//==============================================================================

// This file intentionally left empty - UVM component binding happens in test code
// Include this file to document the hierarchical path, but no actual binding needed

`ifdef SIMULATION
initial begin
    $display("[INFO] VexRiscv tohost monitor documentation file loaded");
    $display("       Monitor is a UVM component - instantiate in test class, not bound here");
    $display("       BlockRAM path: mem_crossbar.blockram_inst.mem");
    $display("       tohost address: 0x00001000");
end
`endif


