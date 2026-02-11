`timescale 1ns / 1ps

//==============================================================================
// Frame Parser Unit Test
//==============================================================================
// Test ID: UART Bridge - Module Test 3
// Duration: ~15-20s
//
// Purpose:
//   Verify Frame_Parser frame building and CRC validation with:
//   - Frame building with CRC calculation
//   - RESET command frame construction
//   - Frame format validation
//
// Pass/Fail Criteria:
//   - Frame building produces correct byte sequences
//   - CRC values match expected for known frames
//==============================================================================

class uart_frame_parser_test extends uart_bridge_base_test;

    `uvm_component_utils(uart_frame_parser_test)

    function new(string name = "uart_frame_parser_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info(get_type_name(), "UART Frame_Parser Unit Test configured", UVM_LOW)
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        `uvm_info(get_type_name(),
            "\n========================================\n  Frame Parser Unit Test\n  Testing: Frame parsing and CRC\n========================================",
            UVM_NONE)

        test_frame_building();
        test_reset_frame();
        test_crc_in_frames();

        if (error_count == 0) begin
            report_test_pass("All Frame_Parser tests passed");
        end else begin
            report_test_fail($sformatf("%0d Frame_Parser errors detected", error_count));
        end

        phase.drop_objection(this);
    endtask

    //====================================================================
    // Test 1: Frame Building
    //====================================================================

    virtual task test_frame_building();
        int frame_size;

        `uvm_info(get_type_name(), "TEST 1: Frame Building", UVM_MEDIUM)

        fifo_clear();

        // Build a WRITE command frame: CMD=0x10 ADDR=0x80001000
        build_frame(8'h10, 32'h80001000);

        frame_size = fifo_size();

        // Expected: SOF(1) + CMD(1) + ADDR(4) + CRC(1) = 7 bytes
        check_value("WRITE frame size", frame_size, 7);

        // Verify SOF byte
        if (frame_size > 0) begin
            check_value("SOF byte", {24'h0, fifo_pop()}, 32'h000000A5);
        end

        // Verify CMD byte
        if (fifo_size() > 0) begin
            check_value("CMD byte", {24'h0, fifo_pop()}, 32'h00000010);
        end

        `uvm_info(get_type_name(), "PASS: WRITE frame built correctly", UVM_LOW)

    endtask

    //====================================================================
    // Test 2: RESET Frame
    //====================================================================

    virtual task test_reset_frame();
        int frame_size;
        logic [7:0] sof_byte;
        logic [7:0] cmd_byte;
        logic [7:0] crc_byte;

        `uvm_info(get_type_name(), "TEST 2: RESET Command Frame", UVM_MEDIUM)

        fifo_clear();

        build_reset_frame();

        frame_size = fifo_size();

        // RESET frame: SOF(1) + CMD(1) + CRC(1) = 3 bytes
        check_value("RESET frame size", frame_size, 3);

        if (frame_size == 3) begin
            sof_byte = fifo_pop();
            cmd_byte = fifo_pop();
            crc_byte = fifo_pop();

            check_value("RESET SOF", {24'h0, sof_byte}, 32'h000000A5);
            check_value("RESET CMD", {24'h0, cmd_byte}, 32'h000000FF);
            check_value("RESET CRC", {24'h0, crc_byte}, 32'h000000F3);
        end

    endtask

    //====================================================================
    // Test 3: CRC in Frames
    //====================================================================

    virtual task test_crc_in_frames();
        logic [7:0] crc_bytes[5];
        logic [7:0] expected_crc;
        logic [7:0] frame_crc;
        logic [7:0] dummy;
        int i;

        `uvm_info(get_type_name(), "TEST 3: CRC Validation in Frames", UVM_MEDIUM)

        fifo_clear();

        // Build READ command frame: CMD=0x90 ADDR=0x80001000
        build_frame(8'h90, 32'h80001000);

        // Calculate expected CRC manually
        crc_bytes[0] = 8'h90;          // CMD
        crc_bytes[1] = 8'h00;          // ADDR[7:0]
        crc_bytes[2] = 8'h10;          // ADDR[15:8]
        crc_bytes[3] = 8'h00;          // ADDR[23:16]
        crc_bytes[4] = 8'h80;          // ADDR[31:24]
        expected_crc = calc_crc8(crc_bytes, 5);

        // Skip SOF + CMD + ADDR (6 bytes) to get CRC
        for (i = 0; i < 6; i++) begin
            dummy = fifo_pop();
        end
        frame_crc = fifo_pop();

        check_value("Frame CRC", {24'h0, frame_crc}, {24'h0, expected_crc});

        `uvm_info(get_type_name(),
            $sformatf("READ frame CRC = 0x%02X (expected 0x%02X)", frame_crc, expected_crc), UVM_LOW)

    endtask

endclass
