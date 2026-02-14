# DSIM file list for UART Bridge unit tests (Issue #54)

+incdir+../../../rtl/uart_axi4_bridge
+incdir+../../tests

# RTL under test
../../../rtl/uart_axi4_bridge/Crc8_Calculator.sv
../../../rtl/uart_axi4_bridge/Frame_Parser.sv
../../../rtl/uart_axi4_bridge/fifo_sync.sv
../../../rtl/uart_axi4_bridge/Uart_Rx.sv
../../../rtl/uart_axi4_bridge/Uart_Tx.sv

# Unit testbenches
../../tests/uart_unit_crc8_tb.sv
../../tests/uart_unit_frame_parser_tb.sv
../../tests/uart_unit_fifo_sync_tb.sv
../../tests/uart_unit_uart_rx_tb.sv
../../tests/uart_unit_uart_tx_tb.sv
