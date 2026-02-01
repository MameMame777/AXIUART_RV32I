# Assertion modules configuration file
# This file is ONLY included when assertions are enabled
# Usage: dsim ... -f dsim_assertions.f (when +define+ENABLE_ASSERTIONS is set)

# Debug assertion modules
../../assertions/td4cpu_br_timing_assertions.sv
../../assertions/td4cpu_address_debug.sv
../../assertions/td4cpu_debug_read_monitor.sv
../../assertions/td4cpu_ram_read_investigation.sv
../../assertions/td4cpu_ram_rd_en_timing.sv
../../assertions/td4cpu_debug_mem_spec.sv
../../assertions/td4cpu_flag_hazard_assertions.sv
../../assertions/td4cpu_fetch_spec.sv
../../assertions/spec/td4cpu_branch_fetch_assertions.sv
../../assertions/spec/vexriscv_ibus_rsp_pc_spec.sv
../../assertions/vexriscv_ibus_pc_fifo_assertions.sv
../../assertions/spec/vexriscv_mem_crossbar_fifo_spec.sv
../../assertions/bind_debug_spec.sv
../../assertions/bind/bind_vexriscv_ibus_rsp_pc_spec.sv
../../assertions/bind/bind_vexriscv_ibus_pc_fifo_assertions.sv
../../assertions/bind/bind_vexriscv_mem_crossbar_fifo_spec.sv

