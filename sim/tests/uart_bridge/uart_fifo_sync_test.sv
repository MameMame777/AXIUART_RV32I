`timescale 1ns / 1ps

//==============================================================================
// FIFO Sync Unit Test
//==============================================================================
// Test ID: UART Bridge - Module Test 2
// Duration: ~10-15s
//
// Purpose:
//   Verify synchronous FIFO model (queue-based reference) with:
//   - Basic FIFO operations (write, read, order)
//   - Empty/full flag behavior
//   - Count accuracy
//
// Pass/Fail Criteria:
//   - All count and flag values match expected
//   - Correct FIFO ordering maintained
//==============================================================================

class uart_fifo_sync_test extends uart_bridge_base_test;

    `uvm_component_utils(uart_fifo_sync_test)

    function new(string name = "uart_fifo_sync_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info(get_type_name(), "UART FIFO Sync Unit Test configured", UVM_LOW)
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        `uvm_info(get_type_name(),
            "\n========================================\n  FIFO Sync Unit Test\n  Testing: Synchronous FIFO\n========================================",
            UVM_NONE)

        test_fifo_basic();
        test_fifo_flags();
        test_fifo_ordering();

        if (error_count == 0) begin
            report_test_pass("All FIFO tests passed");
        end else begin
            report_test_fail($sformatf("%0d FIFO errors detected", error_count));
        end

        phase.drop_objection(this);
    endtask

    //====================================================================
    // Test 1: FIFO Basic Operations
    //====================================================================

    virtual task test_fifo_basic();
        int i;
        logic [7:0] val;

        `uvm_info(get_type_name(), "TEST 1: FIFO Basic Operations", UVM_MEDIUM)

        fifo_clear();

        // Push 4 bytes
        for (i = 0; i < 4; i++) begin
            fifo_push(8'h10 + i);
        end

        check_value("Count after 4 pushes", fifo_size(), 4);

        // Pop all and verify
        for (i = 0; i < 4; i++) begin
            val = fifo_pop();
            check_value($sformatf("Pop[%0d]", i), {24'h0, val}, {24'h0, 8'h10 + i[7:0]});
        end

        check_value("Count after drain", fifo_size(), 0);

    endtask

    //====================================================================
    // Test 2: FIFO Flags
    //====================================================================

    virtual task test_fifo_flags();
        logic [7:0] dummy;

        `uvm_info(get_type_name(), "TEST 2: FIFO Flag Behavior", UVM_MEDIUM)

        fifo_clear();

        // Verify empty on init
        if (fifo_is_empty()) begin
            `uvm_info(get_type_name(), "PASS: FIFO empty on initialization", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "FAIL: FIFO not empty on initialization")
            error_count++;
        end

        // Push one byte
        fifo_push(8'hAA);
        if (!fifo_is_empty()) begin
            `uvm_info(get_type_name(), "PASS: FIFO not empty after push", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "FAIL: FIFO still empty after push")
            error_count++;
        end

        // Pop and verify empty
        dummy = fifo_pop();
        if (fifo_is_empty()) begin
            `uvm_info(get_type_name(), "PASS: FIFO empty after pop", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "FAIL: FIFO not empty after pop")
            error_count++;
        end

    endtask

    //====================================================================
    // Test 3: FIFO Ordering
    //====================================================================

    virtual task test_fifo_ordering();
        int i;
        logic [7:0] val;
        int order_ok;

        `uvm_info(get_type_name(), "TEST 3: FIFO Ordering (FIFO property)", UVM_MEDIUM)

        fifo_clear();
        order_ok = 1;

        // Push 16 bytes
        for (i = 0; i < 16; i++) begin
            fifo_push(i[7:0]);
        end

        check_value("Count after 16 pushes", fifo_size(), 16);

        // Pop and verify order
        for (i = 0; i < 16; i++) begin
            val = fifo_pop();
            if (val !== i[7:0]) begin
                `uvm_error(get_type_name(),
                    $sformatf("FAIL: FIFO order broken at index %0d (got 0x%02X, expected 0x%02X)",
                             i, val, i))
                error_count++;
                order_ok = 0;
            end
        end

        if (order_ok) begin
            `uvm_info(get_type_name(), "PASS: FIFO ordering correct for 16 entries", UVM_LOW)
        end

    endtask

endclass
