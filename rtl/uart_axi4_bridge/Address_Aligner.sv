`timescale 1ns / 1ps

// Address Aligner Module for UART-AXI4 Bridge
// Validates address alignment and generates WSTRB based on SIZE and ADDR
module Address_Aligner (
    input  logic [31:0] addr,           // Input address
    input  logic [1:0]  size,           // Size: 00=8-bit, 01=16-bit, 10=32-bit, 11=reserved
    output logic        addr_ok,        // Address alignment is valid
    output logic [3:0]  wstrb,          // Write strobe for AXI4-Lite
    output logic [2:0]  status_code     // Error status code if alignment fails
);

    // Status codes from protocol specification (Section 3)
    localparam [2:0] STATUS_OK        = 3'h0;  // 0x00
    localparam [2:0] STATUS_CMD_INV   = 3'h2;  // 0x02 - Invalid command (reserved SIZE)
    localparam [2:0] STATUS_ADDR_ALIGN = 3'h3; // 0x03 - Address alignment error

    // Address alignment and WSTRB generation
    always_comb begin
        addr_ok = 1'b0;
        wstrb = 4'b0000;
        status_code = STATUS_CMD_INV;

        unique case (size)
            2'b00: begin  // 8-bit access
                // Any address is valid for 8-bit access
                wstrb = 4'b0001 << addr[1:0];
                addr_ok = 1'b1;
                status_code = STATUS_OK;
            end
            
            2'b01: begin  // 16-bit access
                // Address must be 16-bit aligned (addr[0] == 0)
                if (addr[0] == 1'b0) begin
                    wstrb = addr[1] ? 4'b1100 : 4'b0011;
                    addr_ok = 1'b1;
                    status_code = STATUS_OK;
                end else begin
                    wstrb = 4'b0000;
                    addr_ok = 1'b0;
                    status_code = STATUS_ADDR_ALIGN;
                end
            end
            
            2'b10: begin  // 32-bit access
                // Address must be 32-bit aligned (addr[1:0] == 00)
                if (addr[1:0] == 2'b00) begin
                    wstrb = 4'b1111;
                    addr_ok = 1'b1;
                    status_code = STATUS_OK;
                end else begin
                    wstrb = 4'b0000;
                    addr_ok = 1'b0;
                    status_code = STATUS_ADDR_ALIGN;
                end
            end
            
            2'b11: begin  // Reserved size
                wstrb = 4'b0000;
                addr_ok = 1'b0;
                status_code = STATUS_CMD_INV;
            end
            default: begin
                wstrb = 4'b0000;
                addr_ok = 1'b0;
                status_code = STATUS_CMD_INV;
            end
        endcase
    end

    // Assertions for verification
    `ifdef ENABLE_ADDRESS_ALIGNER_ASSERTIONS
        // WSTRB should be zero when address is not OK
        assert_wstrb_zero_when_not_ok: assert property (
            !addr_ok |-> (wstrb == 4'b0000)
        ) else $error("Address_Aligner: WSTRB not zero when addr_ok is false");

        // WSTRB should be non-zero when address is OK
        assert_wstrb_nonzero_when_ok: assert property (
            addr_ok |-> (wstrb != 4'b0000)
        ) else $error("Address_Aligner: WSTRB is zero when addr_ok is true");

        // Status code should be OK when address is OK
        assert_status_ok_when_addr_ok: assert property (
            addr_ok |-> (status_code == STATUS_OK)
        ) else $error("Address_Aligner: Status not OK when addr_ok is true");

        // 8-bit access should always be OK
        assert_8bit_always_ok: assert property (
            (size == 2'b00) |-> addr_ok
        ) else $error("Address_Aligner: 8-bit access should always be valid");

        // 16-bit access alignment check
        assert_16bit_alignment: assert property (
            (size == 2'b01) |-> (addr_ok == !addr[0])
        ) else $error("Address_Aligner: 16-bit alignment check failed");

        // 32-bit access alignment check
        assert_32bit_alignment: assert property (
            (size == 2'b10) |-> (addr_ok == (addr[1:0] == 2'b00))
        ) else $error("Address_Aligner: 32-bit alignment check failed");

        // Reserved size should never be OK
        assert_reserved_size_not_ok: assert property (
            (size == 2'b11) |-> !addr_ok
        ) else $error("Address_Aligner: Reserved size should not be valid");
    `endif

endmodule
