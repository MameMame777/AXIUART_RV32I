`timescale 1ns / 1ps

//==============================================================================
// RV32I Memory Access (MEM) Stage Module
//==============================================================================
// Combinational logic for load/store operations, byte alignment, MMIO decoding,
// and exception detection. Memory accesses are validated against address ranges.
//
// See: rtl/cpu/rv32i_mem_spec.md for detailed specification
//==============================================================================

module rv32i_mem
    import rv32i_isa_pkg::*;
    import rv32i_pipeline_pkg::*;
(
    // EX/MEM pipeline register inputs
    input  logic [31:0]   pc,
    input  logic [31:0]   insn,
    input  logic [31:0]   alu_result,      // Memory address
    input  logic [1:0]    byte_offset,     // Address LSBs delayed by 1 cycle (synchronized with BRAM latency)
    input  logic [31:0]   rs2_data,        // Store data
    input  logic [31:0]   csr_rdata,
    input  decode_ctrl_t  ctrl,
    input  logic          valid,
    
    // Debug mode control
    input  logic          debug_mode_enable,
    
    // MEM stall signal (hold ctrl_final during LOAD wait)
    input  logic          mem_stall,
    
    // Data RAM interface (Port B)
    output logic [10:0]   data_ram_addr,
    output logic [31:0]   data_ram_wdata,
    output logic [3:0]    data_ram_we,
    input  logic [31:0]   data_ram_rdata,
    
    // MMIO LED register
    output logic [3:0]    led_out,
    input  logic          clk,
    input  logic          rst,
    
    // Exception interface
    output logic          exception_trap,
    output logic [31:0]   exception_pc,
    output logic [3:0]    exception_code,
    output logic [31:0]   exception_tval,
    
    // Outputs to MEM/WB register
    output logic [31:0]   mem_data_out,
    output logic          valid_out,
    output decode_ctrl_t  ctrl_out
);

    localparam logic [31:0] LED_ADDR = 32'h0000_407C;
    
    //==========================================================================
    // Address Decode
    //==========================================================================
    logic [31:0] mem_addr;
    logic        is_ram_access;
    logic        is_mmio_led;
    logic        is_invalid_addr;
    
    assign mem_addr = alu_result;
    
    assign is_ram_access   = (mem_addr < 32'h0000_2000);  // 0x0000-0x1FFF (8KB)
    assign is_mmio_led     = (mem_addr == LED_ADDR);
    assign is_invalid_addr = !is_ram_access && !is_mmio_led;
    
    //==========================================================================
    // Load Data Processing - Registered Output Synchronized with BRAM
    //==========================================================================
    // BRAM registered output timing:
    // Cycle N:   LOAD in MEM, ram_addr_b sent, ctrl/byte_offset captured
    // Cycle N+1: Next insn in MEM, ram_rdata_raw updated at clock edge
    //            → Combinational logic evaluates BEFORE edge (uses old data!)
    //            → Solution: Register load_data_aligned output
    //            → Processing happens AFTER edge when BRAM data is stable ✓
    //
    // Key: Delay ctrl by 1 cycle, then register the output processing
    
    // CRITICAL FIX: Hold ctrl during mem_stall ONLY for LOAD instructions
    // Problem: When mem_stall=1, the EX/MEM register is held. The NEXT
    // instruction's ctrl would contaminate the current LOAD's rd_addr.
    // Solution: 
    //   - LOAD instructions: Use registered ctrl_held when mem_stall=1
    //   - Other instructions: Pass ctrl directly (no delay) via combinational path
    logic [1:0]       byte_offset_held;
    decode_ctrl_t     ctrl_held;
    logic             valid_held;
    
    // Hold registers - capture LOAD instruction's ctrl on first cycle
    always_ff @(posedge clk) begin
        if (rst) begin
            byte_offset_held          <= 2'b00;
            valid_held                <= 1'b0;
            // Initialize ctrl_held struct with proper enum types
            ctrl_held.rf_wen          <= 1'b0;
            ctrl_held.rd_addr         <= 5'h00;
            ctrl_held.rs1_addr        <= 5'h00;
            ctrl_held.rs2_addr        <= 5'h00;
            ctrl_held.alu_src1_pc     <= 1'b0;
            ctrl_held.alu_src2_imm    <= 1'b0;
            ctrl_held.alu_op          <= ALU_ADD;
            ctrl_held.mem_read        <= 1'b0;
            ctrl_held.mem_write       <= 1'b0;
            ctrl_held.mem_width       <= MEM_WORD;
            ctrl_held.mem_sign_ext    <= 1'b0;
            ctrl_held.is_branch       <= 1'b0;
            ctrl_held.is_jump         <= 1'b0;
            ctrl_held.is_jalr         <= 1'b0;
            ctrl_held.branch_op       <= BR_EQ;
            ctrl_held.wb_src          <= WB_ALU;
            ctrl_held.is_ecall        <= 1'b0;
            ctrl_held.is_ebreak       <= 1'b0;
            ctrl_held.is_fence        <= 1'b0;
            ctrl_held.is_mret         <= 1'b0;
            ctrl_held.is_csr          <= 1'b0;
            ctrl_held.csr_op          <= CSR_RW;
            ctrl_held.csr_addr        <= 12'h000;
            ctrl_held.csr_imm_mode    <= 1'b0;
            ctrl_held.immediate       <= 32'h00000000;
            ctrl_held.illegal         <= 1'b0;
        end else if (ctrl.mem_read && !mem_stall) begin
            // Capture LOAD instruction's ctrl on first cycle (when mem_stall=0)
            byte_offset_held <= byte_offset;
            ctrl_held        <= ctrl;
            valid_held       <= valid;
        end
    end
    
    // Output selection - combinational for non-LOAD, held value during LOAD stall
    logic [1:0]       byte_offset_final;
    decode_ctrl_t     ctrl_final;
    logic             valid_final;
    
    assign byte_offset_final = mem_stall ? byte_offset_held : byte_offset;
    assign ctrl_final        = mem_stall ? ctrl_held : ctrl;
    assign valid_final       = mem_stall ? valid_held : valid;
    
    // Extract byte/halfword (combinational, for registered output below)
    logic [7:0]  load_byte;
    logic [15:0] load_halfword;
    logic [31:0] load_word;
    
    always_comb begin
        case (byte_offset_final)
            2'b00: load_byte = data_ram_rdata[7:0];
            2'b01: load_byte = data_ram_rdata[15:8];
            2'b10: load_byte = data_ram_rdata[23:16];
            2'b11: load_byte = data_ram_rdata[31:24];
        endcase
        
        case (byte_offset_final[1])
            1'b0: load_halfword = data_ram_rdata[15:0];
            1'b1: load_halfword = data_ram_rdata[31:16];
        endcase
        
        load_word = data_ram_rdata;
    end
    
    // Sign/zero extension (combinational)
    logic [31:0] load_data_aligned;
    
    always_comb begin
        case (ctrl_final.mem_width)
            MEM_BYTE: begin
                load_data_aligned = ctrl_final.mem_sign_ext ? 
                                   {{24{load_byte[7]}}, load_byte} : 
                                   {24'h0, load_byte};
            end
            MEM_HALF: begin
                load_data_aligned = ctrl_final.mem_sign_ext ? 
                                   {{16{load_halfword[15]}}, load_halfword} : 
                                   {16'h0, load_halfword};
            end
            MEM_WORD: begin
                load_data_aligned = load_word;
            end
            default: load_data_aligned = data_ram_rdata;
        endcase
    end
    
    //==========================================================================
    // Load Data Output (combinational from registered BRAM + delayed controls)
    //==========================================================================
    // BRAM registered output (ram_rdata_raw) + ctrl_final (2-cycle delayed) = correct timing
    // mem_data_out can be combinational because all its inputs are already registered
    assign mem_data_out = load_data_aligned;
    assign valid_out = valid_final;
    assign ctrl_out = ctrl_final;
    
    // Debug: Monitor LOAD operations  
    always @(posedge clk) begin
        if (ctrl_final.mem_read && valid_final) begin
            $display("[LOAD_DEBUG] Time=%0t PC=0x%08h data_ram_rdata=0x%08h load_data_aligned=0x%08h mem_data_out=0x%08h mem_width=%0d byte_offset=%0d",
                     $time, pc, data_ram_rdata, load_data_aligned, mem_data_out, ctrl_final.mem_width, byte_offset_final);
        end
    end
    
    //==========================================================================
    // Store Data Alignment and Write Enables
    //==========================================================================
    logic [31:0] store_data_aligned;
    logic [3:0]  byte_write_enables;
    
    always_comb begin
        store_data_aligned = 32'h0;
        byte_write_enables = 4'b0000;
        
        if (ctrl.mem_write && valid) begin
            case (ctrl.mem_width)
                MEM_BYTE: begin
                    store_data_aligned = {4{rs2_data[7:0]}};  // Replicate to all lanes
                    case (byte_offset)
                        2'b00: byte_write_enables = 4'b0001;
                        2'b01: byte_write_enables = 4'b0010;
                        2'b10: byte_write_enables = 4'b0100;
                        2'b11: byte_write_enables = 4'b1000;
                    endcase
                end
                
                MEM_HALF: begin
                    store_data_aligned = {2{rs2_data[15:0]}};  // Replicate to both halfwords
                    case (byte_offset[1])
                        1'b0: byte_write_enables = 4'b0011;
                        1'b1: byte_write_enables = 4'b1100;
                    endcase
                end
                
                MEM_WORD: begin
                    store_data_aligned  = rs2_data;
                    byte_write_enables = 4'b1111;
                end
                
                default: begin
                    store_data_aligned  = rs2_data;
                    byte_write_enables = 4'b0000;
                end
            endcase
        end
    end
    
    // RAM outputs (no write when accessing MMIO)
    assign data_ram_addr  = mem_addr[12:2];  // Word address
    assign data_ram_wdata = store_data_aligned;
    assign data_ram_we    = is_ram_access ? byte_write_enables : 4'b0000;
    
    //==========================================================================
    // MMIO LED Register
    //==========================================================================
    logic [3:0] led_reg;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            led_reg <= 4'h0;
        end else begin
            if (valid && ctrl.mem_write && is_mmio_led) begin
                led_reg <= rs2_data[3:0];
                $display("[%0t] LED WRITE: addr=0x%08X, data=0x%X, valid=%b, mem_write=%b, is_mmio_led=%b",
                         $time, mem_addr, rs2_data[3:0], valid, ctrl.mem_write, is_mmio_led);
            end else if (valid && ctrl.mem_write) begin
                $display("[%0t] MEM WRITE (not LED): addr=0x%08X, data=0x%08X, is_mmio_led=%b, is_ram=%b",
                         $time, mem_addr, rs2_data, is_mmio_led, is_ram_access);
            end
        end
    end
    
    assign led_out = led_reg;
    
    //==========================================================================
    // Exception Detection
    //==========================================================================
    logic misaligned_load, misaligned_store;
    logic load_fault, store_fault;
    
    // Misalignment detection
    always_comb begin
        case (ctrl.mem_width)
            MEM_BYTE: begin
                misaligned_load  = 1'b0;  // Bytes always aligned
                misaligned_store = 1'b0;
            end
            MEM_HALF: begin
                misaligned_load  = (mem_addr[0] != 1'b0) && ctrl.mem_read;
                misaligned_store = (mem_addr[0] != 1'b0) && ctrl.mem_write;
            end
            MEM_WORD: begin
                misaligned_load  = (mem_addr[1:0] != 2'b00) && ctrl.mem_read;
                misaligned_store = (mem_addr[1:0] != 2'b00) && ctrl.mem_write;
            end
            default: begin
                misaligned_load  = 1'b0;
                misaligned_store = 1'b0;
            end
        endcase
    end
    
    // Access fault detection
    assign load_fault  = is_invalid_addr && ctrl.mem_read;
    assign store_fault = is_invalid_addr && ctrl.mem_write;
    
    // Exception aggregation
    always_comb begin
        exception_trap = 1'b0;
        exception_code = 4'h0;
        exception_pc   = pc;
        exception_tval = mem_addr;
        
        if (valid) begin
            if (ctrl.is_ebreak) begin
                // In debug mode, EBREAK stops CPU instead of generating exception
                // In normal mode, EBREAK generates exception trap (RISC-V standard)
                if (!debug_mode_enable) begin
                    exception_trap = 1'b1;
                    exception_code = 4'h3;  // Breakpoint
                end
            end else if (ctrl.is_ecall) begin
                exception_trap = 1'b1;
                exception_code = 4'hB;  // Environment call (M-mode)
            end else if (misaligned_load) begin
                exception_trap = 1'b1;
                exception_code = 4'h4;  // Load address misaligned
            end else if (load_fault) begin
                exception_trap = 1'b1;
                exception_code = 4'h5;  // Load access fault
            end else if (misaligned_store) begin
                exception_trap = 1'b1;
                exception_code = 4'h6;  // Store address misaligned
            end else if (store_fault) begin
                exception_trap = 1'b1;
                exception_code = 4'h7;  // Store access fault
            end else if (ctrl.illegal) begin
                exception_trap = 1'b1;
                exception_code = 4'h2;  // Illegal instruction
            end
        end
    end
    
endmodule : rv32i_mem
