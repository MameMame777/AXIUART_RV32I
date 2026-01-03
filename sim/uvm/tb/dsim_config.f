# DSIM Configuration File for Simplified AXIUART UVM Testbench
# UBUS-style simplified environment

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

# RTL Design Files - CPU core (project-specific)
../../../rtl/cpu/rv32i_core.sv
../../../rtl/cpu/rv32i_trace_buffer.sv

# Top Level
../../../rtl/AXIUART_Top.sv

# Assertions - Debug Port
../../assertions/rv32i_debug_port_assertions.sv

# Assertions - Register Block CPU Memory Interface
../../assertions/register_block_cpu_mem_assertions.sv
../../assertions/bind_register_block_cpu_mem.sv

# Testbench Top Module (includes package and test_lib)
+incdir+.
./axiuart_tb_top.sv
