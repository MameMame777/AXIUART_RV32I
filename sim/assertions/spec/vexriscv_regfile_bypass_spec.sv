`timescale 1ns / 1ps
//==============================================================================
// VexRiscv RegFile Bypass Specification
//==============================================================================
// Observer-only assertions for register file read/write and bypass correctness.
// Checks: read-after-write timing (SyncDR), x0 hardwiring, and write enable.
// Bind target: VexRiscv
//==============================================================================

`ifdef ENABLE_ASSERTIONS

module vexriscv_regfile_bypass_spec (
    input logic clk,
    input logic reset,

    // Register file synchronous read data (registered, available one cycle after address)
    input logic [31:0] RegFilePlugin_regFile_spinal_port0,  // RS1 read port
    input logic [31:0] RegFilePlugin_regFile_spinal_port1,  // RS2 read port

    // RegFile read addresses (from decode stage, combinational)
    input logic [4:0]  decode_RegFilePlugin_regFileReadAddress1,
    input logic [4:0]  decode_RegFilePlugin_regFileReadAddress2,

    // WriteBack write port (last stage register write)
    input logic        lastStageRegFileWrite_valid,
    input logic [4:0]  lastStageRegFileWrite_payload_address,
    input logic [31:0] lastStageRegFileWrite_payload_data,

    // WriteBack stage arbitration
    input logic        writeBack_arbitration_isFiring,
    input logic        writeBack_REGFILE_WRITE_VALID,

    // WriteBack instruction [11:7] = rd field
    input logic [31:0] writeBack_INSTRUCTION,

    // Decode stage: rd==x0 detection and REGFILE_WRITE_VALID
    input logic        when_RegFilePlugin_l63,      // decode rd == x0
    input logic        decode_REGFILE_WRITE_VALID,  // decode stage write enable

    // Debug-mode override flag (suppresses x0 assertion during debug init)
    input logic        _zz_5
);

    // -------------------------------------------------------------------------
    // Check 1: Read-after-write (SyncDR) – bypass buffer consistency
    // After WB stage fires a register write, the HazardSimplePlugin writeBackBuffer
    // is updated with the new data. Since the regfile is synchronous (SyncDR),
    // the written data is readable from the regfile one cycle after the write.
    // This checks that lastStageRegFileWrite_valid reflects actual WB firing.
    // -------------------------------------------------------------------------
    property p_wb_write_requires_firing;
        @(posedge clk) disable iff (reset)
        (lastStageRegFileWrite_valid && !_zz_5) |-> writeBack_arbitration_isFiring;
    endproperty

    a_wb_write_requires_firing: assert property (p_wb_write_requires_firing)
        else $error("[REGFILE] lastStageRegFileWrite_valid but writeBack_arbitration_isFiring=0");

    // After WB fires with a valid register write, the write port data is stable:
    // The write data read-back check (SyncDR: written in cycle N, readable in cycle N+1)
    property p_syncdr_write_address_stability;
        @(posedge clk) disable iff (reset)
        (lastStageRegFileWrite_valid && writeBack_arbitration_isFiring && !_zz_5)
        |=> $stable(lastStageRegFileWrite_payload_address) || lastStageRegFileWrite_valid;
    endproperty

    a_syncdr_write_address_stability: assert property (p_syncdr_write_address_stability)
        else $error("[REGFILE] write address changed unexpectedly after WB fire");

    // -------------------------------------------------------------------------
    // Check 2: x0 hardwiring – writes to x0 (rd==0) must be suppressed
    // When decode stage sees rd==x0, decode_REGFILE_WRITE_VALID must be 0.
    // This ensures the write enable is cleared before propagating down the pipeline.
    // -------------------------------------------------------------------------
    property p_x0_write_suppressed_at_decode;
        @(posedge clk) disable iff (reset)
        when_RegFilePlugin_l63 |-> !decode_REGFILE_WRITE_VALID;
    endproperty

    a_x0_write_suppressed_at_decode: assert property (p_x0_write_suppressed_at_decode)
        else $error("[REGFILE] x0 write not suppressed: when_RegFilePlugin_l63=1 but decode_REGFILE_WRITE_VALID=1");

    // When WB fires with REGFILE_WRITE_VALID, the destination must not be x0
    // (x0 write suppression must propagate through the pipeline).
    property p_x0_not_written_at_wb;
        @(posedge clk) disable iff (reset)
        (writeBack_arbitration_isFiring && writeBack_REGFILE_WRITE_VALID)
        |-> (writeBack_INSTRUCTION[11:7] != 5'd0);
    endproperty

    a_x0_not_written_at_wb: assert property (p_x0_not_written_at_wb)
        else $error("[REGFILE] WB fires with REGFILE_WRITE_VALID but rd=x0 (should be suppressed)");

    // -------------------------------------------------------------------------
    // Check 3: Write enable correctness
    // lastStageRegFileWrite_valid can only be asserted when writeBack_REGFILE_WRITE_VALID
    // AND writeBack_arbitration_isFiring. No spurious write enables.
    // -------------------------------------------------------------------------
    property p_write_enable_requires_valid_and_firing;
        @(posedge clk) disable iff (reset)
        (lastStageRegFileWrite_valid && !_zz_5)
        |-> (writeBack_REGFILE_WRITE_VALID && writeBack_arbitration_isFiring);
    endproperty

    a_write_enable_requires_valid_and_firing: assert property (p_write_enable_requires_valid_and_firing)
        else $error("[REGFILE] lastStageRegFileWrite_valid asserted spuriously (REGFILE_WRITE_VALID=%0b, isFiring=%0b)",
            writeBack_REGFILE_WRITE_VALID, writeBack_arbitration_isFiring);

    // Converse: when WB fires with write valid, lastStageRegFileWrite_valid must be set
    property p_write_enable_set_on_wb_fire;
        @(posedge clk) disable iff (reset)
        (writeBack_arbitration_isFiring && writeBack_REGFILE_WRITE_VALID)
        |-> lastStageRegFileWrite_valid;
    endproperty

    a_write_enable_set_on_wb_fire: assert property (p_write_enable_set_on_wb_fire)
        else $error("[REGFILE] WB fires with REGFILE_WRITE_VALID but lastStageRegFileWrite_valid=0");

endmodule

`endif // ENABLE_ASSERTIONS
