`timescale 1ns / 1ps

//==============================================================================
// UART Bridge Unit Test Base Class
//==============================================================================
// Description:
//   Base class for UART Bridge submodule unit tests.
//   Provides common infrastructure including:
//   - Reference CRC-8 calculator
//   - FIFO helper methods (using class member queue)
//   - Frame building utilities
//   - Report helpers
//
// Author: Claude Code
// Date: February 8, 2026
//==============================================================================

class uart_bridge_base_test extends uvm_test;

    `uvm_component_utils(uart_bridge_base_test)

    //==========================================================================
    // Properties
    //==========================================================================

    int timeout_cycles = 10000;
    int error_count = 0;

    // Internal FIFO model (class member queue)
    logic [7:0] m_fifo[$];

    //==========================================================================
    // Constructor
    //==========================================================================

    function new(string name = "uart_bridge_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info(get_type_name(), "UART Bridge Base Test configured", UVM_LOW)
    endfunction

    //==========================================================================
    // Reference CRC-8 Calculator
    //==========================================================================
    // CRC-8-CCITT: poly=0x07, init=0x00, no reflect, no xor_out
    //==========================================================================

    virtual function logic [7:0] calc_crc8_byte(logic [7:0] data, logic [7:0] crc_in);
        logic [7:0] crc;

        crc = crc_in ^ data;

        // 8 rounds of polynomial division (matching RTL Crc8_Calculator.sv)
        if (crc[7]) crc = (crc << 1) ^ 8'h07; else crc = crc << 1;
        if (crc[7]) crc = (crc << 1) ^ 8'h07; else crc = crc << 1;
        if (crc[7]) crc = (crc << 1) ^ 8'h07; else crc = crc << 1;
        if (crc[7]) crc = (crc << 1) ^ 8'h07; else crc = crc << 1;
        if (crc[7]) crc = (crc << 1) ^ 8'h07; else crc = crc << 1;
        if (crc[7]) crc = (crc << 1) ^ 8'h07; else crc = crc << 1;
        if (crc[7]) crc = (crc << 1) ^ 8'h07; else crc = crc << 1;
        if (crc[7]) crc = (crc << 1) ^ 8'h07; else crc = crc << 1;

        return crc;
    endfunction

    // Calculate CRC for multiple bytes
    virtual function logic [7:0] calc_crc8(logic [7:0] data_bytes[], int num_bytes);
        logic [7:0] crc;
        int i;

        crc = 8'h00;
        for (i = 0; i < num_bytes; i++) begin
            crc = calc_crc8_byte(data_bytes[i], crc);
        end

        return crc;
    endfunction

    //==========================================================================
    // FIFO Helper Methods (uses m_fifo class member)
    //==========================================================================

    virtual function void fifo_push(logic [7:0] data);
        m_fifo.push_back(data);
    endfunction

    virtual function logic [7:0] fifo_pop();
        logic [7:0] val;
        if (m_fifo.size() > 0) begin
            val = m_fifo.pop_front();
            return val;
        end
        return 8'hXX;
    endfunction

    virtual function int fifo_size();
        return m_fifo.size();
    endfunction

    virtual function bit fifo_is_empty();
        return (m_fifo.size() == 0);
    endfunction

    virtual function void fifo_clear();
        m_fifo.delete();
    endfunction

    //==========================================================================
    // Frame Building Utilities
    //==========================================================================

    // Build a UART frame with CRC [SOF][CMD][ADDR(4)][DATA(n)][CRC]
    // Result stored in m_fifo
    virtual function void build_frame(
        logic [7:0] cmd,
        logic [31:0] addr,
        int num_data_bytes = 0
    );
        logic [7:0] crc_bytes[256];
        logic [7:0] crc;
        int crc_idx;

        crc_idx = 0;

        // Push SOF
        m_fifo.push_back(8'hA5);

        // CMD
        crc_bytes[crc_idx] = cmd;
        crc_idx++;
        m_fifo.push_back(cmd);

        // ADDR (little-endian)
        crc_bytes[crc_idx] = addr[7:0];
        crc_idx++;
        crc_bytes[crc_idx] = addr[15:8];
        crc_idx++;
        crc_bytes[crc_idx] = addr[23:16];
        crc_idx++;
        crc_bytes[crc_idx] = addr[31:24];
        crc_idx++;
        m_fifo.push_back(addr[7:0]);
        m_fifo.push_back(addr[15:8]);
        m_fifo.push_back(addr[23:16]);
        m_fifo.push_back(addr[31:24]);

        // CRC
        crc = calc_crc8(crc_bytes, crc_idx);
        m_fifo.push_back(crc);
    endfunction

    // Build a RESET command frame [SOF][0xFF][CRC]
    virtual function void build_reset_frame();
        logic [7:0] crc;

        m_fifo.push_back(8'hA5);   // SOF
        m_fifo.push_back(8'hFF);   // RESET command

        crc = calc_crc8_byte(8'hFF, 8'h00);
        m_fifo.push_back(crc);
    endfunction

    //==========================================================================
    // Check Helper
    //==========================================================================

    virtual function void check_value(string name, logic [31:0] actual, logic [31:0] expected);
        if (actual !== expected) begin
            `uvm_error(get_type_name(),
                $sformatf("FAIL: %s = 0x%08X (expected 0x%08X)", name, actual, expected))
            error_count++;
        end else begin
            `uvm_info(get_type_name(), $sformatf("PASS: %s = 0x%08X", name, expected), UVM_LOW)
        end
    endfunction

    //==========================================================================
    // Report Helpers
    //==========================================================================

    virtual function void report_test_pass(string msg = "");
        if (msg != "") begin
            `uvm_info(get_type_name(),
                $sformatf("\n========================================\n  TEST PASSED: %s\n========================================", msg),
                UVM_NONE)
        end else begin
            `uvm_info(get_type_name(),
                "\n========================================\n  TEST PASSED\n========================================",
                UVM_NONE)
        end
    endfunction

    virtual function void report_test_fail(string msg = "");
        if (msg != "") begin
            `uvm_error(get_type_name(),
                $sformatf("\n========================================\n  TEST FAILED: %s\n========================================", msg))
        end else begin
            `uvm_error(get_type_name(),
                "\n========================================\n  TEST FAILED\n========================================")
        end
    endfunction

endclass
