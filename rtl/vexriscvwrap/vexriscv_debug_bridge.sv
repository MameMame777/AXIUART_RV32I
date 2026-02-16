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
    input  logic        reg_cpu_step,        // Single-step pulse
    input  logic        reg_cpu_reset,       // Reset CPU
    output logic        reg_cpu_halted,      // CPU is halted
    output logic        reg_debug_resetOut,  // CPU requested reset
    
    // Breakpoint registers (4 external slots, 2 hardware slots in core)
    input  logic [3:0]  reg_bp_enable,
    input  logic [31:0] reg_bp_address [0:3],
    
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

    // Debug register addresses (from VexRiscv DebugPlugin)
    localparam logic [7:0] DBG_CTRL = 8'h00;
    localparam logic [7:0] DBG_BP0  = 8'h40;
    localparam logic [7:0] DBG_BP1  = 8'h44;
    
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

    // Control bit for stepIt
    localparam logic [31:0] CTRL_STEP   = 32'h0000_0010;  // Bit 4: stepIt

    typedef enum logic [2:0] {
        CMD_NONE,
        CMD_BP0,
        CMD_BP1,
        CMD_HALT,
        CMD_RESUME,
        CMD_STEP,
        CMD_RESET
    } debug_cmd_t;

    debug_cmd_t pending_cmd;

    logic prev_cpu_run;
    logic prev_cpu_halt;
    logic prev_cpu_step;
    logic prev_cpu_reset;

    logic [3:0]  bp_enable_shadow;
    logic [31:0] bp_addr_shadow [0:3];

    logic run_edge;
    logic halt_edge;
    logic step_edge;
    logic reset_edge;
    logic bp0_update_pending;
    logic bp1_update_pending;

    assign run_edge = reg_cpu_run && !prev_cpu_run;
    assign halt_edge = reg_cpu_halt && !prev_cpu_halt;
    assign step_edge = reg_cpu_step && !prev_cpu_step;
    assign reset_edge = reg_cpu_reset && !prev_cpu_reset;

    assign bp0_update_pending = (bp_enable_shadow[0] != reg_bp_enable[0]) ||
                                (bp_addr_shadow[0] != reg_bp_address[0]);
    assign bp1_update_pending = (bp_enable_shadow[1] != reg_bp_enable[1]) ||
                                (bp_addr_shadow[1] != reg_bp_address[1]);

    always_comb begin
        pending_cmd = CMD_NONE;
        if (bp0_update_pending) begin
            pending_cmd = CMD_BP0;
        end else if (bp1_update_pending) begin
            pending_cmd = CMD_BP1;
        end else if (halt_edge) begin
            pending_cmd = CMD_HALT;
        end else if (run_edge) begin
            pending_cmd = CMD_RESUME;
        end else if (step_edge) begin
            pending_cmd = CMD_STEP;
        end else if (reset_edge) begin
            pending_cmd = CMD_RESET;
        end
    end

    always_comb begin
        debug_bus_cmd_valid           = (pending_cmd != CMD_NONE);
        debug_bus_cmd_payload_wr      = 1'b1;
        debug_bus_cmd_payload_address = DBG_CTRL;
        debug_bus_cmd_payload_data    = 32'h0000_0000;

        case (pending_cmd)
            CMD_BP0: begin
                debug_bus_cmd_payload_address = DBG_BP0;
                debug_bus_cmd_payload_data = {reg_bp_address[0][31:1], reg_bp_enable[0]};
            end
            CMD_BP1: begin
                debug_bus_cmd_payload_address = DBG_BP1;
                debug_bus_cmd_payload_data = {reg_bp_address[1][31:1], reg_bp_enable[1]};
            end
            CMD_HALT: begin
                debug_bus_cmd_payload_data = CTRL_HALT;
            end
            CMD_RESUME: begin
                debug_bus_cmd_payload_data = CTRL_RESUME;
            end
            CMD_STEP: begin
                debug_bus_cmd_payload_data = CTRL_STEP;
            end
            CMD_RESET: begin
                debug_bus_cmd_payload_data = CTRL_RESET;
            end
            default: begin
            end
        endcase
    end
    
    //=================================================================
    // Status Outputs
    //=================================================================
    
    logic halted_reg;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            prev_cpu_run <= 1'b0;
            prev_cpu_halt <= 1'b0;
            prev_cpu_step <= 1'b0;
            prev_cpu_reset <= 1'b0;
            bp_enable_shadow <= 4'b0000;
            bp_addr_shadow[0] <= 32'h0;
            bp_addr_shadow[1] <= 32'h0;
            bp_addr_shadow[2] <= 32'h0;
            bp_addr_shadow[3] <= 32'h0;
            halted_reg <= 1'b1;  // Start halted
        end else begin
            prev_cpu_run <= reg_cpu_run;
            prev_cpu_halt <= reg_cpu_halt;
            prev_cpu_step <= reg_cpu_step;
            prev_cpu_reset <= reg_cpu_reset;

            if (debug_bus_cmd_valid && debug_bus_cmd_ready) begin
                case (pending_cmd)
                    CMD_BP0: begin
                        bp_enable_shadow[0] <= reg_bp_enable[0];
                        bp_addr_shadow[0] <= reg_bp_address[0];
                    end
                    CMD_BP1: begin
                        bp_enable_shadow[1] <= reg_bp_enable[1];
                        bp_addr_shadow[1] <= reg_bp_address[1];
                    end
                    CMD_HALT: begin
                        halted_reg <= 1'b1;
                    end
                    CMD_RESUME: begin
                        halted_reg <= 1'b0;
                    end
                    CMD_STEP: begin
                        halted_reg <= 1'b1;
                    end
                    default: begin
                    end
                endcase
            end
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
