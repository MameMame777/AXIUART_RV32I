
//------------------------------------------------------------------------------
// Simplified AXI4-Lite Monitor (UBUS Style)
//------------------------------------------------------------------------------

class axi4_lite_monitor extends uvm_monitor;
    
    `uvm_component_utils(axi4_lite_monitor)
    
    // Virtual interface
    virtual axi4_lite_if vif;
    
    // Analysis port
    uvm_analysis_port #(uart_transaction) item_collected_port;
    
    function new(string name = "axi4_lite_monitor", uvm_component parent = null);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual axi4_lite_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXI_MONITOR", "Failed to get virtual interface")
        end
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        uart_transaction trans;
        
        fork
            monitor_write_channel();
            monitor_read_channel();
        join
    endtask
    
    // Monitor AXI write transactions
    virtual task monitor_write_channel();
        uart_transaction trans;
        
        forever begin
            @(posedge vif.aclk);
            
            if (vif.awvalid && vif.awready) begin
                trans = uart_transaction::type_id::create("trans");
                trans.address = vif.awaddr;
                trans.is_read = 1'b0;
                
                // Wait for write data
                while (!(vif.wvalid && vif.wready)) @(posedge vif.aclk);
                trans.data = vif.wdata;
                
                item_collected_port.write(trans);
                `uvm_info("AXI_MONITOR", $sformatf("AXI Write: ADDR=0x%08h DATA=0x%08h", 
                         trans.address, trans.data), UVM_HIGH)
            end
        end
    endtask
    
    // Monitor AXI read transactions
    virtual task monitor_read_channel();
        uart_transaction trans;
        
        forever begin
            @(posedge vif.aclk);
            
            if (vif.arvalid && vif.arready) begin
                trans = uart_transaction::type_id::create("trans");
                trans.address = vif.araddr;
                trans.is_read = 1'b1;
                
                // Wait for read data
                while (!(vif.rvalid && vif.rready)) @(posedge vif.aclk);
                trans.data = vif.rdata;
                
                item_collected_port.write(trans);
                `uvm_info("AXI_MONITOR", $sformatf("AXI Read: ADDR=0x%08h DATA=0x%08h",
                         trans.address, trans.data), UVM_HIGH)
            end
        end
    endtask
    
endclass
