
//------------------------------------------------------------------------------
// Basic UART Sequence
//------------------------------------------------------------------------------

class uart_basic_sequence extends uvm_sequence#(uart_transaction);
    `uvm_object_utils(uart_basic_sequence)
    
    function new(string name = "uart_basic_sequence");
        super.new(name);
    endfunction
    
    task body();
        uart_transaction tx;
        
        `uvm_info(get_type_name(), "Starting UART basic sequence", UVM_MEDIUM)
        
        repeat(5) begin
            tx = uart_transaction::type_id::create("tx");
            start_item(tx);
            assert(tx.randomize());
            finish_item(tx);
        end
        
        `uvm_info(get_type_name(), "UART basic sequence completed", UVM_MEDIUM)
    endtask
endclass
