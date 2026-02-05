# RV32I Core UVM Compilation File List for DSIM
# Updated: 2026-02-06 - Migrated to VexRiscv Generated RTL

# Timescale
-timescale 1ns/1ps

# UVM Library
-uvm

# Include directories
+incdir+../../../rtl/vexriscvwrap
+incdir+../../../rtl/interfaces
+incdir+../../../sim/assertions
+incdir+../sv
+incdir+../../tests

# RTL Design Files - VexRiscv Generated CPU Core (SpinalHDL)
../../../rtl/cpu/VexRiscv.v

# RTL Design Files - VexRiscv Wrapper Infrastructure
../../../rtl/vexriscvwrap/vexriscv_ibus_adapter.sv
../../../rtl/vexriscvwrap/vexriscv_dbus_adapter.sv
../../../rtl/vexriscvwrap/vexriscv_debug_bridge.sv
../../../rtl/vexriscvwrap/vexriscv_trace_probe.sv
../../../rtl/vexriscvwrap/vexriscv_blockram.sv
../../../rtl/vexriscvwrap/vexriscv_ebreak_monitor.sv
../../../rtl/vexriscvwrap/vexriscv_mem_crossbar.sv
../../../rtl/vexriscvwrap/vexriscv_control.sv
../../../rtl/vexriscvwrap/vexriscv_wrapper.sv

# UVM Components (must be compiled in dependency order)
# Transaction must come before monitor/scoreboard
../sv/rv32i_transaction.sv
../sv/rv32i_monitor.sv
../sv/rv32i_scoreboard.sv
../sv/rv32i_env.sv

# Test Package and Tests
../../tests/rv32i_test_pkg.sv

# Testbench Top
rv32i_tb_top.sv

# Optional: Assertions (if needed)
# ../../../sim/assertions/rv32i_pipeline_spec.sv
