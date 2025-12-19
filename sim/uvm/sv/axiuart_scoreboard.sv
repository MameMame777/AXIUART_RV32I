
//------------------------------------------------------------------------------
// Simplified AXIUART Scoreboard (UBUS Style)
//------------------------------------------------------------------------------

class axiuart_scoreboard extends uvm_scoreboard;
    
    `uvm_component_utils(axiuart_scoreboard)
    
    // Analysis exports
    uvm_analysis_export #(uart_transaction) uart_export;
    uvm_analysis_export #(uart_transaction) axi_export;
    
    // FIFOs
    uvm_tlm_analysis_fifo #(uart_transaction) uart_fifo;
    uvm_tlm_analysis_fifo #(uart_transaction) axi_fifo;
    
    // Register write tracking: address -> expected data
    bit [31:0] write_shadow_regs[bit [31:0]];
    
    // Statistics
    int match_count;
    int mismatch_count;
    int write_count;
    int read_count;
    
    function new(string name = "axiuart_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        match_count = 0;
        mismatch_count = 0;
        write_count = 0;
        read_count = 0;
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        uart_export = new("uart_export", this);
        axi_export = new("axi_export", this);
        
        uart_fifo = new("uart_fifo", this);
        axi_fifo = new("axi_fifo", this);
    endfunction
    
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        uart_export.connect(uart_fifo.analysis_export);
        axi_export.connect(axi_fifo.analysis_export);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        fork
            // Process UART Monitor responses (DUT output)
            begin
                uart_transaction uart_trans;
                forever begin
                    uart_fifo.get(uart_trans);
                    process_uart_transaction(uart_trans);
                end
            end
            
            // Process Driver write commands (host input tracking)
            begin
                uart_transaction axi_trans;
                forever begin
                    axi_fifo.get(axi_trans);
                    track_write_transaction(axi_trans);
                end
            end
        join
    endtask
    
    // Process UART transactions: track writes, verify reads
    virtual function void process_uart_transaction(uart_transaction trans);
        if (trans.is_response && trans.response_valid) begin
            // This is a read response from DUT
            verify_read_response(trans);
        end else if (!trans.is_read && !trans.is_reset && !trans.is_response) begin
            // This is a write transaction (exclude WRITE_ACK which has is_response=1)
            track_write_transaction(trans);
        end
    endfunction
    
    // Track write transactions in shadow register
    virtual function void track_write_transaction(uart_transaction trans);
        write_shadow_regs[trans.address] = trans.data;
        write_count++;
        `uvm_info("SCOREBOARD", 
            $sformatf("Write tracked: ADDR=0x%08X DATA=0x%08X (total: %0d)", trans.address, trans.data, write_count), 
            UVM_MEDIUM)
    endfunction
    
    // Verify read response against shadow register
    virtual function void verify_read_response(uart_transaction trans);
        bit [31:0] expected_data;
        
        read_count++;
        
        if (write_shadow_regs.exists(trans.address)) begin
            expected_data = write_shadow_regs[trans.address];
            
            if (trans.read_response_data == expected_data) begin
                match_count++;
                `uvm_info("SCOREBOARD", 
                    $sformatf("READ MATCH: ADDR=0x%08X Expected=0x%08X Got=0x%08X", 
                              trans.address, expected_data, trans.read_response_data), 
                    UVM_MEDIUM)
            end else begin
                mismatch_count++;
                `uvm_error("SCOREBOARD", 
                    $sformatf("READ MISMATCH: ADDR=0x%08X Expected=0x%08X Got=0x%08X",
                              trans.address, expected_data, trans.read_response_data))
            end
        end else begin
            `uvm_warning("SCOREBOARD", 
                $sformatf("Read from unwritten address: ADDR=0x%08X DATA=0x%08X",
                          trans.address, trans.read_response_data))
        end
    endfunction
    
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        `uvm_info("SCOREBOARD", "=== Final Register R/W Verification Results ===", UVM_LOW)
        `uvm_info("SCOREBOARD", $sformatf("Total Writes: %0d", write_count), UVM_LOW)
        `uvm_info("SCOREBOARD", $sformatf("Total Reads:  %0d", read_count), UVM_LOW)
        `uvm_info("SCOREBOARD", $sformatf("MATCHES:      %0d", match_count), UVM_LOW)
        `uvm_info("SCOREBOARD", $sformatf("MISMATCHES:   %0d", mismatch_count), UVM_LOW)
        
        if (mismatch_count == 0 && read_count > 0) begin
            `uvm_info("SCOREBOARD", "*** TEST PASSED ***", UVM_LOW)
        end else if (read_count == 0) begin
            `uvm_warning("SCOREBOARD", "*** NO READ RESPONSES VERIFIED ***")
        end else begin
            `uvm_error("SCOREBOARD", "*** TEST FAILED ***")
        end
    endfunction
    
endclass
