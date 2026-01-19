# VexRiscv test file list
+define+DEFINE_SIM

# Package must be compiled first
rtl/cpu/vexriscv_pkg.sv

# Core modules (in dependency order)
rtl/cpu/vexriscv_regfile.sv
rtl/cpu/vexriscv_stream_fifo.sv
rtl/cpu/vexriscv_ibus_simple.sv
rtl/cpu/vexriscv_dbus_simple.sv
rtl/cpu/vexriscv_hazard_simple.sv
rtl/cpu/vexriscv_branch.sv
rtl/cpu/vexriscv_csr.sv
rtl/cpu/vexriscv_execute.sv

# Top-level integration
rtl/cpu/vexriscv_top.sv

# Test module
rtl/cpu/vexriscv_regfile_test.sv
