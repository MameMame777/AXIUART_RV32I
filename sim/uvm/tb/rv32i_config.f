# RV32I Core UVM Compilation File List for DSIM
# Updated: 2026-01-02 - UVM Environment Added

# Timescale
-timescale 1ns/1ps

# UVM Library
-uvm

# Include directories
+incdir+../../../rtl/cpu
+incdir+../../../rtl/interfaces
+incdir+../../../sim/assertions
+incdir+../sv
+incdir+../../tests

# RTL - ISA Package (must be compiled first)
../../../rtl/cpu/rv32i_isa_pkg.sv

# RTL - Core (includes trace buffer internally, no separate module needed)
../../../rtl/cpu/rv32i_core.sv

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
