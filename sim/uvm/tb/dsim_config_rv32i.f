# DSIM Configuration for RV32I CPU UVM Tests
# Updated: 2026-01-02 - RV32I UVM Environment

# Note: -timescale and -uvm are provided on command line, do not duplicate here

# Include directories
+incdir+../../../rtl/cpu
+incdir+../../../rtl/interfaces
+incdir+../../../sim/assertions
+incdir+../sv
+incdir+../../tests

# RTL - ISA Package (must be compiled first)
../../../rtl/cpu/rv32i_isa_pkg.sv

# RTL - Core
../../../rtl/cpu/rv32i_core.sv

# Assertions
../../assertions/rv32i_mem_access_spec.sv
../../assertions/bind_rv32i_mem_spec.sv

# Testbench Top (includes all UVM components via rv32i_test_pkg.sv)
rv32i_tb_top.sv
