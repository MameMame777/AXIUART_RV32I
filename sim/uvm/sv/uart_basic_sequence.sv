
//------------------------------------------------------------------------------
// Basic UART Sequence
//------------------------------------------------------------------------------

import axiuart_reg_pkg::*;

class uart_basic_sequence extends uvm_sequence#(uart_transaction);
    `uvm_object_utils(uart_basic_sequence)
    
    function new(string name = "uart_basic_sequence");
        super.new(name);
    endfunction
    
    task body();
        uart_transaction tx, rsp;
        
        `uvm_info(get_type_name(), "Starting UART basic sequence", UVM_MEDIUM)
        
        repeat(5) begin
            tx = uart_transaction::type_id::create("tx");
            start_item(tx);
            assert(tx.randomize() with {
                address inside {REG_TEST_0, REG_TEST_1, REG_TEST_2, REG_TEST_3, 
                               REG_TEST_4, REG_TEST_LED, REG_STATUS, REG_VERSION};
            });
            finish_item(tx);
            
            // If read transaction, retrieve response
            if (tx.is_read) begin
                get_response(rsp);
                `uvm_info(get_type_name(), 
                    $sformatf("Read response: ADDR=0x%08h DATA=0x%08h", 
                              rsp.address, rsp.read_response_data), UVM_MEDIUM)
            end
        end
        
        `uvm_info(get_type_name(), "UART basic sequence completed", UVM_MEDIUM)
    endtask
endclass
