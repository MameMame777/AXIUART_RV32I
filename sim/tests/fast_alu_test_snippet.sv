// Fast ALU test using direct trace monitoring (no UART polling)
task execute_alu_test_fast(
    input string test_name,
    input bit [2:0] rd_idx,
    input bit [15:0] rd_init,
    input bit [2:0] rs_idx,
    input bit [15:0] rs_init,
    input bit [5:0] funct,
    input bit [15:0] expected_result,
    input bit expected_z,
    input bit expected_n,
    input bit expected_c
);
    bit [15:0] insn;
    int trace_idx;
    
    `uvm_info("ALU_TEST", $sformatf("=== %s ===", test_name), UVM_LOW)
    
    // Setup (minimal waits)
    write_cpu_reg(rd_idx, rd_init);
    write_cpu_reg(rs_idx, rs_init);
    insn = build_r_insn(rd_idx, rs_idx, funct);
    write_insn(16'h0000, insn);
    set_cpu_pc(16'h0000);
    
    // Clear trace buffer
    trace_idx = trace_vif.write_ptr;
    
    // Execute ONE instruction (no polling!)
    write_reg(CPU_DBG_CTRL, 32'h00000004); // Step
    
    // Wait for trace buffer update (1 cycle max!)
    repeat(10) @(posedge trace_vif.clk);
    if (trace_vif.write_ptr == trace_idx) begin
        `uvm_error("ALU_TEST", "No trace captured - CPU not executing")
    end
    
    // Read result from trace buffer (instant!)
    automatic bit [79:0] trace = trace_vif.trace_buffer[trace_idx];
    automatic bit [15:0] actual_result = trace[47:32];
    automatic bit actual_z = trace[2];
    automatic bit actual_n = trace[1];
    automatic bit actual_c = trace[0];
    
    // Verify
    if (actual_result !== expected_result) begin
        `uvm_error("ALU_TEST", $sformatf("Result: Expected=0x%04x, Got=0x%04x", 
            expected_result, actual_result))
    end else begin
        `uvm_info("ALU_TEST", "PASS: Result matched", UVM_MEDIUM)
    end
    
    if (actual_z !== expected_z || actual_n !== expected_n || actual_c !== expected_c) begin
        `uvm_error("ALU_TEST", $sformatf("Flags: Expected Z=%b N=%b C=%b, Got Z=%b N=%b C=%b",
            expected_z, expected_n, expected_c, actual_z, actual_n, actual_c))
    end else begin
        `uvm_info("ALU_TEST", "PASS: Flags matched", UVM_MEDIUM)
    end
endtask
