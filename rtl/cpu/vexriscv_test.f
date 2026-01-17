# VexRiscv CPU Compilation File List
# Usage: dsim -f vexriscv_test.f +define+VEXRISCV_CPU <other_files>
# Purpose: Compile VexRiscv wrapper and dependencies for UART integration

# SystemVerilog package (must be first)
rtl/cpu/vexriscv_pkg.sv

# VexRiscv core modules (refactored from Verilog)
rtl/cpu/vexriscv_regfile.sv
rtl/cpu/vexriscv_stream_fifo.sv
rtl/cpu/vexriscv_ibus_simple.sv
rtl/cpu/vexriscv_dbus_simple.sv
rtl/cpu/vexriscv_hazard_simple.sv
rtl/cpu/vexriscv_branch.sv
rtl/cpu/vexriscv_csr.sv
rtl/cpu/vexriscv_execute.sv
rtl/cpu/vexriscv_top.sv

# UART integration modules (new implementation)
rtl/cpu/vexriscv_blockram.sv
rtl/cpu/vexriscv_ebreak_monitor.sv
rtl/cpu/vexriscv_mem_crossbar.sv
rtl/cpu/vexriscv_control.sv
rtl/cpu/vexriscv_wrapper.sv

# Note: AXIUART_Top.sv is included separately in main compilation
# Use +define+VEXRISCV_CPU to select VexRiscv instead of rv32i_top
