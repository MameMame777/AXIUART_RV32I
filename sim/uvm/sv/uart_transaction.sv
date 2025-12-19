
//------------------------------------------------------------------------------
// Simplified UART Transaction (UBUS Style)
//------------------------------------------------------------------------------

class uart_transaction extends uvm_sequence_item;
    
    // Basic transaction fields
    rand bit [31:0] address;
    rand bit [31:0] data;
    rand bit is_read;
    
    // Frame data for UART protocol
    rand bit [7:0] frame_data[];
    
    // Response handling (for read operations)
    bit is_response = 0;           // Flag indicating this is a DUT response
    bit [31:0] read_response_data; // Data extracted from DUT response frame
    bit response_valid = 0;        // Flag indicating response_data is valid
    
    // Reset control
    bit is_reset = 0;
    int reset_cycles = 100;
    
    // Constraints
    constraint valid_address_c {
        address[1:0] == 2'b00;  // 4-byte aligned
    }
    
    constraint frame_size_c {
        frame_data.size() inside {[1:256]};
    }
    
    // UVM registration
    `uvm_object_utils_begin(uart_transaction)
        `uvm_field_int(address, UVM_ALL_ON)
        `uvm_field_int(data, UVM_ALL_ON)
        `uvm_field_int(is_read, UVM_ALL_ON)
        `uvm_field_array_int(frame_data, UVM_ALL_ON)
        `uvm_field_int(is_response, UVM_ALL_ON)
        `uvm_field_int(read_response_data, UVM_ALL_ON)
        `uvm_field_int(response_valid, UVM_ALL_ON)
    `uvm_object_utils_end
    
    function new(string name = "uart_transaction");
        super.new(name);
    endfunction
    
    // Utility functions
    function string convert2string();
        string s;
        if (is_response) begin
            s = $sformatf("RESPONSE: ADDR=0x%08h DATA=0x%08h VALID=%0b",
                          address, read_response_data, response_valid);
        end else begin
            s = $sformatf("Transaction: %s ADDR=0x%08h DATA=0x%08h FRAME_SIZE=%0d",
                          is_read ? "READ" : "WRITE", address, data, frame_data.size());
        end
        return s;
    endfunction
    
endclass
