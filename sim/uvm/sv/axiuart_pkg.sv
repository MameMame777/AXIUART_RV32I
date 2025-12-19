
//------------------------------------------------------------------------------
// AXIUART UVM Package (Simplified - UBUS Style)
//------------------------------------------------------------------------------

package axiuart_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    typedef uvm_config_db#(virtual uart_if) uart_vif_config;
    typedef uvm_config_db#(virtual axi4_lite_if) axi_vif_config;
    typedef virtual uart_if uart_vif;
    typedef virtual axi4_lite_if axi_vif;

    // Transaction types
    `include "uart_transaction.sv"
    
    // UART Agent components
    `include "uart_monitor.sv"
    `include "uart_sequencer.sv"
    `include "uart_driver.sv"
    `include "uart_agent.sv"
    
    // Basic sequences (needed for tests)
    `include "uart_basic_sequence.sv"
    
    // AXI Agent components (monitor only for internal observation)
    `include "axi4_lite_monitor.sv"
    
    // Reset sequence
    `include "uart_reset_sequence.sv"
    
    // Register access sequences
    `include "uart_reg_sequences.sv"
    
    // Scoreboard
    `include "axiuart_scoreboard.sv"
    
    // Environment
    `include "axiuart_env.sv"

endpackage: axiuart_pkg
