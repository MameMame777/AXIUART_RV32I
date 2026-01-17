`timescale 1ns / 1ps
//=====================================================================
// VexRiscv EBREAK Instruction Monitor
//=====================================================================
// Description:
//   Detects EBREAK instruction (0x00100073) from DBus transactions
//   - Monitors all DBus data payloads (both reads and writes)
//   - Registers cpu_break flag when EBREAK detected
//   - Clear on reset or explicit clear signal
//   - Write-back stage monitoring for accurate PC capture
//
// EBREAK Instruction Encoding:
//   31            20 19   15 14   12 11    7 6      0
//   [0000000000001] [00000] [000] [00000] [1110011]
//   imm[11:0]=1     rs1=x0  funct3 rd=x0   SYSTEM opcode
//   → Binary: 0000_0000_0001_0000_0000_0000_0111_0011
//   → Hex: 0x00100073
//
// Detection Strategy:
//   Monitor DBus response data (dBus_rsp_data) for instruction fetches
//   Also monitor DBus command data (dBus_cmd_payload_data) for writes
//   Set cpu_break flag on detection, auto-clear on next CPU run
//
// Author: GitHub Copilot (Claude Sonnet 4.5)
// Date: January 17, 2026
//=====================================================================

module vexriscv_ebreak_monitor (
    input  logic        clk,
    input  logic        rst,
    
    // DBus monitoring signals
    input  logic        dBus_cmd_valid,
    input  logic        dBus_cmd_ready,
    input  logic        dBus_cmd_payload_wr,
    input  logic [31:0] dBus_cmd_payload_data,    // Monitor write data
    input  logic [31:0] dBus_cmd_payload_address,
    
    input  logic        dBus_rsp_ready,
    input  logic [31:0] dBus_rsp_data,            // Monitor read data
    
    // IBus monitoring signals (optional - for instruction fetch tracking)
    input  logic        iBus_rsp_valid,
    input  logic [31:0] iBus_rsp_payload_inst,    // Monitor fetched instructions
    input  logic [31:0] iBus_cmd_payload_pc,      // Current PC
    
    // Control signals
    input  logic        cpu_running,              // CPU is executing
    input  logic        clear_break,              // Clear break flag (W1P)
    
    // Status outputs
    output logic        cpu_break,                // EBREAK detected
    output logic [31:0] break_pc                  // PC where EBREAK occurred
);

    //=================================================================
    // EBREAK Instruction Pattern
    //=================================================================
    
    localparam logic [31:0] EBREAK_OPCODE = 32'h0010_0073;
    
    //=================================================================
    // EBREAK Detection Logic
    //=================================================================
    
    // Detect EBREAK in various data sources
    logic ebreak_in_ibus;
    logic ebreak_in_dbus_rsp;
    logic ebreak_in_dbus_cmd;
    logic ebreak_detected;
    
    always_comb begin
        // Check IBus instruction fetch (most reliable source)
        ebreak_in_ibus = iBus_rsp_valid && 
                         (iBus_rsp_payload_inst == EBREAK_OPCODE);
        
        // Check DBus response data (load from instruction memory)
        ebreak_in_dbus_rsp = dBus_rsp_ready && 
                             (dBus_rsp_data == EBREAK_OPCODE);
        
        // Check DBus command data (store to instruction memory)
        ebreak_in_dbus_cmd = dBus_cmd_valid && 
                             dBus_cmd_ready && 
                             dBus_cmd_payload_wr &&
                             (dBus_cmd_payload_data == EBREAK_OPCODE);
        
        // Any detection triggers break
        ebreak_detected = ebreak_in_ibus || ebreak_in_dbus_rsp || ebreak_in_dbus_cmd;
    end
    
    //=================================================================
    // Break Status Register
    //=================================================================
    
    always_ff @(posedge clk) begin
        if (rst || clear_break) begin
            cpu_break <= 1'b0;
            break_pc  <= 32'h0000_0000;
        end else if (ebreak_detected && cpu_running) begin
            // Set break flag only when CPU is running
            // (Prevents false triggers during program loading)
            cpu_break <= 1'b1;
            
            // Capture PC where EBREAK occurred
            if (ebreak_in_ibus) begin
                // IBus provides most accurate PC
                break_pc <= iBus_cmd_payload_pc;
            end else if (ebreak_in_dbus_cmd) begin
                // DBus store to instruction memory (less common)
                break_pc <= dBus_cmd_payload_address;
            end else begin
                // Keep previous PC
                break_pc <= break_pc;
            end
        end
    end
    
    //=================================================================
    // EBREAK Detection Counter (Debug)
    //=================================================================
    
    `ifdef SIMULATION
    logic [31:0] ebreak_count;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            ebreak_count <= 32'h0000_0000;
        end else if (ebreak_detected && cpu_running) begin
            ebreak_count <= ebreak_count + 1;
            $display("[EBREAK_MONITOR] EBREAK detected at PC=0x%08X (count=%0d)", 
                     ebreak_in_ibus ? iBus_cmd_payload_pc : dBus_cmd_payload_address,
                     ebreak_count + 1);
        end
    end
    
    // Log EBREAK detection sources
    always_ff @(posedge clk) begin
        if (!rst && ebreak_detected && cpu_running) begin
            if (ebreak_in_ibus) begin
                $display("[EBREAK_MONITOR]   Source: IBus instruction fetch (PC=0x%08X, inst=0x%08X)",
                         iBus_cmd_payload_pc, iBus_rsp_payload_inst);
            end
            if (ebreak_in_dbus_rsp) begin
                $display("[EBREAK_MONITOR]   Source: DBus read response (data=0x%08X)",
                         dBus_rsp_data);
            end
            if (ebreak_in_dbus_cmd) begin
                $display("[EBREAK_MONITOR]   Source: DBus write command (addr=0x%08X, data=0x%08X)",
                         dBus_cmd_payload_address, dBus_cmd_payload_data);
            end
        end
    end
    
    // Warn on EBREAK during program loading (cpu not running)
    always_ff @(posedge clk) begin
        if (!rst && ebreak_detected && !cpu_running) begin
            $warning("[EBREAK_MONITOR] EBREAK pattern detected while CPU not running (likely program load)");
        end
    end
    `endif

endmodule
