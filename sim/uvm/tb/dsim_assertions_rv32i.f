# RV32I Assertion modules configuration file
# This file is ONLY included when assertions are enabled for RV32I tests
# Usage: dsim ... -f dsim_assertions_rv32i.f (when +define+ENABLE_ASSERTIONS is set)

# RV32I Debug assertion modules
../../../sim/assertions/rv32i_mmio_led_spec.sv
../../../sim/assertions/rv32i_ebreak_spec.sv
../../../sim/assertions/rv32i_ebreak_debug_spec.sv
../../../sim/assertions/rv32i_data_hazard_spec.sv
../../../sim/assertions/bind_rv32i_debug_spec.sv
../../../sim/assertions/bind_rv32i_ebreak_debug_spec.sv
