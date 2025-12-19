
//------------------------------------------------------------------------------
// Simplified UART Monitor (UBUS Style)
//------------------------------------------------------------------------------

class uart_monitor extends uvm_monitor;
    
    `uvm_component_utils(uart_monitor)
    
    // Virtual interface
    virtual uart_if vif;
    
    // Analysis port
    uvm_analysis_port #(uart_transaction) item_collected_port;
    
    function new(string name = "uart_monitor", uvm_component parent = null);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("UART_MONITOR", "Failed to get virtual interface")
        end
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        uart_transaction trans;
        
        forever begin
            // Wait for UART activity and collect transaction
            trans = uart_transaction::type_id::create("trans");
            collect_transaction(trans);
            
            // Broadcast all valid responses to scoreboard
            // (collect_transaction only returns when valid SOF detected)
            item_collected_port.write(trans);
            `uvm_info("UART_MONITOR", 
                $sformatf("Broadcasting transaction to scoreboard: is_response=%0d response_valid=%0d",
                          trans.is_response, trans.response_valid), 
                UVM_HIGH)
        end
    endtask
    
    // Simple frame collection per AXIUART protocol spec
    virtual task collect_transaction(uart_transaction trans);
        bit [7:0] sof, status_byte, cmd_echo;
        bit [7:0] addr_bytes[4];
        bit [7:0] data_bytes[4];
        bit [7:0] crc_byte;
        bit is_read_response;
        
        // Wait for SOF (0x5A = Device→Host)
        do begin
            wait_for_byte(sof);
        end while (sof != 8'h5A);
        
        // Read STATUS byte
        wait_for_byte(status_byte);
        
        // Read CMD echo
        wait_for_byte(cmd_echo);
        
        // Decode CMD byte to determine if read response
        is_read_response = cmd_echo[7];  // RW bit
        
        if (is_read_response && status_byte == 8'h00) begin
            // Read response with data: STATUS + CMD + ADDR(4) + DATA(4) + CRC
            foreach (addr_bytes[i]) wait_for_byte(addr_bytes[i]);
            foreach (data_bytes[i]) wait_for_byte(data_bytes[i]);
            wait_for_byte(crc_byte);
            
            // Reconstruct address and data (little-endian)
            trans.address = {addr_bytes[3], addr_bytes[2], addr_bytes[1], addr_bytes[0]};
            trans.read_response_data = {data_bytes[3], data_bytes[2], data_bytes[1], data_bytes[0]};
            trans.is_response = 1;
            trans.response_valid = 1;
            
            `uvm_info("UART_MONITOR",
                $sformatf("READ_RESP: STATUS=0x%02X ADDR=0x%08X DATA=0x%08X CRC=0x%02X",
                          status_byte, trans.address, trans.read_response_data, crc_byte),
                UVM_MEDIUM)
            
        end else if (!is_read_response) begin
            // Write ACK: STATUS + CMD + CRC (no address/data)
            wait_for_byte(crc_byte);
            
            trans.is_response = 1;  // WRITE_ACK is a response from DUT
            trans.response_valid = 0;  // Not a read response (no data payload)
            
            `uvm_info("UART_MONITOR",
                $sformatf("WRITE_ACK: STATUS=0x%02X CMD=0x%02X CRC=0x%02X",
                          status_byte, cmd_echo, crc_byte),
                UVM_MEDIUM)
                
        end else begin
            // Read response with error: STATUS + CMD + CRC (no addr/data)
            wait_for_byte(crc_byte);
            
            trans.is_response = 1;
            trans.response_valid = 0;  // Error response
            
            `uvm_info("UART_MONITOR",
                $sformatf("READ_ERROR: STATUS=0x%02X CMD=0x%02X CRC=0x%02X",
                          status_byte, cmd_echo, crc_byte),
                UVM_MEDIUM)
        end
    endtask
    
    // Sample one UART byte directly from uart_tx pin
    // UART format: Start bit (0), 8 data bits (LSB first), Stop bit (1)
    virtual task wait_for_byte(output bit [7:0] data);
        // 115200 baud: bit period = 1/115200 = 8.68 μs = 8680 ns
        // 125MHz clock: 1 clock = 8 ns
        // Clocks per bit = 8680 ns / 8 ns = 1085 clocks
        int clocks_per_bit = 1085;
        
        // Wait for start bit (1→0 transition on uart_tx)
        wait (vif.uart_tx == 1'b1);
        wait (vif.uart_tx == 1'b0);
        
        // Move to center of start bit for stable sampling
        repeat(clocks_per_bit / 2) @(posedge vif.clk);
        
        // Sample 8 data bits (LSB first) at bit centers
        for (int i = 0; i < 8; i++) begin
            repeat(clocks_per_bit) @(posedge vif.clk);
            data[i] = vif.uart_tx;
        end
        
        // Move to center of stop bit for verification
        repeat(clocks_per_bit) @(posedge vif.clk);
        if (vif.uart_tx != 1'b1) begin
            `uvm_error("UART_MONITOR", 
                $sformatf("Framing error: stop bit=%b (expected 1)", vif.uart_tx))
        end
        
        // Wait for remaining half of stop bit to complete frame
        repeat(clocks_per_bit / 2) @(posedge vif.clk);
        
        `uvm_info("UART_MONITOR", $sformatf("Received byte: 0x%02X", data), UVM_DEBUG)
    endtask
    
endclass
