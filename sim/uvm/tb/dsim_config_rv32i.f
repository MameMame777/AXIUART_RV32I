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

# RTL - Pipeline Package (types for modular architecture)
../../../rtl/cpu/rv32i_pipeline_pkg.sv

# RTL - Modular Pipeline Stages
../../../rtl/cpu/rv32i_if.sv
../../../rtl/cpu/rv32i_id.sv
../../../rtl/cpu/rv32i_hazard.sv
../../../rtl/cpu/rv32i_ex.sv
../../../rtl/cpu/rv32i_mem.sv
../../../rtl/cpu/rv32i_wb.sv

# RTL - CSR Module
../../../rtl/cpu/rv32i_csr.sv

# RTL - Top Level Integration
../../../rtl/cpu/rv32i_top.sv

# RTL - Trace Buffer
../../../rtl/cpu/rv32i_trace_buffer.sv

# NOTE: Old monolithic rv32i_core.sv archived to rtl/cpu/archive/ (2026-01-05)
# Use modular architecture (rv32i_top.sv) instead

# Assertions (TD4-specific mem access assertions disabled for RV32I)
# ../../assertions/rv32i_mem_access_spec.sv
# ../../assertions/bind_rv32i_mem_spec.sv

# Breakpoint assertions (TEMPORARILY DISABLED - need hierarchy update for modular arch)
# ../../assertions/rv32i_breakpoint_spec.sv
# ../../assertions/bind_rv32i_breakpoint_spec.sv

# Exception trap timing assertions (TEMPORARILY DISABLED - need hierarchy update for modular arch)
# ../../assertions/rv32i_csr_timing_spec.sv
# ../../assertions/rv32i_exception_trap_spec.sv
# ../../assertions/rv32i_debug_state_spec.sv
# ../../assertions/bind_rv32i_exception_spec.sv

# Branch debug assertions (DISABLED - files not present)
# ../../assertions/rv32i_branch_debug_assertions.sv
# ../../assertions/rv32i_branch_debug_bind.sv

# Testbench Top (includes all UVM components via rv32i_test_pkg.sv)
rv32i_tb_top.sv
