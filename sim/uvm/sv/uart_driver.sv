
//------------------------------------------------------------------------------
// Simplified UART Driver (UBUS Style)
//------------------------------------------------------------------------------

class uart_driver extends uvm_driver #(uart_transaction);
    
    `uvm_component_utils(uart_driver)
    
    // Virtual interface
    virtual uart_if vif;
    
    // Analysis port to broadcast write commands to scoreboard
    uvm_analysis_port #(uart_transaction) item_sent_port;
    
    // Baud rate timing
    int bit_period_ns = 8680;  // 115200 baud default
    
    function new(string name = "uart_driver", uvm_component parent = null);
        super.new(name, parent);
        item_sent_port = new("item_sent_port", this);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("UART_DRIVER", "Failed to get virtual interface")
        end
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        uart_transaction req;
        
        // Initialize signals
        vif.uart_rx = 1'b1;
        vif.uart_cts_n = 1'b0;
        vif.rst = 1'b0;
        vif.rst_n = 1'b1;
        
        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info("UART_DRIVER", $sformatf("Driving: %s", req.convert2string()), UVM_HIGH)
            
            if (req.is_reset) begin
                handle_reset(req);
            end else begin
                drive_transaction(req);
            end
            
            seq_item_port.item_done();
        end
    endtask
    
    // Handle reset transaction
    virtual task handle_reset(uart_transaction trans);
        `uvm_info("UART_DRIVER", $sformatf("Executing reset: %0d cycles", trans.reset_cycles), UVM_MEDIUM)
        
        // Keep UART RX line HIGH (IDLE state) during reset
        vif.uart_rx = 1'b1;
        vif.rst = 1'b1;
        vif.rst_n = 1'b0;
        repeat(trans.reset_cycles) @(posedge vif.clk);
        vif.rst = 1'b0;
        vif.rst_n = 1'b1;
        // Ensure IDLE state after reset
        vif.uart_rx = 1'b1;
        repeat(10) @(posedge vif.clk);
        
        `uvm_info("UART_DRIVER", "Reset completed", UVM_MEDIUM)
    endtask
    
    // Drive UART frame
    virtual task drive_transaction(uart_transaction trans);
        // Build UART frame per AXIUART protocol spec:
        // SOF (0xA5) + CMD + ADDR (LE) + DATA (LE, write only) + CRC-8
        bit [7:0] frame[];
        bit [7:0] cmd_byte;
        bit [7:0] crc;
        int payload_size;
        
        // Build CMD byte: {RW, INC, SIZE[1:0], LEN[3:0]}
        // RW=0 (write), RW=1 (read)
        // INC=0 (fixed address)
        // SIZE=10 (32-bit access)
        // LEN=0 (1 beat)
        cmd_byte = {trans.is_read, 1'b0, 2'b10, 4'h0};
        
        if (trans.is_read) begin
            // Read: SOF + CMD + ADDR + CRC (no data payload)
            frame = new[7];  // 1 + 1 + 4 + 1
            frame[0] = 8'hA5;  // SOF
            frame[1] = cmd_byte;
            // Address (little-endian)
            frame[2] = trans.address[7:0];
            frame[3] = trans.address[15:8];
            frame[4] = trans.address[23:16];
            frame[5] = trans.address[31:24];
            
            // CRC-8: polynomial 0x07, init 0x00, over CMD + ADDR
            crc = calculate_crc8({cmd_byte, 
                                  trans.address[7:0], trans.address[15:8],
                                  trans.address[23:16], trans.address[31:24]});
            frame[6] = crc;
        end else begin
            // Write: SOF + CMD + ADDR + DATA + CRC
            frame = new[11];  // 1 + 1 + 4 + 4 + 1
            frame[0] = 8'hA5;  // SOF
            frame[1] = cmd_byte;
            // Address (little-endian)
            frame[2] = trans.address[7:0];
            frame[3] = trans.address[15:8];
            frame[4] = trans.address[23:16];
            frame[5] = trans.address[31:24];
            // Data (little-endian)
            frame[6] = trans.data[7:0];
            frame[7] = trans.data[15:8];
            frame[8] = trans.data[23:16];
            frame[9] = trans.data[31:24];
            
            // CRC-8: over CMD + ADDR + DATA
            crc = calculate_crc8({cmd_byte,
                                  trans.address[7:0], trans.address[15:8],
                                  trans.address[23:16], trans.address[31:24],
                                  trans.data[7:0], trans.data[15:8],
                                  trans.data[23:16], trans.data[31:24]});
            frame[10] = crc;
        end
        
        `uvm_info("UART_DRIVER",
            $sformatf("Sending %s frame: CMD=0x%02X ADDR=0x%08X %s CRC=0x%02X",
                      trans.is_read ? "READ" : "WRITE",
                      cmd_byte, trans.address,
                      trans.is_read ? "" : $sformatf("DATA=0x%08X", trans.data),
                      crc),
            UVM_HIGH)
        
        // Broadcast write transaction to scoreboard for tracking
        if (!trans.is_read) begin
            item_sent_port.write(trans);
            `uvm_info("UART_DRIVER",
                $sformatf("Broadcasted WRITE to Scoreboard: ADDR=0x%08X DATA=0x%08X",
                          trans.address, trans.data),
                UVM_MEDIUM)
        end
        
        // Send frame
        foreach (frame[i]) begin
            send_uart_byte(frame[i]);
        end
        
        // Inter-frame gap
        repeat(10) @(posedge vif.clk);
    endtask
    
    // CRC-8 calculation (polynomial 0x07)
    function bit [7:0] calculate_crc8(bit [7:0] data_bytes[]);
        bit [7:0] crc = 8'h00;
        foreach (data_bytes[i]) begin
            crc = crc ^ data_bytes[i];
            for (int j = 0; j < 8; j++) begin
                if (crc[7])
                    crc = (crc << 1) ^ 8'h07;
                else
                    crc = crc << 1;
            end
        end
        return crc;
    endfunction
    
    // Send one UART byte (8N1 format)
    virtual task send_uart_byte(bit [7:0] data);
        // Start bit
        vif.uart_rx = 1'b0;
        #bit_period_ns;
        
        // Data bits (LSB first)
        for (int i = 0; i < 8; i++) begin
            vif.uart_rx = data[i];
            #bit_period_ns;
        end
        
        // Stop bit
        vif.uart_rx = 1'b1;
        #bit_period_ns;
        
        // Inter-byte idle (minimum 1-bit period for clean framing)
        // Keep line high (IDLE state) before next byte
        #bit_period_ns;
    endtask

endclass
