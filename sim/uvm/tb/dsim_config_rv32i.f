# DSIM Configuration for RV32I CPU UVM Tests
# Updated: 2026-02-06 - Migrated to VexRiscv Generated RTL

# Note: -timescale and -uvm are provided on command line, do not duplicate here

# Include directories
+incdir+../../../rtl/vexriscvwrap
+incdir+../../../rtl/interfaces
+incdir+../../../rtl/uart_axi4_bridge
+incdir+../../../rtl/register_block
+incdir+../../../rtl
+incdir+../../../sim/assertions
+incdir+../sv
+incdir+../../tests

# Generated Register Package
../../../rtl/register_block/axiuart_reg_pkg.sv

# RTL Interface Definitions
../../../rtl/interfaces/uart_if.sv
../../../rtl/interfaces/axi4_lite_if.sv

# RTL Design Files - UART-AXI4 Bridge Core
../../../rtl/uart_axi4_bridge/fifo_sync.sv
../../../rtl/uart_axi4_bridge/Uart_Rx.sv
../../../rtl/uart_axi4_bridge/Uart_Tx.sv
../../../rtl/uart_axi4_bridge/Crc8_Calculator.sv
../../../rtl/uart_axi4_bridge/Frame_Parser.sv
../../../rtl/uart_axi4_bridge/Frame_Builder.sv
../../../rtl/uart_axi4_bridge/Address_Aligner.sv
../../../rtl/uart_axi4_bridge/Axi4_Lite_Master.sv
../../../rtl/uart_axi4_bridge/Uart_Axi4_Bridge.sv

# RTL Design Files - Register Block
../../../rtl/register_block/Register_Block.sv

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

# Top Level
../../../rtl/AXIUART_Top.sv

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
# ../../assertions/debug/rv32i_pipeline_monitor.sv  # File not present
# ../../assertions/bind_rv32i_pipeline_monitor.sv  # File not present

# WB Forwarding Correctness Assertions (Critical bug fix validation)
# ../../assertions/spec/rv32i_wb_forwarding_spec.sv  # Disabled for now
# ../../assertions/bind_rv32i_wb_forwarding_spec.sv  # Disabled for now

# Branch Operation Assertions (Validates BEQ/BNE/BLT/BGE/BLTU/BGEU logic)
# ../../assertions/spec/rv32i_branch_spec.sv  # Disabled for now
# ../../assertions/bind_rv32i_branch_spec.sv  # Disabled for now

# Memory Protection Assertions (Prevents data stores from corrupting instruction memory)
# ../../assertions/rv32i_mem_protect_spec.sv  # Disabled for now
# ../../assertions/bind_rv32i_mem_protect.sv  # Disabled for now

# Register File & Forwarding Debug Assertions (Diagnose x23/x24 confusion bug)
# ../../assertions/spec/rv32i_regfile_forward_debug_spec.sv  # Disabled for now
# ../../assertions/bind_rv32i_regfile_debug.sv  # Disabled for now

# UVM Environment and Base Test Classes
../sv/axiuart_pkg.sv
# ../sv/axiuart_base_test.sv  # Not needed for VexRiscv tests
../sv/vexriscv_base_test.sv

# Test Package (includes all VexRiscv test classes)
../../tests/rv32i_test_pkg.sv

# Testbench Top (includes all UVM components)
rv32i_tb_top.sv
