`timescale 1ns / 1ps
//=====================================================================
// VexRiscv Debug Bridge
//=====================================================================
// Description:
//   Bridges Register_Block simple commands to VexRiscv DebugPlugin
//   bus protocol.
//
//   DebugPlugin registers:
//   - 0x00: Breakpoint 0 address
//   - 0x04: Breakpoint 0 control
//   - 0x08: Breakpoint 1 address
//   - 0x0C: Breakpoint 1 control
//   - 0x10: CPU control (halt, resume, step, reset)
//   - 0x14: CPU status (halted, break, etc.)
//   - 0x18: PC read/write
//   - 0x1C: Instruction inject
//
// Interface:
//   - reg_*: Simple register interface from Register_Block
//   - debug_*: VexRiscv DebugPlugin bus interface
//
// Author: GitHub Copilot (Claude Opus 4.5)
// Date: February 6, 2026
//=====================================================================

module vexriscv_debug_bridge (
    input  logic        clk,
    input  logic        rst,
    
    //=================================================================
    // Register Block Interface (simple commands)
    //=================================================================
    input  logic        reg_cpu_run,         // Start CPU execution
    input  logic        reg_cpu_halt,        // Stop CPU execution
    input  logic        reg_cpu_reset,       // Reset CPU
    output logic        reg_cpu_halted,      // CPU is halted
    output logic        reg_debug_resetOut,  // CPU requested reset
    
    // Breakpoint registers (optional)
    input  logic        reg_bp0_enable,
    input  logic [31:0] reg_bp0_address,
    input  logic        reg_bp1_enable,
    input  logic [31:0] reg_bp1_address,
    
    //=================================================================
    // VexRiscv DebugPlugin Bus Interface
    //=================================================================
    output logic        debug_bus_cmd_valid,
    input  logic        debug_bus_cmd_ready,
    output logic        debug_bus_cmd_payload_wr,
    output logic [7:0]  debug_bus_cmd_payload_address,
    output logic [31:0] debug_bus_cmd_payload_data,
    input  logic [31:0] debug_bus_rsp_data,
    input  logic        debug_resetOut
);

    //=================================================================
    // Debug Command FSM
    //=================================================================
    
    typedef enum logic [2:0] {
        IDLE,
        SEND_HALT,
        SEND_RESUME,
        SEND_RESET,
        WAIT_RSP
    } debug_state_t;
    
    debug_state_t state, next_state;
    
    // Debug register addresses (from VexRiscv DebugPlugin)
    // Address[7:2] is used as case selector, so:
    // - 6'h00 = byte address 0x00 = Control/Status register
    // - 6'h10 = byte address 0x40 = Breakpoint 0
    // - 6'h11 = byte address 0x44 = Breakpoint 1
    localparam logic [7:0] DBG_CTRL = 8'h00;  // Control register (address[7:2] = 6'h0)
    localparam logic [7:0] DBG_STAT = 8'h00;  // Status register (same as CTRL for reads)
    
    // Control bits for write to address 0x00:
    // Bit 4:  stepIt
    // Bit 16: set resetIt
    // Bit 17: set haltIt
    // Bit 18: set disableEbreak
    // Bit 24: clear resetIt
    // Bit 25: clear haltIt (also clears haltedByBreak, godmode)
    // Bit 26: clear disableEbreak
    localparam logic [31:0] CTRL_HALT   = 32'h0002_0000;  // Bit 17: Set haltIt
    localparam logic [31:0] CTRL_RESUME = 32'h0200_0000;  // Bit 25: Clear haltIt
    localparam logic [31:0] CTRL_RESET  = 32'h0001_0000;  // Bit 16: Set resetIt
    
    //=================================================================
    // State Register
    //=================================================================
    
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    //=================================================================
    // Next State Logic
    //=================================================================
    
    logic cmd_pending;
    logic [31:0] cmd_data;
    
    always_comb begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (reg_cpu_halt) begin
                    next_state = SEND_HALT;
                end else if (reg_cpu_run) begin
                    next_state = SEND_RESUME;
                end else if (reg_cpu_reset) begin
                    next_state = SEND_RESET;
                end
            end
            
            SEND_HALT, SEND_RESUME, SEND_RESET: begin
                if (debug_bus_cmd_ready) begin
                    next_state = WAIT_RSP;
                end
            end
            
            WAIT_RSP: begin
                // One cycle for command completion
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    //=================================================================
    // Debug Bus Command Output
    //=================================================================
    
    always_comb begin
        debug_bus_cmd_valid           = 1'b0;
        debug_bus_cmd_payload_wr      = 1'b1;
        debug_bus_cmd_payload_address = DBG_CTRL;
        debug_bus_cmd_payload_data    = 32'h0;
        
        case (state)
            SEND_HALT: begin
                debug_bus_cmd_valid        = 1'b1;
                debug_bus_cmd_payload_data = CTRL_HALT;
            end
            
            SEND_RESUME: begin
                debug_bus_cmd_valid        = 1'b1;
                debug_bus_cmd_payload_data = CTRL_RESUME;
            end
            
            SEND_RESET: begin
                debug_bus_cmd_valid        = 1'b1;
                debug_bus_cmd_payload_data = CTRL_RESET;
            end
            
            default: begin
                // No command
            end
        endcase
    end
    
    //=================================================================
    // Status Outputs
    //=================================================================
    
    // CPU halted status from debug response
    // Note: This is a simplification - proper implementation would
    // poll the status register periodically
    logic halted_reg;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            halted_reg <= 1'b1;  // Start halted
        end else begin
            case (state)
                SEND_HALT: begin
                    if (debug_bus_cmd_ready) begin
                        halted_reg <= 1'b1;
                    end
                end
                SEND_RESUME: begin
                    if (debug_bus_cmd_ready) begin
                        halted_reg <= 1'b0;
                    end
                end
                default: begin
                    // Maintain state
                end
            endcase
        end
    end
    
    assign reg_cpu_halted     = halted_reg;
    assign reg_debug_resetOut = debug_resetOut;
    
    //=================================================================
    // Debug Logging (Simulation Only)
    //=================================================================
    
    `ifdef SIMULATION
    always_ff @(posedge clk) begin
        if (!rst && debug_bus_cmd_valid && debug_bus_cmd_ready) begin
            $display("[DEBUG_BRIDGE] Command: addr=0x%02X data=0x%08X wr=%b",
                     debug_bus_cmd_payload_address,
                     debug_bus_cmd_payload_data,
                     debug_bus_cmd_payload_wr);
        end
    end
    `endif

endmodule
