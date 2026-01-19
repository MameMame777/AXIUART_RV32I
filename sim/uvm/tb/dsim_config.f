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

# UVM Package (environment, agents, sequences)
../sv/axiuart_pkg.sv

# Generated ISA package (from isa/)
# ../../../rtl/cpu/rv32i_isa_pkg.sv  # Legacy RV32I - not used

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

# RTL Design Files - VexRiscv CPU (GenSmallAndProductive)
../../../rtl/cpu/vexriscv_pkg.sv
../../../rtl/cpu/vexriscv_regfile.sv
../../../rtl/cpu/vexriscv_stream_fifo.sv
../../../rtl/cpu/vexriscv_ibus_simple.sv
../../../rtl/cpu/vexriscv_dbus_simple.sv
../../../rtl/cpu/vexriscv_hazard_simple.sv
../../../rtl/cpu/vexriscv_branch.sv
../../../rtl/cpu/vexriscv_csr.sv
../../../rtl/cpu/vexriscv_execute.sv
../../../rtl/cpu/vexriscv_decoder.sv
../../../rtl/cpu/vexriscv_top.sv

# RTL Design Files - VexRiscv UART Integration
../../../rtl/cpu/vexriscv_blockram.sv
../../../rtl/cpu/vexriscv_ebreak_monitor.sv
../../../rtl/cpu/vexriscv_mem_crossbar.sv
../../../rtl/cpu/vexriscv_control.sv
../../../rtl/cpu/vexriscv_wrapper.sv

# Top Level
../../../rtl/AXIUART_Top.sv

# Assertions - Debug Port (compatible with VexRiscv wrapper)
../../assertions/rv32i_debug_port_assertions.sv

# VexRiscv tohost Monitor (ISA test pass/fail detection)
../../assertions/bind_vexriscv_tohost_monitor.sv

# Assertions - RV32I Pipeline Stages (legacy - commented out for VexRiscv)
# ../../assertions/rv32i_if_timing_spec.sv
# ../../assertions/bind_rv32i_if_spec.sv
# ../../assertions/rv32i_hazard_timing_spec.sv
# ../../assertions/bind_rv32i_hazard_spec.sv
# ../../assertions/rv32i_ex_timing_spec.sv
# ../../assertions/bind_rv32i_ex_spec.sv
# ../../assertions/rv32i_mem_timing_spec.sv
# ../../assertions/bind_rv32i_mem_spec.sv
# ../../assertions/rv32i_wb_timing_spec.sv
# ../../assertions/bind_rv32i_wb_spec.sv
# ../../assertions/rv32i_id_timing_spec.sv
# ../../assertions/bind_rv32i_id_spec.sv
# ../../assertions/bind_rv32i_csr_spec.sv

# Assertions - Register Block CPU Memory Interface (compatible with VexRiscv)
../../assertions/register_block_cpu_mem_assertions.sv
../../assertions/bind_register_block_cpu_mem.sv

# VexRiscv Fetch Verification Assertions (debugging fetch cycle issues)
../../assertions/spec/vexriscv_fetch_verification.sv
../../assertions/bind_vexriscv_fetch_verification.sv

# VexRiscv Base Test and Monitor
../sv/vexriscv_base_test.sv
../sv/vexriscv_tohost_monitor.sv

# VexRiscv Stage 1 Tests
../../tests/vexriscv_regfile_test.sv
../../tests/vexriscv_pipeline_flow_test.sv
../../tests/vexriscv_memory_access_test.sv
../../tests/vexriscv_ex_bypass_test.sv
../../tests/vexriscv_mem_bypass_test.sv
../../tests/vexriscv_wb_bypass_test.sv
../../tests/vexriscv_load_use_stall_test.sv
../../tests/vexriscv_ibus_fetch_test.sv
../../tests/vexriscv_dbus_access_test.sv

# Testbench Top Module (includes package and test_lib)
+incdir+.
./rv32i_tb_top.sv
