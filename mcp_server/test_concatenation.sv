`timescale 1ns / 1ps

module test_concatenation;

    localparam logic [3:0] OP_LDI = 4'h1;
    localparam logic [3:0] OP_ADDI = 4'h2;
    
    logic [15:0] result1, result2;
    
    initial begin
        // Test LDI R1, #0x80
        result1 = {OP_LDI, 3'd1, 9'h080};
        $display("LDI R1, #0x80: {OP_LDI=0x%01x, rd=1, imm=0x080} = 0x%04x", OP_LDI, result1);
        $display("  Expected: 0x1280");
        $display("  Decoded: op=%0d, rd=%0d, imm=0x%03x", result1[15:12], result1[11:9], result1[8:0]);
        
        // Test ADDI R1, #0x80
        result2 = {OP_ADDI, 3'd1, 9'h080};
        $display("ADDI R1, #0x80: {OP_ADDI=0x%01x, rd=1, imm=0x080} = 0x%04x", OP_ADDI, result2);
        $display("  Expected: 0x2280");
        $display("  Decoded: op=%0d, rd=%0d, imm=0x%03x", result2[15:12], result2[11:9], result2[8:0]);
        
        $finish;
    end

endmodule
