//------------------------------------------------------------------------------
// AXIUART Register Read/Write Test
// Purpose: Demonstrates register access and scoreboard verification
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

import axiuart_reg_pkg::*;

class axiuart_reg_rw_test extends axiuart_base_test;
    `uvm_component_utils(axiuart_reg_rw_test)
    
    function new(string name = "axiuart_reg_rw_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction
    
    task run_phase(uvm_phase phase);
        uart_reset_sequence reset_seq;
        uart_reg_write_sequence wr_seq[6];
        uart_reg_read_sequence rd_seq[6];
        bit [31:0] test_data[6] = '{32'h1111_1111, 32'h2222_2222, 
                                     32'h3333_3333, 32'h4444_4444, 
                                     32'h5555_5555, 32'h0000_000F};
        int error_count = 0;
        
        phase.raise_objection(this, "Starting register R/W test");
        `uvm_info(get_type_name(), "=== AXIUART Register R/W Test Started ===", UVM_LOW)
        
        // 1. Reset DUT
        reset_seq = uart_reset_sequence::type_id::create("reset_seq");
        reset_seq.reset_cycles = 100;
        reset_seq.start(env.uart_agt.sequencer);
        
        // 2. Write 6 test registers (REG_TEST_0-4 + REG_TEST_LED using register package)
        `uvm_info(get_type_name(), "Writing 6 test registers (REG_TEST_0-4 + REG_TEST_LED)...", UVM_LOW)
        for (int i = 0; i < 6; i++) begin
            wr_seq[i] = uart_reg_write_sequence::type_id::create($sformatf("wr_seq_%0d", i));
            // Use generated register addresses from axiuart_reg_pkg
            if (i < 4)
                wr_seq[i].reg_addr = REG_TEST_0 + (i * 4);
            else if (i == 4)
                wr_seq[i].reg_addr = REG_TEST_4;
            else
                wr_seq[i].reg_addr = REG_TEST_LED;
            wr_seq[i].reg_data = test_data[i];
            wr_seq[i].start(env.uart_agt.sequencer);
        end
        
        #5000ns;  // Wait for DUT processing
        
        // 3. Send read commands (note: read-back verification requires Monitor enhancement)
        `uvm_info(get_type_name(), "Sending read commands for 6 test registers...", UVM_LOW)
        for (int i = 0; i < 6; i++) begin
            rd_seq[i] = uart_reg_read_sequence::type_id::create($sformatf("rd_seq_%0d", i));
            // Use generated register addresses from axiuart_reg_pkg
            if (i < 4)
                rd_seq[i].reg_addr = REG_TEST_0 + (i * 4);
            else if (i == 4)
                rd_seq[i].reg_addr = REG_TEST_4;
            else
                rd_seq[i].reg_addr = REG_TEST_LED;
            rd_seq[i].start(env.uart_agt.sequencer);
            `uvm_info(get_type_name(), 
                $sformatf("Read command sent for addr=0x%08X", rd_seq[i].reg_addr), UVM_MEDIUM)
        end
        
        #5000000ns;  // Wait 5ms for all READ responses (5 frames × 694μs each + margin)
        
        // 5. Verify Scoreboard results
        `uvm_info(get_type_name(), "=== Verification Phase: Scoreboard Check ===", UVM_LOW)
        
        if (env.scoreboard.mismatch_count > 0) begin
            `uvm_error(get_type_name(), 
                $sformatf("Register verification FAILED: %0d mismatches detected", 
                          env.scoreboard.mismatch_count))
        end else if (env.scoreboard.match_count == 0) begin
            `uvm_warning(get_type_name(), 
                "No read responses verified - check Monitor/DUT connection")
        end else begin
            `uvm_info(get_type_name(), 
                $sformatf("Register verification PASSED: %0d reads matched expected values", 
                          env.scoreboard.match_count), UVM_LOW)
        end
        
        `uvm_info(get_type_name(), "=== AXIUART Register R/W Test Completed ===", UVM_LOW)
        phase.drop_objection(this, "Register R/W test completed");
    endtask
endclass
