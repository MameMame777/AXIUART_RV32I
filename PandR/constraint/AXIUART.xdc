# USB-UART-AXI4 Bridge Constraint File for Vivado
# Target Board: Zybo Z7-20
# Date: September 23, 2025
# Description: Production constraint file aligned with AXIUART_Top.sv RTL implementation
# Reference: RTL signals in AXIUART_Top.sv

###################################################################################
# Clock Constraints
###################################################################################

# System Clock - 125MHz input (matching RTL CLK_FREQ_HZ parameter)
# Zybo Z7-20 provides 125MHz system clock, period = 8.000ns
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 8.000 -name sys_clk_pin -waveform {0.000 4.000} -add [get_ports clk]

###################################################################################
# Reset Constraints
###################################################################################

# External reset input (active high, synchronous)
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports rst]

###################################################################################
# UART Interface - JB Connector (Pmod USBUART)
###################################################################################
# PMOD UART 4-pin interface with hardware flow control
# Standard PMOD UART pinout (FPGA perspective):
# Pin1 (JB1): RTS_N - Request to Send (FPGA output, active low)
# Pin2 (JB2): RX - Receive Data (FPGA input from external device)
# Pin3 (JB3): TX - Transmit Data (FPGA output to external device)
# Pin4 (JB4): CTS_N - Clear to Send (FPGA input, active low)
##Pmod Header JB (Zybo Z7-20 only)


##Pmod Header JB (Zybo Z7-20 only)
#set_property -dict { PACKAGE_PIN V8    IOSTANDARD LVCMOS33     } [get_ports { jb[0] }]; #IO_L15P_T2_DQS_13 Sch=jb_p[1]
#set_property -dict { PACKAGE_PIN W8    IOSTANDARD LVCMOS33     } [get_ports { jb[1] }]; #IO_L15N_T2_DQS_13 Sch=jb_n[1]
#set_property -dict { PACKAGE_PIN U7    IOSTANDARD LVCMOS33     } [get_ports { jb[2] }]; #IO_L11P_T1_SRCC_13 Sch=jb_p[2]
#set_property -dict { PACKAGE_PIN V7    IOSTANDARD LVCMOS33     } [get_ports { jb[3] }]; #IO_L11N_T1_SRCC_13 Sch=jb_n[2]
#set_property -dict { PACKAGE_PIN Y7    IOSTANDARD LVCMOS33     } [get_ports { jb[4] }]; #IO_L13P_T2_MRCC_13 Sch=jb_p[3]
#set_property -dict { PACKAGE_PIN Y6    IOSTANDARD LVCMOS33     } [get_ports { jb[5] }]; #IO_L13N_T2_MRCC_13 Sch=jb_n[3]
#set_property -dict { PACKAGE_PIN V6    IOSTANDARD LVCMOS33     } [get_ports { jb[6] }]; #IO_L22P_T3_13 Sch=jb_p[4]
#set_property -dict { PACKAGE_PIN W6    IOSTANDARD LVCMOS33     } [get_ports { jb[7] }]; #IO_L22N_T3_13 Sch=jb_n[4]

# RTS_N - Request to Send (FPGA output, active low)
set_property -dict {PACKAGE_PIN V8 IOSTANDARD LVCMOS33} [get_ports uart_cts_n]
# UART_RX - Receive Data (FPGA input from external device)
set_property -dict {PACKAGE_PIN W8 IOSTANDARD LVCMOS33} [get_ports uart_tx]
# UART_TX - Transmit Data (FPGA output to external device)
set_property -dict {PACKAGE_PIN U7 IOSTANDARD LVCMOS33} [get_ports uart_rx]
# CTS_N - Clear to Send (FPGA input, active low)
set_property -dict {PACKAGE_PIN V7 IOSTANDARD LVCMOS33} [get_ports uart_rts_n]

###################################################################################
# System Status Outputs - LED indicators for debugging/monitoring
###################################################################################

# LED - System Heartbeat indicator
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led[0] }]; #IO_L23P_T3_35 Sch=led[0]
set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports { led[1] }]; #IO_L23N_T3_35 Sch=led[1]
set_property -dict { PACKAGE_PIN G14   IOSTANDARD LVCMOS33 } [get_ports { led[2] }]; #IO_0_35 Sch=led[2]
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { led[3] }]; #IO_L3N_T0_DQS_AD1N_35 Sch=led[3]

###################################################################################
# Timing Constraints
###################################################################################

# UART Interface Timing Constraints
# UART signals are asynchronous but need proper timing relationship with system clock
set_input_delay -clock [get_clocks sys_clk_pin] -min 1.000 [get_ports {uart_rx uart_cts_n}]
set_input_delay -clock [get_clocks sys_clk_pin] -max 3.000 [get_ports {uart_rx uart_cts_n}]

set_output_delay -clock [get_clocks sys_clk_pin] -min 1.000 [get_ports {uart_tx uart_rts_n}]
set_output_delay -clock [get_clocks sys_clk_pin] -max 3.000 [get_ports {uart_tx uart_rts_n}]

# False path constraints for asynchronous UART signals
# UART RX/CTS are asynchronous and handled by synchronizers in RTL
set_false_path -from [get_ports {uart_rx uart_cts_n}] -to [get_clocks sys_clk_pin]
set_false_path -from [get_clocks sys_clk_pin] -to [get_ports {uart_tx uart_rts_n}]
# Reset signal is external and asynchronous
set_false_path -from [get_ports rst] -to [all_clocks]

# Optional: False paths for status output LEDs if implemented
set_false_path -to [get_ports {led[*]}]

###################################################################################
# Physical Constraints
###################################################################################

# Set slew rate and drive strength for UART output signals
# Slower slew rate reduces EMI for UART communication
set_property SLEW SLOW [get_ports uart_tx]
set_property SLEW SLOW [get_ports uart_rts_n]
set_property DRIVE 8 [get_ports uart_tx]
set_property DRIVE 8 [get_ports uart_rts_n]

# Optional: LED output characteristics if status LEDs are implemented
# set_property SLEW SLOW [get_ports {system_ready system_busy system_error}]
# set_property DRIVE 8 [get_ports {system_ready system_busy system_error}]

###################################################################################
# Configuration Constraints
###################################################################################

# Bitstream configuration settings for Zynq-7000 series
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]


###################################################################################
# Additional Timing Constraints for Performance
###################################################################################

# Internal clock domain constraints if needed for AXI interfaces
# Note: All internal logic operates on single clock domain in this design

# Maximum delay constraints for critical paths (if timing issues occur)
# set_max_delay -from [get_pins {uart_bridge_inst/state_reg[*]/C}] -to [get_pins {uart_bridge_inst/axi_*}] 10.0

# Multicycle path constraints for UART bit timing logic
# UART operates much slower than system clock, allow multiple cycles for timing closure


###################################################################################
# Implementation Directives (Optional)
###################################################################################

# Placement constraints for better timing closure
# set_property LOC SLICE_X50Y50 [get_cells {uart_bridge_inst/state_reg[*]}]

# Clock buffer placement (if manual control needed)
# set_property LOC BUFGCTRL_X0Y0 [get_cells {clk_IBUF_BUFG_inst}]


