`timescale 1ns / 1ps
//=====================================================================
// VexRiscv CPU Control Module
//=====================================================================
// Description:
//   Controls VexRiscv execution via UART register commands
//   - Run/Halt/Step control from Register_Block
//   - Auto-halt on EBREAK detection
//   - Reset pulse generation
//   - Status reporting (halted, break)
//
// Control Flow:
//   HALTED → (cpu_run) → RUNNING → (cpu_halt || ebreak) → HALTED
//                    ↘ (cpu_step) → STEPPING → HALTED
//
// Timing:
//   - cpu_run: Synchronous start (1 cycle)
//   - cpu_halt: Synchronous stop (1 cycle)
//   - cpu_step: Single instruction execution (not implemented, requires cycle counter)
//   - ebreak: Auto-halt on EBREAK detection (1 cycle)
//
// Author: GitHub Copilot (Claude Sonnet 4.5)
// Date: January 17, 2026
//=====================================================================

module vexriscv_control (
    input  logic clk,
    input  logic rst,
    
    //=================================================================
    // UART Control Signals (from Register_Block)
    //=================================================================
    input  logic cpu_run,        // Start CPU execution
    input  logic cpu_halt,       // Stop CPU execution
    input  logic cpu_step,       // Single-step execution (W1P)
    
    //=================================================================
    // Status Outputs (to Register_Block)
    //=================================================================
    output logic cpu_halted,     // CPU is halted
    output logic cpu_break,      // EBREAK detected
    
    //=================================================================
    // VexRiscv Control (to CPU)
    //=================================================================
    output logic cpu_reset,      // CPU reset (active high)
    output logic cpu_running,    // CPU is executing
    
    //=================================================================
    // EBREAK Detection (from vexriscv_ebreak_monitor)
    //=================================================================
    input  logic ebreak_detected,
    input  logic [31:0] break_pc,
    output logic clear_break     // Clear break flag
);

    //=================================================================
    // CPU State Machine
    //=================================================================
    
    typedef enum logic [2:0] {
        STATE_RESET,     // CPU reset active
        STATE_HALTED,    // CPU stopped, awaiting run command
        STATE_RUNNING,   // CPU executing instructions
        STATE_STEPPING,  // Single-step mode (future enhancement)
        STATE_BREAK      // EBREAK detected, auto-halted
    } cpu_state_t;
    
    cpu_state_t state, next_state;
    
    //=================================================================
    // State Register
    //=================================================================
    
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= STATE_RESET;
        end else begin
            state <= next_state;
        end
    end
    
    //=================================================================
    // Next State Logic
    //=================================================================
    
    always_comb begin
        next_state = state;
        
        case (state)
            STATE_RESET: begin
                // Hold reset for 2 cycles
                next_state = STATE_HALTED;
            end
            
            STATE_HALTED: begin
                if (cpu_run) begin
                    next_state = STATE_RUNNING;
                end else if (cpu_step) begin
                    next_state = STATE_STEPPING;
                end
            end
            
            STATE_RUNNING: begin
                if (cpu_halt) begin
                    next_state = STATE_HALTED;
                end else if (ebreak_detected) begin
                    next_state = STATE_BREAK;
                end
            end
            
            STATE_STEPPING: begin
                // TODO: Implement cycle counter for single-step
                // For now, execute one cycle then halt
                next_state = STATE_HALTED;
            end
            
            STATE_BREAK: begin
                // EBREAK detected, remain halted until run command
                if (cpu_run) begin
                    next_state = STATE_RUNNING;
                end else if (cpu_halt) begin
                    next_state = STATE_HALTED;
                end
            end
            
            default: begin
                next_state = STATE_RESET;
            end
        endcase
    end
    
    //=================================================================
    // Output Logic
    //=================================================================
    
    always_comb begin
        // Default values
        cpu_reset   = 1'b0;
        cpu_halted  = 1'b0;
        cpu_running = 1'b0;
        cpu_break   = 1'b0;
        clear_break = 1'b0;
        
        case (state)
            STATE_RESET: begin
                cpu_reset  = 1'b1;
                cpu_halted = 1'b1;
            end
            
            STATE_HALTED: begin
                cpu_halted = 1'b1;
            end
            
            STATE_RUNNING: begin
                cpu_running = 1'b1;
            end
            
            STATE_STEPPING: begin
                cpu_running = 1'b1;
            end
            
            STATE_BREAK: begin
                cpu_halted = 1'b1;
                cpu_break  = 1'b1;
            end
        endcase
    end
    
    //=================================================================
    // Clear Break Flag on Run/Halt Command
    //=================================================================
    
    always_ff @(posedge clk) begin
        if (rst) begin
            clear_break <= 1'b0;
        end else begin
            // Clear break flag when transitioning out of BREAK state
            clear_break <= (state == STATE_BREAK) && (cpu_run || cpu_halt);
        end
    end
    
    //=================================================================
    // Debug Logging (Simulation Only)
    //=================================================================
    
    `ifdef SIMULATION
    // State transition logging
    always_ff @(posedge clk) begin
        if (!rst && (state != next_state)) begin
            $display("[CPU_CONTROL] State transition: %s → %s", 
                     state.name(), next_state.name());
        end
    end
    
    // EBREAK detection logging
    always_ff @(posedge clk) begin
        if (!rst && ebreak_detected && (state == STATE_RUNNING)) begin
            $display("[CPU_CONTROL] EBREAK detected at PC=0x%08X, halting CPU", break_pc);
        end
    end
    
    // Command logging
    always_ff @(posedge clk) begin
        if (!rst) begin
            if (cpu_run && (state == STATE_HALTED || state == STATE_BREAK)) begin
                $display("[CPU_CONTROL] CPU_RUN command received");
            end
            if (cpu_halt && (state == STATE_RUNNING)) begin
                $display("[CPU_CONTROL] CPU_HALT command received");
            end
            if (cpu_step && (state == STATE_HALTED)) begin
                $display("[CPU_CONTROL] CPU_STEP command received (stepping not fully implemented)");
            end
        end
    end
    `endif

endmodule
