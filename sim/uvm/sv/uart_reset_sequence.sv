//------------------------------------------------------------------------------
// UART Reset Sequence
// Purpose: Dedicated reset sequence for DUT initialization
// Reusability: Can be called from any test or virtual sequence
//------------------------------------------------------------------------------

class uart_reset_sequence extends uvm_sequence#(uart_transaction);
    `uvm_object_utils(uart_reset_sequence)
    
    // Configurable reset duration (default: 100 cycles)
    rand int reset_cycles;
    
    constraint reset_cycles_range {
        reset_cycles inside {[10:1000]};
    }
    
    function new(string name = "uart_reset_sequence");
        super.new(name);
        reset_cycles = 100; // Default value
    endfunction
    
    task body();
        uart_transaction tx;
        
        `uvm_info(get_type_name(), 
            $sformatf("Executing reset sequence: %0d cycles", reset_cycles), UVM_MEDIUM)
        
        tx = uart_transaction::type_id::create("tx");
        start_item(tx);
        tx.is_reset = 1;
        tx.reset_cycles = this.reset_cycles;
        finish_item(tx);
        
        `uvm_info(get_type_name(), "Reset sequence completed", UVM_MEDIUM)
    endtask
endclass
