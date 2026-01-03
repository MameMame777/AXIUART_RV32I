
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
    
    // CPU Memory Debug tracking (32-bit words, 11-bit word address)
    bit [31:0] cpu_memory_shadow[bit [10:0]];  // Shadow memory: 2048 words × 32-bit
    bit [10:0] pending_cpu_mem_addr;            // Current CPU_MEM_ADDR value (word address)
    bit [10:0] cpu_mem_read_queue[$];          // Queue of word addresses for pending reads
    int cpu_memory_match_count;
    int cpu_memory_mismatch_count;
    int cpu_memory_write_count;
    int cpu_memory_read_count;
    
    // Statistics
    int match_count;
    int mismatch_count;
    int write_count;
    int read_count;
    
    // Non-verifiable register addresses (read-only or dynamic)
    local bit [31:0] exclude_verify_addrs[$];
    
    function new(string name = "axiuart_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        match_count = 0;
        mismatch_count = 0;
        write_count = 0;
        read_count = 0;
        cpu_memory_match_count = 0;
        cpu_memory_mismatch_count = 0;
        cpu_memory_write_count = 0;
        cpu_memory_read_count = 0;
        pending_cpu_mem_addr = 16'h0000;
        
        // Initialize exclude list for registers that shouldn't be verified against shadow
        // Read-only registers
        exclude_verify_addrs.push_back(axiuart_reg_pkg::REG_VERSION);         // Read-only: hardware version
        exclude_verify_addrs.push_back(axiuart_reg_pkg::REG_TX_COUNT);        // Read-only: TX counter
        exclude_verify_addrs.push_back(axiuart_reg_pkg::REG_RX_COUNT);        // Read-only: RX counter
        exclude_verify_addrs.push_back(axiuart_reg_pkg::REG_FIFO_STAT);       // Read-only: FIFO status
        exclude_verify_addrs.push_back(axiuart_reg_pkg::REG_REVISION);        // Read-only: revision
        exclude_verify_addrs.push_back(axiuart_reg_pkg::REG_CPU_MEM_RDATA);   // Read-only: CPU memory read data
        
        // Dynamic registers (RV32I CPU status/control)
        exclude_verify_addrs.push_back(axiuart_reg_pkg::REG_CPU_MEM_CTRL);    // Dynamic: CPU control/status bits
    endfunction
    
    // Helper function: Check if address should be excluded from verification
    local function bit is_excluded_addr(bit [31:0] addr);
        foreach (exclude_verify_addrs[i]) begin
            if (exclude_verify_addrs[i] == addr) return 1'b1;
        end
        return 1'b0;
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
        // Track CPU memory debug operations
        if (trans.address == axiuart_reg_pkg::REG_CPU_MEM_ADDR) begin
            pending_cpu_mem_addr = trans.data[10:0];  // Extract 11-bit word address
            `uvm_info("SCOREBOARD", 
                $sformatf("CPU_MEM_ADDR set: 0x%03X (word address)", pending_cpu_mem_addr), 
                UVM_HIGH)
        end else if (trans.address == axiuart_reg_pkg::REG_CPU_MEM_WDATA) begin
            cpu_memory_shadow[pending_cpu_mem_addr] = trans.data;  // Full 32-bit data
            cpu_memory_write_count++;
            `uvm_info("SCOREBOARD", 
                $sformatf("CPU_MEM write: ADDR=0x%03X DATA=0x%08X (total: %0d)", 
                          pending_cpu_mem_addr, trans.data, cpu_memory_write_count), 
                UVM_MEDIUM)
        end else if (trans.address == axiuart_reg_pkg::REG_CPU_MEM_CTRL) begin
            // If read request (bit 4), enqueue current address for future verification
            if (trans.data[4] == 1'b1) begin
                cpu_mem_read_queue.push_back(pending_cpu_mem_addr);
                `uvm_info("SCOREBOARD", 
                    $sformatf("CPU_MEM read request queued: ADDR=0x%03X (queue size: %0d)", 
                              pending_cpu_mem_addr, cpu_mem_read_queue.size()), 
                    UVM_HIGH)
            end
        end
        
        // Normal register write tracking
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
        
        // Special handling for CPU_MEM_RDATA (32-bit register)
        if (trans.address == axiuart_reg_pkg::REG_CPU_MEM_RDATA) begin
            bit [31:0] expected_mem_data;
            bit [31:0] actual_mem_data;
            bit [10:0] read_addr;  // 11-bit word address (0x000-0x7FF)
            
            cpu_memory_read_count++;
            actual_mem_data = trans.read_response_data;  // Full 32-bit value
            
            // Pop address from queue for this read response
            if (cpu_mem_read_queue.size() == 0) begin
                `uvm_error("SCOREBOARD", 
                    $sformatf("CPU_MEM_RDATA response with empty read queue! DATA=0x%08X", actual_mem_data))
                return;
            end
            
            read_addr = cpu_mem_read_queue.pop_front();
            
            if (cpu_memory_shadow.exists(read_addr)) begin
                expected_mem_data = cpu_memory_shadow[read_addr];
                
                if (actual_mem_data == expected_mem_data) begin
                    cpu_memory_match_count++;
                    `uvm_info("SCOREBOARD", 
                        $sformatf("CPU_MEM READ MATCH: ADDR=0x%03X Expected=0x%08X Got=0x%08X", 
                                  read_addr, expected_mem_data, actual_mem_data), 
                        UVM_MEDIUM)
                end else begin
                    cpu_memory_mismatch_count++;
                    `uvm_error("SCOREBOARD", 
                        $sformatf("CPU_MEM READ MISMATCH: ADDR=0x%03X Expected=0x%08X Got=0x%08X",
                                  read_addr, expected_mem_data, actual_mem_data))
                end
            end else begin
                `uvm_warning("SCOREBOARD", 
                    $sformatf("CPU_MEM read from unwritten address: ADDR=0x%03X DATA=0x%08X",
                              read_addr, actual_mem_data))
            end
            return;  // Skip normal register verification for CPU_MEM_RDATA
        end
        
        // Exclude read-only and dynamic registers from verification
        if (is_excluded_addr(trans.address)) begin
            `uvm_info("SCOREBOARD", 
                $sformatf("Read from excluded register (no verification): ADDR=0x%08X DATA=0x%08X",
                          trans.address, trans.read_response_data), 
                UVM_HIGH)
            return;
        end
        
        // Normal register read verification
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
        
        if (cpu_memory_write_count > 0 || cpu_memory_read_count > 0) begin
            `uvm_info("SCOREBOARD", "=== CPU Memory Debug Verification Results ===", UVM_LOW)
            `uvm_info("SCOREBOARD", $sformatf("CPU Memory Writes: %0d", cpu_memory_write_count), UVM_LOW)
            `uvm_info("SCOREBOARD", $sformatf("CPU Memory Reads:  %0d", cpu_memory_read_count), UVM_LOW)
            `uvm_info("SCOREBOARD", $sformatf("CPU MEM MATCHES:   %0d", cpu_memory_match_count), UVM_LOW)
            `uvm_info("SCOREBOARD", $sformatf("CPU MEM MISMATCHES: %0d", cpu_memory_mismatch_count), UVM_LOW)
        end
        
        if (mismatch_count == 0 && cpu_memory_mismatch_count == 0) begin
            if (match_count > 0 || cpu_memory_match_count > 0) begin
                `uvm_info("SCOREBOARD", "*** TEST PASSED ***", UVM_LOW)
            end else if (read_count == 0 && cpu_memory_read_count == 0) begin
                `uvm_warning("SCOREBOARD", "*** NO READ RESPONSES VERIFIED ***")
            end
        end else begin
            `uvm_error("SCOREBOARD", "*** TEST FAILED ***")
        end
    endfunction
    
endclass
