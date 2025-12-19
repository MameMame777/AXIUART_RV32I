
//------------------------------------------------------------------------------
// Simplified UART Agent (UBUS Style)
//------------------------------------------------------------------------------

class uart_agent extends uvm_agent;
    
    `uvm_component_utils(uart_agent)
    
    // Components
    uart_driver driver;
    uart_monitor monitor;
    uart_sequencer sequencer;
    
    // Control
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    
    function new(string name = "uart_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        monitor = uart_monitor::type_id::create("monitor", this);
        
        if (is_active == UVM_ACTIVE) begin
            driver = uart_driver::type_id::create("driver", this);
            sequencer = uart_sequencer::type_id::create("sequencer", this);
        end
    endfunction
    
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        if (is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction
    
endclass
