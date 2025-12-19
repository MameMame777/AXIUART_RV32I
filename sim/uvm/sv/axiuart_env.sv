
//------------------------------------------------------------------------------
// Simplified AXIUART Environment (UBUS Style)
//------------------------------------------------------------------------------

class axiuart_env extends uvm_env;
    
    `uvm_component_utils(axiuart_env)
    
    // Virtual interfaces
    protected virtual uart_if uart_vif;
    protected virtual axi4_lite_if axi_vif;
    
    // Control properties
    protected bit has_scoreboard = 1;
    protected bit has_axi_monitor = 1;
    
    // Components
    uart_agent uart_agt;
    axi4_lite_monitor axi_monitor;
    axiuart_scoreboard scoreboard;
    
    function new(string name = "axiuart_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get virtual interfaces
        if (!uvm_config_db#(virtual uart_if)::get(this, "", "uart_vif", uart_vif)) begin
            `uvm_fatal("ENV", "Failed to get UART virtual interface")
        end
        
        // AXI interface is optional (AXIUART_Top has internal bridge only)
        if (has_axi_monitor) begin
            if (!uvm_config_db#(virtual axi4_lite_if)::get(this, "", "axi_vif", axi_vif)) begin
                `uvm_warning("ENV", "AXI interface not found - disabling AXI monitor")
                has_axi_monitor = 0;
            end
        end
        
        // Set VIFs for subcomponents
        uvm_config_db#(virtual uart_if)::set(this, "uart_agt*", "vif", uart_vif);
        if (has_axi_monitor && axi_vif != null) begin
            uvm_config_db#(virtual axi4_lite_if)::set(this, "axi_monitor", "vif", axi_vif);
        end
        
        // Create components
        uart_agt = uart_agent::type_id::create("uart_agt", this);
        
        if (has_axi_monitor) begin
            axi_monitor = axi4_lite_monitor::type_id::create("axi_monitor", this);
        end
        
        if (has_scoreboard) begin
            scoreboard = axiuart_scoreboard::type_id::create("scoreboard", this);
        end
    endfunction
    
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        if (has_scoreboard) begin
            // Connect UART monitor to scoreboard (for DUT responses)
            uart_agt.monitor.item_collected_port.connect(scoreboard.uart_export);
            `uvm_info("ENV", "Connected Monitor → Scoreboard (uart_export)", UVM_MEDIUM)
            
            // Connect Driver to scoreboard (for write command tracking)
            // Driver broadcasts write commands to axi_export as AXI monitor substitute
            uart_agt.driver.item_sent_port.connect(scoreboard.axi_export);
            `uvm_info("ENV", "Connected Driver → Scoreboard (axi_export)", UVM_MEDIUM)
            
            // AXI monitor connection (disabled - using Driver instead)
            // if (has_axi_monitor && axi_monitor != null) begin
            //     axi_monitor.item_collected_port.connect(scoreboard.axi_export);
            // end
        end
    endfunction
    
endclass
