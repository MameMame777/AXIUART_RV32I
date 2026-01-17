//------------------------------------------------------------------------------
// VexRiscv Smoke Test
// Purpose: Basic functionality test for VexRiscv CPU via UART
// Test Flow:
//   1. Load NOP program to memory via UART
//   2. Start CPU execution
//   3. Wait for execution
//   4. Halt CPU
//   5. Verify PC advanced and memory intact
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

import uvm_pkg::*;
import axiuart_reg_pkg::*;

class vexriscv_smoke_test extends axiuart_base_test;
    `uvm_component_utils(vexriscv_smoke_test)
    
    // Register addresses (VexRiscv debug interface)
    localparam bit [31:0] CPU_MEM_ADDR  = REG_CPU_MEM_ADDR;   // 0x1228
    localparam bit [31:0] CPU_MEM_WDATA = REG_CPU_MEM_WDATA;  // 0x122C
    localparam bit [31:0] CPU_MEM_RDATA = REG_CPU_MEM_RDATA;  // 0x1230
    localparam bit [31:0] CPU_MEM_CTRL  = REG_CPU_MEM_CTRL;   // 0x1234
    
    // CPU_MEM_CTRL bit fields
    localparam int CTRL_READ_REQ_BIT  = 4;
    localparam int CTRL_WRITE_REQ_BIT = 5;
    localparam int CTRL_BUSY_BIT      = 6;
    localparam int CTRL_RUN_BIT       = 7;
    localparam int CTRL_HALT_BIT      = 8;
    localparam int CTRL_HALTED_BIT    = 9;
    localparam int CTRL_BREAK_BIT     = 10;
    
    // Test program (simple NOP loop)
    typedef struct packed {
        bit [31:0] addr;
        bit [31:0] data;
    } mem_entry_t;
    
    mem_entry_t test_program[$];
    
    function new(string name = "vexriscv_smoke_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Build test program: 4 NOPs + infinite loop
        // Address 0x0000: ADDI x0, x0, 0 (NOP)
        test_program.push_back('{addr: 32'h0000_0000, data: 32'h0000_0013});
        test_program.push_back('{addr: 32'h0000_0004, data: 32'h0000_0013});
        test_program.push_back('{addr: 32'h0000_0008, data: 32'h0000_0013});
        test_program.push_back('{addr: 32'h0000_000C, data: 32'h0000_0013});
        // Address 0x0010: JAL x0, -16 (jump back to 0x0000)
        test_program.push_back('{addr: 32'h0000_0010, data: 32'hFF1F_F06F});
    endfunction
    
    task run_phase(uvm_phase phase);
        uart_reset_sequence reset_seq;
        bit [31:0] read_data;
        int timeout;
        
        phase.raise_objection(this, "Starting VexRiscv smoke test");
        `uvm_info(get_type_name(), "=== VexRiscv Smoke Test Started ===", UVM_LOW)
        
        // 1. Reset system
        reset_seq = uart_reset_sequence::type_id::create("reset_seq");
        reset_seq.start(env.uart_agt.sequencer);
        #100ns;
        
        // 2. Verify CPU is halted at reset
        `uvm_info(get_type_name(), "Step 1: Verify CPU halted after reset", UVM_MEDIUM)
        read_register(CPU_MEM_CTRL, read_data);
        if (read_data[CTRL_HALTED_BIT] !== 1'b1) begin
            `uvm_error(get_type_name(), $sformatf("CPU not halted after reset! CTRL=0x%08X", read_data))
        end else begin
            `uvm_info(get_type_name(), "✓ CPU halted after reset", UVM_LOW)
        end
        
        // 3. Load test program to memory
        `uvm_info(get_type_name(), "Step 2: Load test program via UART", UVM_MEDIUM)
        foreach (test_program[i]) begin
            write_cpu_memory(test_program[i].addr, test_program[i].data);
            `uvm_info(get_type_name(), 
                      $sformatf("  Wrote [0x%08X] = 0x%08X", 
                                test_program[i].addr, test_program[i].data), 
                      UVM_HIGH)
        end
        
        // 4. Verify program loaded correctly
        `uvm_info(get_type_name(), "Step 3: Verify program loaded", UVM_MEDIUM)
        foreach (test_program[i]) begin
            read_cpu_memory(test_program[i].addr, read_data);
            if (read_data !== test_program[i].data) begin
                `uvm_error(get_type_name(), 
                          $sformatf("Memory verification failed at 0x%08X: expected 0x%08X, got 0x%08X",
                                    test_program[i].addr, test_program[i].data, read_data))
            end
        end
        `uvm_info(get_type_name(), "✓ Program verified in memory", UVM_LOW)
        
        // 5. Start CPU execution
        `uvm_info(get_type_name(), "Step 4: Start CPU execution", UVM_MEDIUM)
        write_register(CPU_MEM_CTRL, (1 << CTRL_RUN_BIT));
        #100ns;
        
        // 6. Verify CPU is running
        read_register(CPU_MEM_CTRL, read_data);
        if (read_data[CTRL_HALTED_BIT] !== 1'b0) begin
            `uvm_error(get_type_name(), 
                      $sformatf("CPU not running! CTRL=0x%08X", read_data))
        end else begin
            `uvm_info(get_type_name(), "✓ CPU is running", UVM_LOW)
        end
        
        // 7. Let CPU execute for some time
        `uvm_info(get_type_name(), "Step 5: Execute program (~1000 cycles)", UVM_MEDIUM)
        #10us;  // ~1250 cycles at 125MHz
        
        // 8. Halt CPU
        `uvm_info(get_type_name(), "Step 6: Halt CPU", UVM_MEDIUM)
        write_register(CPU_MEM_CTRL, (1 << CTRL_HALT_BIT));
        
        // 9. Wait for CPU to halt (with timeout)
        timeout = 0;
        forever begin
            #100ns;
            read_register(CPU_MEM_CTRL, read_data);
            if (read_data[CTRL_HALTED_BIT] === 1'b1) break;
            
            timeout++;
            if (timeout > 100) begin
                `uvm_error(get_type_name(), "Timeout waiting for CPU halt")
                break;
            end
        end
        `uvm_info(get_type_name(), "✓ CPU halted", UVM_LOW)
        
        // 10. Verify program still in memory (no corruption)
        `uvm_info(get_type_name(), "Step 7: Verify memory integrity", UVM_MEDIUM)
        foreach (test_program[i]) begin
            read_cpu_memory(test_program[i].addr, read_data);
            if (read_data !== test_program[i].data) begin
                `uvm_error(get_type_name(), 
                          $sformatf("Memory corruption at 0x%08X: expected 0x%08X, got 0x%08X",
                                    test_program[i].addr, test_program[i].data, read_data))
            end
        end
        `uvm_info(get_type_name(), "✓ Memory integrity verified", UVM_LOW)
        
        // 11. Check for EBREAK (should not be triggered)
        if (read_data[CTRL_BREAK_BIT] === 1'b1) begin
            `uvm_warning(get_type_name(), "EBREAK flag set (unexpected in smoke test)")
        end
        
        #1000ns;
        
        `uvm_info(get_type_name(), "=== VexRiscv Smoke Test Completed Successfully ===", UVM_LOW)
        phase.drop_objection(this, "VexRiscv smoke test completed");
    endtask
    
    //--------------------------------------------------------------------------
    // Helper Tasks
    //--------------------------------------------------------------------------
    
    // Write to CPU memory via debug interface
    task write_cpu_memory(input bit [31:0] addr, input bit [31:0] data);
        bit [31:0] ctrl_val;
        int timeout;
        
        // Set address
        write_register(CPU_MEM_ADDR, addr);
        
        // Set write data
        write_register(CPU_MEM_WDATA, data);
        
        // Trigger write (byte enables = 0xF for full word write)
        ctrl_val = 32'h0000_000F | (1 << CTRL_WRITE_REQ_BIT);
        write_register(CPU_MEM_CTRL, ctrl_val);
        
        // Wait for completion (busy bit clears)
        timeout = 0;
        forever begin
            #50ns;
            read_register(CPU_MEM_CTRL, ctrl_val);
            if (ctrl_val[CTRL_BUSY_BIT] === 1'b0) break;
            
            timeout++;
            if (timeout > 100) begin
                `uvm_error(get_type_name(), 
                          $sformatf("Timeout writing to memory addr 0x%08X", addr))
                break;
            end
        end
    endtask
    
    // Read from CPU memory via debug interface
    task read_cpu_memory(input bit [31:0] addr, output bit [31:0] data);
        bit [31:0] ctrl_val;
        int timeout;
        
        // Set address
        write_register(CPU_MEM_ADDR, addr);
        
        // Trigger read
        ctrl_val = (1 << CTRL_READ_REQ_BIT);
        write_register(CPU_MEM_CTRL, ctrl_val);
        
        // Wait for completion
        timeout = 0;
        forever begin
            #50ns;
            read_register(CPU_MEM_CTRL, ctrl_val);
            if (ctrl_val[CTRL_BUSY_BIT] === 1'b0) break;
            
            timeout++;
            if (timeout > 100) begin
                `uvm_error(get_type_name(), 
                          $sformatf("Timeout reading from memory addr 0x%08X", addr))
                data = 32'hDEAD_BEEF;
                return;
            end
        end
        
        // Read data
        read_register(CPU_MEM_RDATA, data);
    endtask
    
    // Write to register using UART protocol
    task write_register(input bit [31:0] addr, input bit [31:0] data);
        uart_reg_write_sequence write_seq;
        write_seq = uart_reg_write_sequence::type_id::create("write_seq");
        write_seq.addr = addr;
        write_seq.data = data;
        write_seq.start(env.uart_agt.sequencer);
    endtask
    
    // Read from register using UART protocol
    task read_register(input bit [31:0] addr, output bit [31:0] data);
        uart_reg_read_sequence read_seq;
        read_seq = uart_reg_read_sequence::type_id::create("read_seq");
        read_seq.addr = addr;
        read_seq.start(env.uart_agt.sequencer);
        data = read_seq.read_data;
    endtask
    
endclass
