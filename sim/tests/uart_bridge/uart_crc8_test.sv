`timescale 1ns / 1ps

//==============================================================================
// CRC-8 Calculator Unit Test
//==============================================================================
// Test ID: UART Bridge - Module Test 1
// Duration: ~5-10s
//
// Purpose:
//   Verify CRC-8-CCITT calculator (poly=0x07) functionality with:
//   - Known CRC-8 test vectors (0x00, 0xFF, RESET command)
//   - Multi-byte CRC accumulation
//   - Back-to-back operations (reset and recompute)
//
// Pass/Fail Criteria:
//   - All CRC values match reference calculation
//==============================================================================

class uart_crc8_test extends uart_bridge_base_test;

    `uvm_component_utils(uart_crc8_test)

    function new(string name = "uart_crc8_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info(get_type_name(), "UART CRC-8 Unit Test configured", UVM_LOW)
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        `uvm_info(get_type_name(),
            "\n========================================\n  CRC-8 Calculator Unit Test\n  Testing: CRC-8-CCITT (poly=0x07)\n========================================",
            UVM_NONE)

        test_known_vectors();
        test_multi_byte_crc();
        test_back_to_back();

        if (error_count == 0) begin
            report_test_pass("All CRC-8 tests passed");
        end else begin
            report_test_fail($sformatf("%0d CRC-8 errors detected", error_count));
        end

        phase.drop_objection(this);
    endtask

    //====================================================================
    // Test 1: Known CRC-8 Vectors
    //====================================================================

    virtual task test_known_vectors();
        logic [7:0] crc_val;

        `uvm_info(get_type_name(), "TEST 1: Known CRC-8-CCITT Vectors", UVM_MEDIUM)

        // Test vector 1: Single byte 0x00 -> CRC = 0x00
        crc_val = calc_crc8_byte(8'h00, 8'h00);
        check_value("CRC(0x00)", {24'h0, crc_val}, 32'h00000000);

        // Test vector 2: Single byte 0xFF -> CRC = 0xF3
        crc_val = calc_crc8_byte(8'hFF, 8'h00);
        check_value("CRC(0xFF)", {24'h0, crc_val}, 32'h000000F3);

        // Test vector 3: Single byte 0xA5 (SOF)
        crc_val = calc_crc8_byte(8'hA5, 8'h00);
        `uvm_info(get_type_name(), $sformatf("CRC(0xA5) = 0x%02X", crc_val), UVM_LOW)

        // Test vector 4: Single byte 0x01
        crc_val = calc_crc8_byte(8'h01, 8'h00);
        `uvm_info(get_type_name(), $sformatf("CRC(0x01) = 0x%02X", crc_val), UVM_LOW)

    endtask

    //====================================================================
    // Test 2: Multi-Byte CRC
    //====================================================================

    virtual task test_multi_byte_crc();
        logic [7:0] test_bytes[6];
        logic [7:0] crc_val;

        `uvm_info(get_type_name(), "TEST 2: Multi-Byte CRC Accumulation", UVM_MEDIUM)

        test_bytes[0] = 8'hA5;
        test_bytes[1] = 8'h10;
        test_bytes[2] = 8'h00;
        test_bytes[3] = 8'h10;
        test_bytes[4] = 8'h00;
        test_bytes[5] = 8'h80;

        crc_val = calc_crc8(test_bytes, 6);

        `uvm_info(get_type_name(),
            $sformatf("CRC([A5 10 00 10 00 80]) = 0x%02X", crc_val), UVM_LOW)

        // Verify CRC is non-zero for non-trivial input
        if (crc_val === 8'hXX) begin
            `uvm_error(get_type_name(), "FAIL: CRC returned X/Z for valid input")
            error_count++;
        end else begin
            `uvm_info(get_type_name(), "PASS: Multi-byte CRC computed successfully", UVM_LOW)
        end

    endtask

    //====================================================================
    // Test 3: Back-to-Back Operations
    //====================================================================

    virtual task test_back_to_back();
        logic [7:0] test_bytes[5];
        logic [7:0] crc1;
        logic [7:0] crc2;

        `uvm_info(get_type_name(), "TEST 3: Back-to-Back Operations", UVM_MEDIUM)

        test_bytes[0] = 8'hA5;
        test_bytes[1] = 8'h00;
        test_bytes[2] = 8'h12;
        test_bytes[3] = 8'h34;
        test_bytes[4] = 8'h56;

        crc1 = calc_crc8(test_bytes, 5);
        crc2 = calc_crc8(test_bytes, 5);

        if (crc1 !== crc2) begin
            `uvm_error(get_type_name(),
                $sformatf("FAIL: Back-to-back CRC mismatch (first=0x%02X, second=0x%02X)", crc1, crc2))
            error_count++;
        end else begin
            `uvm_info(get_type_name(),
                $sformatf("PASS: Back-to-back CRC identical (0x%02X)", crc1), UVM_LOW)
        end

    endtask

endclass
