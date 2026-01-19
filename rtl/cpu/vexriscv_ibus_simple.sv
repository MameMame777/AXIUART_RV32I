`timescale 1ns/1ps
//==============================================================================
// VexRiscv IBusSimplePlugin Module
//
// Instruction fetch unit with:
// - PC management and increment
// - Instruction bus command generation
// - Response buffering and staging
// - Decode injection
// - Static branch prediction
//
// Extracted from VexRiscv_GenSmallAndProductive.v
// Original lines: ~383-2400 (distributed across file)
//==============================================================================

module vexriscv_ibus_simple
    import vexriscv_pkg::*;
(
    input  logic        clk,
    input  logic        reset,
    
    // External bus interface
    output logic        iBus_cmd_valid,
    input  logic        iBus_cmd_ready,
    output logic [31:0] iBus_cmd_payload_pc,
    input  logic        iBus_rsp_valid,
    input  logic        iBus_rsp_payload_error,
    input  logic [31:0] iBus_rsp_payload_inst,
    
    // Jump interfaces (priority: Branch > CSR > Prediction)
    input  logic        branchPlugin_jump_valid,
    input  logic [31:0] branchPlugin_jump_payload,
    input  logic        csrPlugin_jump_valid,
    input  logic [31:0] csrPlugin_jump_payload,
    
    // Decode stage interface
    output logic        decode_arbitration_isValid,
    input  logic        decode_arbitration_isStuck,
    input  logic        decode_arbitration_removeIt,
    output logic [31:0] decode_instruction,
    output logic [31:0] decode_pc,
    
    // Branch prediction interface
    input  logic [1:0]  decode_branch_ctrl,
    input  logic [31:0] decode_instruction_for_prediction,
    output logic        prediction_jump_valid,
    output logic [31:0] prediction_jump_payload,
    output logic        decode_prediction_had_branched,
    
    // Pipeline control
    input  logic        execute_arbitration_flushNext,
    input  logic        memory_arbitration_flushNext,
    input  logic        writeBack_arbitration_flushNext,
    input  logic        decode_arbitration_flushNext,
    input  logic        execute_arbitration_isStuck,
    input  logic        memory_arbitration_isStuck,
    input  logic        writeBack_arbitration_isStuck,
    
    // Fetch control
    input  logic        fetcher_halt,
    input  logic        force_no_decode_cond,
    
    // Status
    output logic        incoming_instruction
);

    //==========================================================================
    // Internal Signals - FetchPC
    //==========================================================================
    
    logic [31:0] fetchPc_pcReg;
    logic        fetchPc_correction;
    logic        fetchPc_correctionReg;
    logic        fetchPc_output_valid;
    logic        fetchPc_output_ready;
    logic [31:0] fetchPc_output_payload;
    logic        fetchPc_output_fire;
    logic        fetchPc_corrected;
    logic        fetchPc_pcRegPropagate;
    logic        fetchPc_booted;
    logic        fetchPc_inc;
    logic [31:0] fetchPc_pc;
    logic        fetchPc_flushed;
    
    logic        jump_pcLoad_valid;
    logic [31:0] jump_pcLoad_payload;
    logic [2:0]  jump_pcLoad_sources;
    logic [2:0]  jump_pcLoad_priority;
    
    //==========================================================================
    // Internal Signals - IBusRsp Stages
    //==========================================================================
    
    logic        iBusRsp_stages_0_input_valid;
    logic        iBusRsp_stages_0_input_ready;
    logic [31:0] iBusRsp_stages_0_input_payload;
    logic        iBusRsp_stages_0_output_valid;
    logic        iBusRsp_stages_0_output_ready;
    logic [31:0] iBusRsp_stages_0_output_payload;
    logic        iBusRsp_stages_0_halt;
    
    logic        iBusRsp_stages_1_input_valid;
    logic        iBusRsp_stages_1_input_ready;
    logic [31:0] iBusRsp_stages_1_input_payload;
    logic        iBusRsp_stages_1_output_valid;
    logic        iBusRsp_stages_1_output_ready;
    logic [31:0] iBusRsp_stages_1_output_payload;
    
    logic        iBusRsp_stages_0_output_m2sPipe_valid;
    logic        iBusRsp_flush;
    logic        iBusRsp_readyForError;
    
    //==========================================================================
    // Internal Signals - Response Buffer & Injector
    //==========================================================================
    
    logic [2:0]  pending_value;
    logic [2:0]  pending_next;
    logic        pending_inc;
    logic        pending_dec;
    
    logic [2:0]  rspJoin_rspBuffer_discardCounter;
    
    logic        rspBuffer_push_valid;
    logic        rspBuffer_push_ready;
    logic        rspBuffer_push_payload_error;
    logic [31:0] rspBuffer_push_payload_inst;
    logic        rspBuffer_pop_valid;
    logic        rspBuffer_pop_ready;
    logic        rspBuffer_pop_payload_error;
    logic [31:0] rspBuffer_pop_payload_inst;
    
    logic        injector_decodeInput_valid;
    logic        injector_decodeInput_ready;
    logic [31:0] injector_decodeInput_payload_pc;
    logic        injector_decodeInput_payload_rsp_error;
    logic [31:0] injector_decodeInput_payload_rsp_inst;
    logic        injector_decodeInput_payload_isRvc;
    
    logic        injector_nextPcCalc_valids_0;
    logic        injector_nextPcCalc_valids_1;
    logic        injector_nextPcCalc_valids_2;
    logic        injector_nextPcCalc_valids_3;
    logic        injector_nextPcCalc_valids_4;
    
    logic        pcValids_0;
    logic        pcValids_1;
    logic        pcValids_2;
    logic        pcValids_3;
    
    //==========================================================================
    // Internal Signals - Prediction
    //==========================================================================
    
    logic        decodePrediction_cmd_hadBranch;
    logic [31:0] predictionJumpInterface_payload;
    
    //==========================================================================
    // External Flush Signal
    //==========================================================================
    
    logic externalFlush;
    assign externalFlush = (|{writeBack_arbitration_flushNext, {memory_arbitration_flushNext, {execute_arbitration_flushNext, decode_arbitration_flushNext}}});
    
    //==========================================================================
    // Jump PC Load Logic (Priority: Branch > CSR > Prediction)
    //==========================================================================
    
    assign jump_pcLoad_sources = {prediction_jump_valid, {branchPlugin_jump_valid, csrPlugin_jump_valid}};
    assign jump_pcLoad_priority = jump_pcLoad_sources & (~(jump_pcLoad_sources - 3'b001));
    assign jump_pcLoad_valid = (|jump_pcLoad_sources);
    
    always_comb begin
        jump_pcLoad_payload = 32'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
        if (jump_pcLoad_priority[0]) jump_pcLoad_payload = csrPlugin_jump_payload;
        if (jump_pcLoad_priority[1]) jump_pcLoad_payload = branchPlugin_jump_payload;
        if (jump_pcLoad_priority[2]) jump_pcLoad_payload = predictionJumpInterface_payload;
    end
    
    //==========================================================================
    // FetchPC Logic
    //==========================================================================
    
    assign fetchPc_output_fire = (fetchPc_output_valid && fetchPc_output_ready);
    assign fetchPc_corrected = (fetchPc_correction || fetchPc_correctionReg);
    
    always_comb begin
        fetchPc_correction = 1'b0;
        if (jump_pcLoad_valid) begin
            fetchPc_correction = 1'b1;
        end
    end
    
    always_comb begin
        fetchPc_pcRegPropagate = 1'b0;
        if (iBusRsp_stages_1_input_ready) begin
            fetchPc_pcRegPropagate = 1'b1;
        end
    end
    
    always_comb begin
        fetchPc_pc = fetchPc_pcReg + {fetchPc_inc, 2'b00};
        if (jump_pcLoad_valid) begin
            fetchPc_pc = jump_pcLoad_payload;
        end
        fetchPc_pc[0] = 1'b0;
        fetchPc_pc[1] = 1'b0;
    end
    
    always_comb begin
        fetchPc_flushed = 1'b0;
        if (jump_pcLoad_valid) begin
            fetchPc_flushed = 1'b1;
        end
    end
    
    assign fetchPc_output_valid = ((!fetcher_halt) && fetchPc_booted);
    assign fetchPc_output_payload = fetchPc_pc;
    
    //==========================================================================
    // IBusRsp Stage 0
    //==========================================================================
    
    assign iBusRsp_stages_0_input_valid = fetchPc_output_valid;
    assign fetchPc_output_ready = iBusRsp_stages_0_input_ready;
    assign iBusRsp_stages_0_input_payload = fetchPc_output_payload;
    
    always_comb begin
        iBusRsp_stages_0_halt = 1'b0;
        if (pending_value == 3'b111) begin // when_IBusSimplePlugin_l306
            iBusRsp_stages_0_halt = 1'b1;
        end
    end
    
    assign iBusRsp_stages_0_input_ready = (iBusRsp_stages_0_output_ready && (!iBusRsp_stages_0_halt));
    assign iBusRsp_stages_0_output_valid = (iBusRsp_stages_0_input_valid && (!iBusRsp_stages_0_halt));
    assign iBusRsp_stages_0_output_payload = iBusRsp_stages_0_input_payload;
    
    //==========================================================================
    // IBusRsp Stage 0 -> 1 (M2S Pipe)
    //==========================================================================
    
    assign iBusRsp_stages_0_output_ready = ((1'b0 && (!iBusRsp_stages_0_output_m2sPipe_valid)) || iBusRsp_stages_1_input_ready);
    
    assign iBusRsp_stages_1_input_valid = iBusRsp_stages_0_output_m2sPipe_valid;
    assign iBusRsp_stages_1_input_payload = fetchPc_pcReg;
    
    //==========================================================================
    // IBusRsp Stage 1
    //==========================================================================
    
    assign iBusRsp_stages_1_input_ready = (iBusRsp_stages_1_output_ready && 1'b1);
    assign iBusRsp_stages_1_output_valid = iBusRsp_stages_1_input_valid;
    assign iBusRsp_stages_1_output_payload = iBusRsp_stages_1_input_payload;
    
    //==========================================================================
    // IBusRsp Flush
    //==========================================================================
    
    assign iBusRsp_flush = (externalFlush || 1'b0); // No redoFetch
    
    //==========================================================================
    // Response Buffer (StreamFifoLowLatency instantiation)
    //==========================================================================
    
    assign rspBuffer_push_valid = iBus_rsp_valid;
    assign rspBuffer_push_payload_error = iBus_rsp_payload_error;
    assign rspBuffer_push_payload_inst = iBus_rsp_payload_inst;
    
    StreamFifoLowLatency rspBuffer (
        .clk                    (clk),
        .reset                  (reset),
        .io_push_valid          (rspBuffer_push_valid),
        .io_push_ready          (rspBuffer_push_ready),
        .io_push_payload_error  (rspBuffer_push_payload_error),
        .io_push_payload_inst   (rspBuffer_push_payload_inst),
        .io_pop_valid           (rspBuffer_pop_valid),
        .io_pop_ready           (rspBuffer_pop_ready),
        .io_pop_payload_error   (rspBuffer_pop_payload_error),
        .io_pop_payload_inst    (rspBuffer_pop_payload_inst),
        .io_flush               (iBusRsp_flush),
        .io_occupancy           (),
        .io_availability        ()
    );
    
    //==========================================================================
    // Pending Counter
    //==========================================================================
    
    assign pending_inc = (iBus_cmd_valid && iBus_cmd_ready);
    assign pending_dec = (rspBuffer_pop_valid && (rspJoin_rspBuffer_discardCounter == 3'b000));
    assign pending_next = (pending_value + {2'b00, pending_inc}) - {2'b00, pending_dec};
    
    //==========================================================================
    // IBus Command
    //==========================================================================
    
    assign iBus_cmd_valid = (iBusRsp_stages_0_output_valid && (!iBusRsp_stages_0_halt));
    assign iBus_cmd_payload_pc = iBusRsp_stages_0_output_payload;
    
    //==========================================================================
    // Response Join & Injector
    //==========================================================================
    
    assign rspBuffer_pop_ready = 1'b1;
    
    always_comb begin
        iBusRsp_readyForError = 1'b1;
        if (injector_decodeInput_valid) begin
            iBusRsp_readyForError = 1'b0;
        end
        if (!pcValids_0) begin // when_Fetcher_l322
            iBusRsp_readyForError = 1'b0;
        end
    end
    
    assign iBusRsp_stages_1_output_ready = ((1'b0 && (!injector_decodeInput_valid)) || injector_decodeInput_ready);
    
    assign injector_decodeInput_ready = (!decode_arbitration_isStuck);
    
    assign pcValids_0 = injector_nextPcCalc_valids_1;
    assign pcValids_1 = injector_nextPcCalc_valids_2;
    assign pcValids_2 = injector_nextPcCalc_valids_3;
    assign pcValids_3 = injector_nextPcCalc_valids_4;
    
    //==========================================================================
    // Decode Arbitration
    //==========================================================================
    
    always_comb begin
        decode_arbitration_isValid = injector_decodeInput_valid;
        if (force_no_decode_cond) begin
            decode_arbitration_isValid = 1'b0;
        end
    end
    
    // Debug: Log decode arbitration changes
    always @(posedge clk) begin
        if (decode_arbitration_isValid && (!$past(decode_arbitration_isValid))) begin
            $display("[%0t] DECODE: decode_arbitration_isValid asserted (inst=0x%08x, pc=0x%08x)", 
                     $time, decode_instruction, decode_pc);
        end
    end
    
`ifdef DEBUG
    // Expose decoder outputs for debugging
    always @(posedge clk) begin
        if (decode_arbitration_isValid) begin
            $display("[%0t] DECODE_CTRL: REGFILE_WR=%0b RS1_USE=%0b RS2_USE=%0b MEM_EN=%0b", 
                     $time, 1'bx, 1'bx, 1'bx, 1'bx);  // Will be driven by top-level
        end
    end
`endif
    
    assign decode_instruction = injector_decodeInput_payload_rsp_inst;
    assign decode_pc = injector_decodeInput_payload_pc;
    
    //==========================================================================
    // Incoming Instruction Flag
    //==========================================================================
    
    always_comb begin
        incoming_instruction = 1'b0;
        if (iBusRsp_stages_1_input_valid) begin
            incoming_instruction = 1'b1;
        end
        if (injector_decodeInput_valid) begin
            incoming_instruction = 1'b1;
        end
    end
    
    //==========================================================================
    // Branch Prediction Logic
    //==========================================================================
    
    always_comb begin
        decodePrediction_cmd_hadBranch = ((decode_branch_ctrl == 2'd2) || // JAL
                                          ((decode_branch_ctrl == 2'd1) && decode_instruction_for_prediction[31])); // B with negative offset
        // Note: Actual implementation would check the computed branch target
    end
    
    assign prediction_jump_valid = (decode_arbitration_isValid && decodePrediction_cmd_hadBranch);
    
    // Simplified branch target calculation (actual implementation extracts immediate fields)
    assign predictionJumpInterface_payload = decode_pc + 32'h4; // Placeholder - real logic extracts J/B immediate
    
    assign decode_prediction_had_branched = decodePrediction_cmd_hadBranch;
    
    //==========================================================================
    // Sequential Logic - FetchPC
    //==========================================================================
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            fetchPc_pcReg <= 32'h80000000;
            fetchPc_correctionReg <= 1'b0;
            fetchPc_booted <= 1'b0;
            fetchPc_inc <= 1'b0;
        end else begin
            if (fetchPc_correction) begin
                fetchPc_correctionReg <= 1'b1;
            end
            if (fetchPc_output_fire) begin
                fetchPc_correctionReg <= 1'b0;
            end
            fetchPc_booted <= 1'b1;
            if (fetchPc_correction || fetchPc_pcRegPropagate) begin // when_Fetcher_l133
                fetchPc_inc <= 1'b0;
            end
            if (fetchPc_output_fire) begin
                fetchPc_inc <= 1'b1;
            end
            if ((!fetchPc_output_valid) && fetchPc_output_ready) begin // when_Fetcher_l133_1
                fetchPc_inc <= 1'b0;
            end
            if (fetchPc_booted && ((fetchPc_output_ready || fetchPc_correction) || fetchPc_pcRegPropagate)) begin // when_Fetcher_l160
                fetchPc_pcReg <= fetchPc_pc;
            end
        end
    end
    
    //==========================================================================
    // Sequential Logic - IBusRsp Stages
    //==========================================================================
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            iBusRsp_stages_0_output_m2sPipe_valid <= 1'b0;
        end else begin
            if (iBusRsp_flush) begin
                iBusRsp_stages_0_output_m2sPipe_valid <= 1'b0;
            end
            if (iBusRsp_stages_0_output_ready) begin
                iBusRsp_stages_0_output_m2sPipe_valid <= (iBusRsp_stages_0_output_valid && (!1'b0));
            end
        end
    end
    
    //==========================================================================
    // Sequential Logic - Injector
    //==========================================================================
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            injector_decodeInput_valid <= 1'b0;
            injector_nextPcCalc_valids_0 <= 1'b0;
            injector_nextPcCalc_valids_1 <= 1'b0;
            injector_nextPcCalc_valids_2 <= 1'b0;
            injector_nextPcCalc_valids_3 <= 1'b0;
            injector_nextPcCalc_valids_4 <= 1'b0;
        end else begin
            if (decode_arbitration_removeIt) begin
                injector_decodeInput_valid <= 1'b0;
                $display("[%0t] INJECTOR: Clearing injector_decodeInput_valid due to removeIt", $time);
            end
            if (iBusRsp_stages_1_output_ready) begin
                injector_decodeInput_valid <= (rspBuffer_pop_valid && (!externalFlush));
                if (rspBuffer_pop_valid && (!externalFlush)) begin
                    $display("[%0t] INJECTOR: Setting injector_decodeInput_valid=1 (inst=0x%08x, pc=0x%08x)", 
                             $time, rspBuffer_pop_payload_inst, iBusRsp_stages_1_output_payload);
                end else begin
                    $display("[%0t] INJECTOR: Clearing injector_decodeInput_valid (rspValid=%0b, flush=%0b)", 
                             $time, rspBuffer_pop_valid, externalFlush);
                end
            end
            
            if (fetchPc_flushed) begin
                injector_nextPcCalc_valids_0 <= 1'b0;
            end
            if ((!iBusRsp_stages_1_input_ready)) begin // when_Fetcher_l331
                injector_nextPcCalc_valids_0 <= 1'b1;
            end
            
            if (fetchPc_flushed) begin
                injector_nextPcCalc_valids_1 <= 1'b0;
            end
            if ((!injector_decodeInput_ready)) begin // when_Fetcher_l331_1
                injector_nextPcCalc_valids_1 <= injector_nextPcCalc_valids_0;
            end
            
            if (fetchPc_flushed) begin
                injector_nextPcCalc_valids_2 <= 1'b0;
            end
            if ((!execute_arbitration_isStuck)) begin // when_Fetcher_l331_2
                injector_nextPcCalc_valids_2 <= injector_nextPcCalc_valids_1;
            end
            
            if (fetchPc_flushed) begin
                injector_nextPcCalc_valids_3 <= 1'b0;
            end
            if ((!memory_arbitration_isStuck)) begin // when_Fetcher_l331_3
                injector_nextPcCalc_valids_3 <= injector_nextPcCalc_valids_2;
            end
            
            if (fetchPc_flushed) begin
                injector_nextPcCalc_valids_4 <= 1'b0;
            end
            if ((!writeBack_arbitration_isStuck)) begin // when_Fetcher_l331_4
                injector_nextPcCalc_valids_4 <= injector_nextPcCalc_valids_3;
            end
        end
    end
    
    always_ff @(posedge clk) begin
        if (iBusRsp_stages_1_output_ready) begin
            injector_decodeInput_payload_pc <= iBusRsp_stages_1_output_payload;  // PC from stage 1
            injector_decodeInput_payload_rsp_error <= rspBuffer_pop_payload_error;
            injector_decodeInput_payload_rsp_inst <= rspBuffer_pop_payload_inst;
            injector_decodeInput_payload_isRvc <= 1'b0;
        end
    end
    
    //==========================================================================
    // Sequential Logic - Pending & Discard Counter
    //==========================================================================
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pending_value <= 3'b000;
            rspJoin_rspBuffer_discardCounter <= 3'b000;
        end else begin
            pending_value <= pending_next;
            rspJoin_rspBuffer_discardCounter <= (rspJoin_rspBuffer_discardCounter - {2'b00, (rspBuffer_pop_valid && (rspJoin_rspBuffer_discardCounter != 3'b000))});
            if (iBusRsp_flush) begin
                rspJoin_rspBuffer_discardCounter <= (pending_value - {2'b00, pending_dec});
            end
        end
    end

endmodule : vexriscv_ibus_simple
