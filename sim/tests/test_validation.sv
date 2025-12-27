`timescale 1ns / 1ps

module test_validation;

    // Replicate the validation logic
    localparam bit [11:0] REG_CPU_TRACE_BASE = 12'h300;
    
    function automatic bit is_read_access_valid(logic [11:0] offset);
        logic [11:0] aligned_offset;
        aligned_offset = {offset[11:2], 2'b00};
        
        // Check trace buffer range first (0x300-0x3FC, 256 entries)
        if (aligned_offset >= REG_CPU_TRACE_BASE && aligned_offset < (REG_CPU_TRACE_BASE + 12'h100)) begin
            return (offset[1:0] == 2'b00);  // Word-aligned
        end
        
        return 1'b0;
    endfunction

    initial begin
        logic [11:0] test_offset;
        bit result;
        
        $display("=== Testing is_read_access_valid ===");
        $display("");
        
        // Test trace buffer addresses
        test_offset = 12'h300;
        result = is_read_access_valid(test_offset);
        $display("Offset 0x%03X: aligned=0x%03X, result=%b %s", 
                 test_offset, {test_offset[11:2], 2'b00}, result,
                 result ? "PASS" : "FAIL");
        
        test_offset = 12'h304;
        result = is_read_access_valid(test_offset);
        $display("Offset 0x%03X: aligned=0x%03X, result=%b %s", 
                 test_offset, {test_offset[11:2], 2'b00}, result,
                 result ? "PASS" : "FAIL");
        
        test_offset = 12'h3FC;
        result = is_read_access_valid(test_offset);
        $display("Offset 0x%03X: aligned=0x%03X, result=%b %s", 
                 test_offset, {test_offset[11:2], 2'b00}, result,
                 result ? "PASS" : "FAIL");
        
        test_offset = 12'h400;
        result = is_read_access_valid(test_offset);
        $display("Offset 0x%03X: aligned=0x%03X, result=%b %s (should be FAIL)", 
                 test_offset, {test_offset[11:2], 2'b00}, result,
                 result ? "PASS" : "FAIL");
        
        test_offset = 12'h2FF;
        result = is_read_access_valid(test_offset);
        $display("Offset 0x%03X: aligned=0x%03X, result=%b %s (should be FAIL)", 
                 test_offset, {test_offset[11:2], 2'b00}, result,
                 result ? "PASS" : "FAIL");
        
        $display("");
        $display("=== Checking range condition ===");
        test_offset = 12'h300;
        $display("REG_CPU_TRACE_BASE = 0x%03X", REG_CPU_TRACE_BASE);
        $display("REG_CPU_TRACE_BASE + 0x100 = 0x%03X", REG_CPU_TRACE_BASE + 12'h100);
        $display("Test offset 0x300:");
        $display("  aligned_offset >= REG_CPU_TRACE_BASE? %b (0x%03X >= 0x%03X)", 
                 test_offset >= REG_CPU_TRACE_BASE, test_offset, REG_CPU_TRACE_BASE);
        $display("  aligned_offset < (BASE+0x100)? %b (0x%03X < 0x%03X)", 
                 test_offset < (REG_CPU_TRACE_BASE + 12'h100), test_offset, REG_CPU_TRACE_BASE + 12'h100);
        $display("  offset[1:0] == 2'b00? %b", test_offset[1:0] == 2'b00);
        
        $finish;
    end

endmodule
