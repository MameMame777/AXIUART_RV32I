# Minimal DSIM config for syntax check
+define+DEFINE_SIM

+incdir+../../../rtl
+incdir+../../../rtl/interfaces

../../../rtl/interfaces/uart_if.sv
../../../rtl/fifo_sync.sv
../../../rtl/Uart_Rx.sv

+incdir+../sv
../sv/uart_transaction.sv
