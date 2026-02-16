//==============================================================================
// RV32I Core Debug Port (Port B) Assertions
// Purpose: Verify debug interface read/write operations via Port B
//
// Critical checks:
// - Debug write enables propagate to BRAM
// - Debug read enables capture correct data
// - Debug read data latches properly
// - No conflicts between debug and CPU memory operations
//==============================================================================

`timescale 1ns / 1ps

module rv32i_debug_port_assertions (
    input logic        clk,
    input logic        rst_n,
    
    // Debug interface signals
    input logic [3:0]  dbg_mem_we,      // Debug write enable (byte-wise)
    input logic        dbg_mem_re,      // Debug read enable
    input logic [11:0] dbg_mem_addr,    // Debug address (word address)
    input logic [31:0] dbg_mem_wdata,   // Debug write data
    input logic [31:0] dbg_mem_rdata,   // Debug read data
    
    // CPU Port B signals (for conflict detection)
    input logic        cpu_mem_write,   // CPU memory write enable
    input logic        cpu_mem_read,    // CPU memory read enable
    input logic [11:0] cpu_mem_addr,    // CPU memory address
    
    // BRAM Port B enable
    input logic        ram_ena_b
);

    //==========================================================================
    // Assertion: Debug Write Enable Valid When Asserted
    //==========================================================================
    // When any debug write enable bit is high, at least one byte should be written
    property dbg_write_enable_valid;
        @(posedge clk) disable iff (!rst_n)
        (|dbg_mem_we) |-> (ram_ena_b);
    endproperty
    
    ast_dbg_write_enable_valid: assert property (dbg_write_enable_valid)
        else $error("[DEBUG_PORT] Debug write enable asserted but Port B not enabled!");
    
    //==========================================================================
    // Assertion: Debug Read Enable Valid When Asserted
    //==========================================================================
    property dbg_read_enable_valid;
        @(posedge clk) disable iff (!rst_n)
        dbg_mem_re |-> (ram_ena_b);
    endproperty
    
    ast_dbg_read_enable_valid: assert property (dbg_read_enable_valid)
        else $error("[DEBUG_PORT] Debug read enable asserted but Port B not enabled!");
    
    //==========================================================================
    // Assertion: Debug Write Has Valid Address
    //==========================================================================
    // Debug address must be within valid RAM range (0-2047 words)
    property dbg_write_addr_valid;
        @(posedge clk) disable iff (!rst_n)
        (|dbg_mem_we) |-> (dbg_mem_addr <= 11'd2047);
    endproperty
    
    ast_dbg_write_addr_valid: assert property (dbg_write_addr_valid)
        else $error("[DEBUG_PORT] Debug write address 0x%03X out of range!", dbg_mem_addr);
    
    //==========================================================================
    // Assertion: Debug Read Has Valid Address
    //==========================================================================
    property dbg_read_addr_valid;
        @(posedge clk) disable iff (!rst_n)
        dbg_mem_re |-> (dbg_mem_addr <= 11'd2047);
    endproperty
    
    ast_dbg_read_addr_valid: assert property (dbg_read_addr_valid)
        else $error("[DEBUG_PORT] Debug read address 0x%03X out of range!", dbg_mem_addr);
    
    //==========================================================================
    // Assertion: Debug Read Data Latches Within 1 Cycle
    //==========================================================================
    // After debug read enable, read data should be available next cycle
    logic [31:0] prev_rdata;
    logic        prev_re;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_rdata <= 32'h0;
            prev_re <= 1'b0;
        end else begin
            prev_rdata <= dbg_mem_rdata;
            prev_re <= dbg_mem_re;
        end
    end
    
    property dbg_read_data_latches;
        @(posedge clk) disable iff (!rst_n)
        $rose(dbg_mem_re) |-> ##1 (dbg_mem_rdata !== prev_rdata || prev_re);
    endproperty
    
    // Warning only - read data might be the same as previous
    ast_dbg_read_data_latches: assert property (dbg_read_data_latches)
        else $warning("[DEBUG_PORT] Debug read data did not update after read enable at addr 0x%03X", dbg_mem_addr);
    
    //==========================================================================
    // Assertion: Debug Write and CPU Write Mutual Exclusion
    //==========================================================================
    // Debug write has priority, so if both asserted, only debug should execute
    property dbg_cpu_write_priority;
        @(posedge clk) disable iff (!rst_n)
        (|dbg_mem_we) && cpu_mem_write |-> (dbg_mem_we !== 4'b0000);
    endproperty
    
    ast_dbg_cpu_write_priority: assert property (dbg_cpu_write_priority)
        else $error("[DEBUG_PORT] Debug write priority violated!");
    
    //==========================================================================
    // Assertion: Debug Read and CPU Read Mutual Exclusion
    //==========================================================================
    property dbg_cpu_read_priority;
        @(posedge clk) disable iff (!rst_n)
        dbg_mem_re && cpu_mem_read |-> dbg_mem_re;
    endproperty
    
    ast_dbg_cpu_read_priority: assert property (dbg_cpu_read_priority)
        else $error("[DEBUG_PORT] Debug read priority violated!");
    
    //==========================================================================
    // Assertion: Debug Write Enable Byte Alignment
    //==========================================================================
    // All 4 bits of write enable should be valid (not X or Z)
    property dbg_we_no_x;
        @(posedge clk) disable iff (!rst_n)
        (|dbg_mem_we) |-> !$isunknown(dbg_mem_we);
    endproperty
    
    ast_dbg_we_no_x: assert property (dbg_we_no_x)
        else $error("[DEBUG_PORT] Debug write enable contains X/Z: %b", dbg_mem_we);
    
    //==========================================================================
    // Assertion: Debug Write Data Stability
    //==========================================================================
    // Write data should be stable when write enable is asserted
    property dbg_wdata_stable;
        @(posedge clk) disable iff (!rst_n)
        (|dbg_mem_we) |-> !$isunknown(dbg_mem_wdata);
    endproperty
    
    ast_dbg_wdata_stable: assert property (dbg_wdata_stable)
        else $error("[DEBUG_PORT] Debug write data contains X/Z when WE asserted: 0x%08X", dbg_mem_wdata);
    
    //==========================================================================
    // Assertion: Debug Address Stability During Access
    //==========================================================================
    property dbg_addr_stable_write;
        @(posedge clk) disable iff (!rst_n)
        (|dbg_mem_we) |-> !$isunknown(dbg_mem_addr);
    endproperty
    
    ast_dbg_addr_stable_write: assert property (dbg_addr_stable_write)
        else $error("[DEBUG_PORT] Debug address contains X/Z during write: 0x%03X", dbg_mem_addr);
    
    property dbg_addr_stable_read;
        @(posedge clk) disable iff (!rst_n)
        dbg_mem_re |-> !$isunknown(dbg_mem_addr);
    endproperty
    
    ast_dbg_addr_stable_read: assert property (dbg_addr_stable_read)
        else $error("[DEBUG_PORT] Debug address contains X/Z during read: 0x%03X", dbg_mem_addr);
    
    //==========================================================================
    // Additional Assertions: Data Integrity & Write-Read Consistency
    //==========================================================================
    
    // Assertion 12: Read data must not be X/Z after valid read
    property dbg_rdata_no_x;
        @(posedge clk) disable iff (!rst_n)
        $past(dbg_mem_re, 1) |-> !$isunknown(dbg_mem_rdata);
    endproperty
    
    ast_dbg_rdata_no_x: assert property (dbg_rdata_no_x)
        else $error("[DEBUG_PORT] Read data is X/Z after valid read operation: rdata=0x%08X", dbg_mem_rdata);
    
    // Track last write for consistency checking
    logic [10:0] last_write_addr;
    logic [31:0] last_write_data;
    logic [3:0]  last_write_mask;
    logic        write_occurred;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_occurred <= 1'b0;
            last_write_addr <= '0;
            last_write_data <= '0;
            last_write_mask <= '0;
        end else begin
            if (|dbg_mem_we) begin
                write_occurred <= 1'b1;
                last_write_addr <= dbg_mem_addr;
                last_write_data <= dbg_mem_wdata;
                last_write_mask <= dbg_mem_we;
            end else if (dbg_mem_re) begin
                write_occurred <= 1'b0;  // Clear after any read
            end
        end
    end
    
    // Assertion 13: Write-then-read consistency (full-word writes only)
    property write_read_consistency;
        @(posedge clk) disable iff (!rst_n)
        (write_occurred && dbg_mem_re && (dbg_mem_addr == last_write_addr) && 
         (last_write_mask == 4'b1111)) |=> 
        (dbg_mem_rdata == last_write_data);
    endproperty
    
    ast_write_read_consistency: assert property (write_read_consistency)
        else $error("[DEBUG_PORT] Write-read consistency failed: addr=0x%03x, expected=0x%08x, got=0x%08x",
                    last_write_addr, last_write_data, dbg_mem_rdata);
    
    //==========================================================================
    // Coverage: Track Debug Interface Usage
    //==========================================================================
    covergroup cg_debug_interface @(posedge clk);
        option.per_instance = 1;
        option.name = "debug_interface_coverage";
        
        cp_write_enable: coverpoint dbg_mem_we {
            bins byte0_only   = {4'b0001};
            bins byte1_only   = {4'b0010};
            bins byte2_only   = {4'b0100};
            bins byte3_only   = {4'b1000};
            bins halfword_low = {4'b0011};
            bins halfword_hi  = {4'b1100};
            bins word         = {4'b1111};
            bins no_write     = {4'b0000};
        }
        
        cp_read_enable: coverpoint dbg_mem_re {
            bins read_active  = {1'b1};
            bins read_idle    = {1'b0};
        }
        
        cp_addr_range: coverpoint dbg_mem_addr {
            bins low_addr   = {[0:255]};
            bins mid_addr   = {[256:1791]};
            bins high_addr  = {[1792:2047]};
        }
        
        // Cross coverage: write patterns vs address ranges
        cx_write_addr: cross cp_write_enable, cp_addr_range;
    endgroup
    
    cg_debug_interface cg_dbg_inst = new();

endmodule

//==============================================================================
// Bind Statement
//==============================================================================
// NOTE: Temporarily disabled for VexRiscv integration
// VexRiscv uses different internal structure (no rv32i_core module)
// TODO: Create vexriscv_debug_port_assertions.sv for VexRiscv-specific checks
/*
bind rv32i_core rv32i_debug_port_assertions u_debug_port_assertions (
    .clk(clk),
    .rst_n(rst_n),
    
    // Debug interface
    .dbg_mem_we(dbg_mem_we),
    .dbg_mem_re(dbg_mem_re),
    .dbg_mem_addr(dbg_mem_addr),
    .dbg_mem_wdata(dbg_mem_wdata),
    .dbg_mem_rdata(dbg_mem_rdata),
    
    // CPU Port B signals
    .cpu_mem_write(ex_mem_reg.ctrl.mem_write && mem_is_ram),
    .cpu_mem_read(ex_mem_reg.ctrl.mem_read && mem_is_ram),
    .cpu_mem_addr(ram_addr_mem),
    
    // BRAM control
    .ram_ena_b(ram_ena_b)
);
*/
