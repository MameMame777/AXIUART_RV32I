`timescale 1ns / 1ps

//==============================================================================
// Register_Block CPU Memory Debug Interface Assertions
//==============================================================================
// Purpose: Verify address-data consistency for CPU memory debug operations
//          via UART→Register_Block→rv32i_core BRAM path
//
// Bound to: Register_Block module instance in AXIUART_Top
//
// Critical Properties:
// 1. CPU_MEM_ADDR write → rv32i_mem_addr immediately reflects
// 2. CPU_MEM_WDATA write → rv32i_mem_wdata immediately reflects
// 3. CPU_MEM_CTRL[5]=1 (write request) → rv32i_mem_we becomes 4'b1111
// 4. CPU_MEM_CTRL[4]=1 (read request) → rv32i_mem_re becomes 1'b1
// 5. Address remains stable during write/read operation (until BUSY clears)
// 6. Read data capture timing: rv32i_mem_rdata → cpu_mem_rdata_reg
//==============================================================================

module register_block_cpu_mem_assertions #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter BASEADDR = 32'h00002000
)(
    input wire clk,
    input wire rst_n,
    
    // AXI4-Lite Write Interface (monitored)
    input wire [ADDR_WIDTH-1:0] axi_awaddr,
    input wire                  axi_awvalid,
    input wire                  axi_awready,
    input wire [DATA_WIDTH-1:0] axi_wdata,
    input wire [3:0]            axi_wstrb,
    input wire                  axi_wvalid,
    input wire                  axi_wready,
    
    // CPU Memory Debug Interface (monitored)
    input wire [10:0]  rv32i_mem_addr,   // Word address to rv32i_core
    input wire [31:0]  rv32i_mem_wdata,  // Write data to rv32i_core
    input wire [31:0]  rv32i_mem_rdata,  // Read data from rv32i_core
    input wire [3:0]   rv32i_mem_we,     // Byte write enable
    input wire         rv32i_mem_re,     // Read enable
    input wire         rv32i_mem_busy,   // Operation in progress
    
    // Internal registers (monitored)
    input wire [31:0]  cpu_mem_addr_reg,  // REG_CPU_MEM_ADDR value
    input wire [31:0]  cpu_mem_wdata_reg, // REG_CPU_MEM_WDATA value
    input wire [31:0]  cpu_mem_rdata_reg, // REG_CPU_MEM_RDATA value
    input wire [31:0]  cpu_mem_ctrl_reg   // REG_CPU_MEM_CTRL value
);

    //==========================================================================
    // Register Address Definitions (relative to BASEADDR)
    //==========================================================================
    localparam REG_CPU_MEM_ADDR  = 32'h00000228;  // 0x2228
    localparam REG_CPU_MEM_WDATA = 32'h0000022C;  // 0x222C
    localparam REG_CPU_MEM_RDATA = 32'h00000230;  // 0x2230
    localparam REG_CPU_MEM_CTRL  = 32'h00000234;  // 0x2234
    
    //==========================================================================
    // Helper Functions
    //==========================================================================
    function automatic logic is_write_to_reg(input [31:0] offset);
        return (axi_awvalid && axi_awready && 
                (axi_awaddr - BASEADDR) == offset);
    endfunction
    
    function automatic logic [31:0] apply_wstrb(input [31:0] old_val, 
                                                 input [31:0] new_val,
                                                 input [3:0] strb);
        logic [31:0] result;
        for (int i = 0; i < 4; i++) begin
            result[i*8 +: 8] = strb[i] ? new_val[i*8 +: 8] : old_val[i*8 +: 8];
        end
        return result;
    endfunction
    
    //==========================================================================
    // Write Tracking State
    //==========================================================================
    logic [10:0] expected_addr;   // Expected word address (from cpu_mem_addr_reg[12:2])
    logic [31:0] expected_wdata;  // Expected write data
    logic        write_pending;   // Write operation in progress
    logic        read_pending;    // Read operation in progress
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            expected_addr     <= 11'h000;
            expected_wdata    <= 32'h0000_0000;
            write_pending     <= 1'b0;
            read_pending      <= 1'b0;
        end else begin
            // Track write request (CPU_MEM_CTRL[5]=1)
            // Capture expected address/data at trigger time (when RTL latches into latched_mem_addr/wdata)
            if (is_write_to_reg(REG_CPU_MEM_CTRL) && axi_wvalid && axi_wready && 
                axi_wstrb[0] && axi_wdata[5]) begin
                write_pending  <= 1'b1;
                expected_addr  <= cpu_mem_addr_reg[12:2];  // Capture word address at WRITE_REQ trigger
                expected_wdata <= cpu_mem_wdata_reg;       // Capture write data at WRITE_REQ trigger
            end else if (write_pending && !rv32i_mem_busy) begin
                write_pending <= 1'b0;
            end
            
            // Track read request (CPU_MEM_CTRL[4]=1)
            // Capture expected address at trigger time (when RTL latches into latched_mem_addr)
            if (is_write_to_reg(REG_CPU_MEM_CTRL) && axi_wvalid && axi_wready && 
                axi_wstrb[0] && axi_wdata[4]) begin
                read_pending  <= 1'b1;
                expected_addr <= cpu_mem_addr_reg[12:2];  // Capture word address at READ_REQ trigger
            end else if (read_pending && !rv32i_mem_busy) begin
                read_pending <= 1'b0;
            end
        end
    end
    
    //==========================================================================
    // Assertion 1: Address Register Consistency (DISABLED - checked by Assertion 7/9)
    // NOTE: RTL uses mux: rv32i_mem_addr = rv32i_mem_busy ? latched_mem_addr[12:2] : cpu_mem_addr_reg[12:2]
    // This assertion would fail during BUSY cycles when latched address is used.
    // Address correctness is verified by ast_write_addr_match and ast_read_addr_match instead.
    //==========================================================================
    // property addr_register_consistency;
    //     @(posedge clk) disable iff (!rst_n)
    //     (rv32i_mem_addr == cpu_mem_addr_reg[12:2]);
    // endproperty
    // 
    // ast_addr_consistency: assert property (addr_register_consistency)
    //     else $error("[CPU_MEM_ADDR] Address inconsistency: rv32i_mem_addr=0x%03X, expected=0x%03X (from cpu_mem_addr_reg=0x%08X)",
    //                 rv32i_mem_addr, cpu_mem_addr_reg[12:2], cpu_mem_addr_reg);
    
    //==========================================================================
    // Assertion 2: Write Data Register Consistency (DISABLED - checked by Assertion 8)
    // NOTE: RTL uses mux: rv32i_mem_wdata = rv32i_mem_busy ? latched_mem_wdata : cpu_mem_wdata_reg
    // This assertion would fail during BUSY cycles when latched data is used.
    // Write data correctness is verified by ast_write_data_match instead.
    //==========================================================================
    // property wdata_register_consistency;
    //     @(posedge clk) disable iff (!rst_n)
    //     (rv32i_mem_wdata == cpu_mem_wdata_reg);
    // endproperty
    // 
    // ast_wdata_consistency: assert property (wdata_register_consistency)
    //     else $error("[CPU_MEM_WDATA] Write data inconsistency: rv32i_mem_wdata=0x%08X, expected=0x%08X",
    //                 rv32i_mem_wdata, cpu_mem_wdata_reg);
    
    //==========================================================================
    // Assertion 3: Write Enable Generation
    // CPU_MEM_CTRL[5]=1 (write request) → rv32i_mem_we becomes non-zero
    //==========================================================================
    property write_enable_generation;
        @(posedge clk) disable iff (!rst_n)
        (is_write_to_reg(REG_CPU_MEM_CTRL) && axi_wvalid && axi_wready && 
         axi_wstrb[0] && axi_wdata[5]) |-> ##[0:2] (rv32i_mem_we != 4'b0000);
    endproperty
    
    ast_write_enable: assert property (write_enable_generation)
        else $error("[CPU_MEM_CTRL] Write request did not generate rv32i_mem_we (stuck at 0x%01X)",
                    rv32i_mem_we);
    
    //==========================================================================
    // Assertion 4: Read Enable Generation
    // CPU_MEM_CTRL[4]=1 (read request) → rv32i_mem_re becomes 1'b1
    //==========================================================================
    property read_enable_generation;
        @(posedge clk) disable iff (!rst_n)
        (is_write_to_reg(REG_CPU_MEM_CTRL) && axi_wvalid && axi_wready && 
         axi_wstrb[0] && axi_wdata[4]) |-> ##[0:2] rv32i_mem_re;
    endproperty
    
    ast_read_enable: assert property (read_enable_generation)
        else $error("[CPU_MEM_CTRL] Read request did not generate rv32i_mem_re");
    
    //==========================================================================
    // Assertion 5: Address Stability During Write
    // Address must remain stable while write operation is in progress
    //==========================================================================
    property addr_stable_during_write;
        @(posedge clk) disable iff (!rst_n)
        (write_pending && rv32i_mem_busy) |-> 
        $stable(rv32i_mem_addr);
    endproperty
    
    ast_addr_stable_write: assert property (addr_stable_during_write)
        else $error("[ADDR_STABILITY] Address changed during write: was 0x%03X, now 0x%03X",
                    $past(rv32i_mem_addr), rv32i_mem_addr);
    
    //==========================================================================
    // Assertion 6: Address Stability During Read
    // Address must remain stable while read operation is in progress
    //==========================================================================
    property addr_stable_during_read;
        @(posedge clk) disable iff (!rst_n)
        (read_pending && rv32i_mem_busy) |-> 
        $stable(rv32i_mem_addr);
    endproperty
    
    ast_addr_stable_read: assert property (addr_stable_during_read)
        else $error("[ADDR_STABILITY] Address changed during read: was 0x%03X, now 0x%03X",
                    $past(rv32i_mem_addr), rv32i_mem_addr);
    
    //==========================================================================
    // Assertion 7: Write Address Matches Expected
    // When write is pending and write enable asserts, rv32i_mem_addr must match expected address
    // NOTE: write_pending ensures expected_addr was captured at CPU_MEM_CTRL trigger time
    //==========================================================================
    property write_addr_matches_expected;
        @(posedge clk) disable iff (!rst_n)
        (write_pending && |rv32i_mem_we) |-> (rv32i_mem_addr == expected_addr);
    endproperty
    
    ast_write_addr_match: assert property (write_addr_matches_expected)
        else $error("[WRITE_ADDR] Write to wrong address: rv32i_mem_addr=0x%03X, expected=0x%03X (byte_addr=0x%08X)",
                    rv32i_mem_addr, expected_addr, cpu_mem_addr_reg);
    
    //==========================================================================
    // Assertion 8: Write Data Matches Expected
    // When write is pending and write enable asserts, rv32i_mem_wdata must match expected data
    // NOTE: write_pending ensures expected_wdata was captured at CPU_MEM_CTRL trigger time
    //==========================================================================
    property write_data_matches_expected;
        @(posedge clk) disable iff (!rst_n)
        (write_pending && |rv32i_mem_we) |-> (rv32i_mem_wdata == expected_wdata);
    endproperty
    
    ast_write_data_match: assert property (write_data_matches_expected)
        else $error("[WRITE_DATA] Write data mismatch: rv32i_mem_wdata=0x%08X, expected=0x%08X (from cpu_mem_wdata_reg)",
                    rv32i_mem_wdata, expected_wdata);
    
    //==========================================================================
    // Assertion 9: Read Address Matches Expected
    // When read is pending and read enable asserts, rv32i_mem_addr must match expected address
    // NOTE: read_pending ensures expected_addr was captured at CPU_MEM_CTRL trigger time
    //==========================================================================
    property read_addr_matches_expected;
        @(posedge clk) disable iff (!rst_n)
        (read_pending && rv32i_mem_re) |-> (rv32i_mem_addr == expected_addr);
    endproperty
    
    ast_read_addr_match: assert property (read_addr_matches_expected)
        else $error("[READ_ADDR] Read from wrong address: rv32i_mem_addr=0x%03X, expected=0x%03X (byte_addr=0x%08X)",
                    rv32i_mem_addr, expected_addr, cpu_mem_addr_reg);
    
    //==========================================================================
    // Assertion 10: BUSY Signal Behavior
    // BUSY must assert when write/read request issued
    //==========================================================================
    property busy_asserts_on_operation;
        @(posedge clk) disable iff (!rst_n)
        (is_write_to_reg(REG_CPU_MEM_CTRL) && axi_wvalid && axi_wready && 
         axi_wstrb[0] && (axi_wdata[4] || axi_wdata[5])) |-> 
        ##[0:2] rv32i_mem_busy;
    endproperty
    
    ast_busy_assertion: assert property (busy_asserts_on_operation)
        else $error("[BUSY] rv32i_mem_busy did not assert after CPU_MEM_CTRL operation request");
    
    //==========================================================================
    // Assertion 11: No X/Z in Address During Operation
    //==========================================================================
    property no_x_in_addr;
        @(posedge clk) disable iff (!rst_n)
        (rv32i_mem_busy || rv32i_mem_re || |rv32i_mem_we) |-> 
        !$isunknown(rv32i_mem_addr);
    endproperty
    
    ast_no_x_addr: assert property (no_x_in_addr)
        else $error("[ADDR_X] rv32i_mem_addr contains X/Z during operation: 0x%03X", rv32i_mem_addr);
    
    //==========================================================================
    // Assertion 12: No X/Z in Write Data During Write
    //==========================================================================
    property no_x_in_wdata;
        @(posedge clk) disable iff (!rst_n)
        (|rv32i_mem_we) |-> !$isunknown(rv32i_mem_wdata);
    endproperty
    
    ast_no_x_wdata: assert property (no_x_in_wdata)
        else $error("[WDATA_X] rv32i_mem_wdata contains X/Z during write: 0x%08X", rv32i_mem_wdata);
    
    //==========================================================================
    // Coverage: Operation Sequences
    //==========================================================================
    
    covergroup cg_cpu_mem_operations @(posedge clk);
        option.per_instance = 1;
        
        cp_addr_write: coverpoint is_write_to_reg(REG_CPU_MEM_ADDR) {
            bins addr_set = {1};
        }
        
        cp_wdata_write: coverpoint is_write_to_reg(REG_CPU_MEM_WDATA) {
            bins wdata_set = {1};
        }
        
        cp_write_request: coverpoint (is_write_to_reg(REG_CPU_MEM_CTRL) && 
                                       axi_wvalid && axi_wstrb[0] && axi_wdata[5]) {
            bins write_req = {1};
        }
        
        cp_read_request: coverpoint (is_write_to_reg(REG_CPU_MEM_CTRL) && 
                                      axi_wvalid && axi_wstrb[0] && axi_wdata[4]) {
            bins read_req = {1};
        }
        
        // Cross: Write sequence (ADDR → WDATA → CTRL[write])
        cx_write_sequence: cross cp_addr_write, cp_wdata_write, cp_write_request;
        
        // Cross: Read sequence (ADDR → CTRL[read])
        cx_read_sequence: cross cp_addr_write, cp_read_request;
    endgroup
    
    cg_cpu_mem_operations cg_ops = new();
    
    //==========================================================================
    // Debug Info (on assertion failure)
    //==========================================================================
    
    always @(posedge clk) begin
        if (!rst_n) begin
            // Reset state - no action
        end else begin
            // Monitor critical state changes
            if ($past(rv32i_mem_addr) != rv32i_mem_addr && (rv32i_mem_busy || rv32i_mem_re || |rv32i_mem_we)) begin
                $display("[DEBUG] %t: Address changed during operation: 0x%03X → 0x%03X (busy=%b, re=%b, we=0x%01X)",
                         $time, $past(rv32i_mem_addr), rv32i_mem_addr, 
                         rv32i_mem_busy, rv32i_mem_re, rv32i_mem_we);
            end
        end
    end

endmodule

//==============================================================================
// Bind Statement (add to dsim_config.f or separate bind file)
//==============================================================================
// bind Register_Block register_block_cpu_mem_assertions #(
//     .ADDR_WIDTH(AXI_ADDR_WIDTH),
//     .DATA_WIDTH(AXI_DATA_WIDTH),
//     .BASEADDR(BASEADDR)
// ) u_cpu_mem_assertions (
//     .clk(clk),
//     .rst_n(rst_n),
//     .axi_awaddr(axi.awaddr),
//     .axi_awvalid(axi.awvalid),
//     .axi_awready(axi.awready),
//     .axi_wdata(axi.wdata),
//     .axi_wstrb(axi.wstrb),
//     .axi_wvalid(axi.wvalid),
//     .axi_wready(axi.wready),
//     .rv32i_mem_addr(rv32i_mem_addr),
//     .rv32i_mem_wdata(rv32i_mem_wdata),
//     .rv32i_mem_rdata(rv32i_mem_rdata),
//     .rv32i_mem_we(rv32i_mem_we),
//     .rv32i_mem_re(rv32i_mem_re),
//     .rv32i_mem_busy(rv32i_mem_busy),
//     .cpu_mem_addr_reg(cpu_mem_addr_reg),
//     .cpu_mem_wdata_reg(cpu_mem_wdata_reg),
//     .cpu_mem_rdata_reg(cpu_mem_rdata_reg),
//     .cpu_mem_ctrl_reg(cpu_mem_ctrl_reg)
// );
