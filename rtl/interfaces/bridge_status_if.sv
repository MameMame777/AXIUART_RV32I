`timescale 1ns / 1ps

//
// bridge_status_if.sv - Bridge Status Interface
//
// This interface provides access to internal bridge status and state information
// for monitoring and verification purposes.
//

interface bridge_status_if (
    input logic clk,
    input logic rst_n
);

    // Frame parser state monitoring
    logic frame_parser_state_changed;
    logic [7:0] current_frame_parser_state;
    
    // FIFO status monitoring
    logic fifo_status_changed;
    logic [6:0] rx_fifo_count;       // 64-deep FIFO: 7-bit count
    logic [6:0] rx_fifo_depth;       // Fixed depth = 64
    logic [6:0] tx_fifo_count;       // 64-deep FIFO: 7-bit count  
    logic [6:0] tx_fifo_depth;       // Fixed depth = 64
    
    // Bridge internal state
    logic        bridge_busy;
    logic [7:0]  bridge_error;
    logic        system_ready;
    logic [7:0] bridge_state;
    logic [31:0] error_status;
    
    // Methods for state information
    function string get_frame_parser_state_name();
        case (current_frame_parser_state)
            8'h00: return "IDLE";
            8'h01: return "WAIT_START";
            8'h02: return "RECV_COMMAND";
            8'h03: return "RECV_ADDRESS";
            8'h04: return "RECV_LENGTH";
            8'h05: return "RECV_DATA";
            8'h06: return "RECV_CRC";
            8'h07: return "VALIDATE";
            8'h08: return "EXECUTE";
            8'h09: return "SEND_RESPONSE";
            8'h0A: return "ERROR";
            default: return "UNKNOWN";
        endcase
    endfunction
    
    // Initialize default values
    initial begin
        frame_parser_state_changed = 1'b0;
        current_frame_parser_state = 8'h00;
        fifo_status_changed = 1'b0;
        rx_fifo_count = 7'h00;
        rx_fifo_depth = 7'h40;  // 64 depth
        tx_fifo_count = 7'h00;
        tx_fifo_depth = 7'h40;  // 64 depth
        bridge_state = 8'h00;
        error_status = 32'h00;
    end
    
    // Modport for monitor access
    modport monitor (
        input clk, rst_n,
        input frame_parser_state_changed,
        input current_frame_parser_state,
        input fifo_status_changed,
        input rx_fifo_count, rx_fifo_depth,
        input tx_fifo_count, tx_fifo_depth,
        input bridge_busy,
        input bridge_error,
        input system_ready,
        input bridge_state, error_status,
        import get_frame_parser_state_name
    );
    
    // Modport for DUT connection
    modport dut (
        input clk, rst_n,
        output frame_parser_state_changed,
        output current_frame_parser_state,
        output fifo_status_changed,
        output rx_fifo_count, rx_fifo_depth,
        output tx_fifo_count, tx_fifo_depth,
        output bridge_busy,
        output bridge_error,
        output system_ready,
        output bridge_state, error_status
    );

endinterface
