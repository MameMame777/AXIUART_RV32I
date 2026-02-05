# DSIM Configuration for RV32I CPU UVM Tests
# Updated: 2026-02-06 - Migrated to VexRiscv Generated RTL

# Note: -timescale and -uvm are provided on command line, do not duplicate here

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

# Pipeline Debug Monitor (Direct Module - No Interface)
../../assertions/debug/rv32i_pipeline_monitor.sv
../../assertions/bind_rv32i_pipeline_monitor.sv

# WB Forwarding Correctness Assertions (Critical bug fix validation)
../../assertions/spec/rv32i_wb_forwarding_spec.sv
../../assertions/bind_rv32i_wb_forwarding_spec.sv

# Branch Operation Assertions (Validates BEQ/BNE/BLT/BGE/BLTU/BGEU logic)
../../assertions/spec/rv32i_branch_spec.sv
../../assertions/bind_rv32i_branch_spec.sv

# Memory Protection Assertions (Prevents data stores from corrupting instruction memory)
../../assertions/rv32i_mem_protect_spec.sv
../../assertions/bind_rv32i_mem_protect.sv

# Register File & Forwarding Debug Assertions (Diagnose x23/x24 confusion bug)
../../assertions/spec/rv32i_regfile_forward_debug_spec.sv
../../assertions/bind_rv32i_regfile_debug.sv

# Testbench Top (includes all UVM components via rv32i_test_pkg.sv)
rv32i_tb_top.sv
