`timescale 1ns / 1ps

// Direct CPU trace monitor - bypasses UART for fast verification
class cpu_trace_monitor extends uvm_monitor;
    `uvm_component_utils(cpu_trace_monitor)
    
    // Analysis port for broadcasting trace events
    uvm_analysis_port #(cpu_trace_item) ap;
    
    // Virtual interface to trace buffer (direct RTL access)
    virtual td4cpu_trace_if trace_vif;
    
    // Tracking
    int last_read_ptr = 0;
    int total_traces = 0;
    
    function new(string name = "cpu_trace_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get virtual interface from config DB
        if (!uvm_config_db#(virtual td4cpu_trace_if)::get(this, "", "trace_vif", trace_vif)) begin
            `uvm_warning("CPU_TRACE_MON", "Trace interface not found - monitor disabled")
        end
    endfunction
    
    task run_phase(uvm_phase phase);
        cpu_trace_item item;
        
        if (trace_vif == null) begin
            `uvm_info("CPU_TRACE_MON", "Trace monitor disabled (no interface)", UVM_LOW)
            return;
        end
        
        `uvm_info("CPU_TRACE_MON", "Starting direct CPU trace monitoring", UVM_MEDIUM)
        
        forever begin
            @(posedge trace_vif.clk);
            
            // Check if new trace entries available
            if (trace_vif.write_ptr != last_read_ptr) begin
                item = cpu_trace_item::type_id::create("item");
                
                // Read trace entry directly from buffer
                item.pc       = trace_vif.trace_buffer[last_read_ptr][79:64];
                item.insn     = trace_vif.trace_buffer[last_read_ptr][63:48];
                item.rd_value = trace_vif.trace_buffer[last_read_ptr][47:32];
                item.rs_value = trace_vif.trace_buffer[last_read_ptr][31:16];
                item.flag_z   = trace_vif.trace_buffer[last_read_ptr][2];
                item.flag_n   = trace_vif.trace_buffer[last_read_ptr][1];
                item.flag_c   = trace_vif.trace_buffer[last_read_ptr][0];
                
                // Broadcast to scoreboard
                ap.write(item);
                
                total_traces++;
                last_read_ptr = (last_read_ptr + 1) % 64;
                
                `uvm_info("CPU_TRACE_MON", 
                    $sformatf("Trace[%0d]: PC=0x%04x INSN=0x%04x RD=0x%04x RS=0x%04x FLAGS=%b%b%b",
                        total_traces-1, item.pc, item.insn, item.rd_value, item.rs_value,
                        item.flag_z, item.flag_n, item.flag_c), UVM_DEBUG)
            end
        end
    endtask
    
    function void report_phase(uvm_phase phase);
        `uvm_info("CPU_TRACE_MON", $sformatf("Captured %0d trace entries", total_traces), UVM_LOW)
    endfunction
endclass

// Trace transaction item
class cpu_trace_item extends uvm_sequence_item;
    rand bit [15:0] pc;
    rand bit [15:0] insn;
    rand bit [15:0] rd_value;
    rand bit [15:0] rs_value;
    rand bit        flag_z;
    rand bit        flag_n;
    rand bit        flag_c;
    
    `uvm_object_utils_begin(cpu_trace_item)
        `uvm_field_int(pc,       UVM_ALL_ON)
        `uvm_field_int(insn,     UVM_ALL_ON)
        `uvm_field_int(rd_value, UVM_ALL_ON)
        `uvm_field_int(rs_value, UVM_ALL_ON)
        `uvm_field_int(flag_z,   UVM_ALL_ON)
        `uvm_field_int(flag_n,   UVM_ALL_ON)
        `uvm_field_int(flag_c,   UVM_ALL_ON)
    `uvm_object_utils_end
    
    function new(string name = "cpu_trace_item");
        super.new(name);
    endfunction
endclass

// Interface for trace buffer access
interface td4cpu_trace_if(input logic clk);
    logic [63:0][79:0] trace_buffer;
    logic [5:0]  write_ptr;
    logic [5:0]  entry_count;
endinterface
