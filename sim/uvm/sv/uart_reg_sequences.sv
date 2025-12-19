//------------------------------------------------------------------------------
// Register Access Sequences for AXIUART
// Purpose: Dedicated sequences for register read/write operations
//------------------------------------------------------------------------------

import axiuart_reg_pkg::*;

class uart_reg_write_sequence extends uvm_sequence#(uart_transaction);
    `uvm_object_utils(uart_reg_write_sequence)
    
    rand bit [31:0] reg_addr;
    rand bit [31:0] reg_data;
    
    constraint valid_addr {
        reg_addr[1:0] == 2'b00;  // 4-byte aligned
        reg_addr inside {[BASE_ADDR:BASE_ADDR + 32'h0100]};  // Register map range
    }
    
    function new(string name = "uart_reg_write_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        uart_transaction tx;
        
        `uvm_info("REG_WR_SEQ", 
            $sformatf("Writing addr=0x%08X data=0x%08X", reg_addr, reg_data), 
            UVM_MEDIUM)
        
        tx = uart_transaction::type_id::create("tx");
        start_item(tx);
        tx.address = reg_addr;
        tx.data = reg_data;
        tx.is_read = 0;
        tx.is_reset = 0;
        // frame_data remains empty - Driver will auto-convert
        finish_item(tx);
        
        `uvm_info("REG_WR_SEQ", "Write transaction completed", UVM_HIGH)
    endtask
endclass

class uart_reg_read_sequence extends uvm_sequence#(uart_transaction);
    `uvm_object_utils(uart_reg_read_sequence)
    
    rand bit [31:0] reg_addr;
    bit [31:0] read_data;  // Store read result
    
    constraint valid_addr {
        reg_addr[1:0] == 2'b00;  // 4-byte aligned
        reg_addr inside {[BASE_ADDR:BASE_ADDR + 32'h0100]};  // Register map range
    }
    
    function new(string name = "uart_reg_read_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        uart_transaction tx;
        
        `uvm_info("REG_RD_SEQ", 
            $sformatf("Reading from addr=0x%08X", reg_addr), 
            UVM_MEDIUM)
        
        tx = uart_transaction::type_id::create("tx");
        start_item(tx);
        tx.address = reg_addr;
        tx.is_read = 1;
        tx.is_reset = 0;
        // frame_data remains empty - Driver will auto-convert
        finish_item(tx);
        
        // Note: Read response handling would require monitor feedback
        `uvm_info("REG_RD_SEQ", "Read transaction sent", UVM_HIGH)
    endtask
endclass
