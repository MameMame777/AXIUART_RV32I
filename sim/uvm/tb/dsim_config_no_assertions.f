# DSIM Configuration File - NO ASSERTIONS VERSION
# UBUS-style simplified environment (Assertions Disabled)
# Created: 2026-01-05 - For performance testing and production simulation

# UVM Defines
+define+UVM_OBJECT_MUST_HAVE_CONSTRUCTOR
+define+DEFINE_SIM
+define+WAVES
+define+UVM_ENABLE_DEPRECATED_API
+define+UVM_REGEX_NO_DPI

# UVM Trace (critical for debug)
+UVM_OBJECTION_TRACE
+UVM_PHASE_TRACE
+UVM_SEQ_CHECKS

# Include paths
+incdir+../../../rtl/interfaces
+incdir+../../../rtl/uart_axi4_bridge
+incdir+../../../rtl/register_block
+incdir+../../../rtl
+incdir+../sv
+incdir+../../tests
+incdir+.

# Generated Register Package (from register_map/axiuart_registers.json)
../../../rtl/register_block/axiuart_reg_pkg.sv

# Generated ISA package (from isa/)
../../../rtl/cpu/rv32i_isa_pkg.sv

# RTL Interface Definitions
../../../rtl/interfaces/uart_if.sv
../../../rtl/interfaces/axi4_lite_if.sv

# RTL Design Files - UART-AXI4 Bridge Core (reusable)
../../../rtl/uart_axi4_bridge/fifo_sync.sv
../../../rtl/uart_axi4_bridge/Uart_Rx.sv
../../../rtl/uart_axi4_bridge/Uart_Tx.sv
../../../rtl/uart_axi4_bridge/Crc8_Calculator.sv
../../../rtl/uart_axi4_bridge/Frame_Parser.sv
../../../rtl/uart_axi4_bridge/Frame_Builder.sv
../../../rtl/uart_axi4_bridge/Address_Aligner.sv
../../../rtl/uart_axi4_bridge/Axi4_Lite_Master.sv
../../../rtl/uart_axi4_bridge/Uart_Axi4_Bridge.sv

# RTL Design Files - Register Block (project-specific)
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

# Testbench Top Module (includes package and test_lib)
+incdir+.
./rv32i_tb_top.sv
