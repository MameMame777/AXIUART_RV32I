`timescale 1ns / 1ps

//==============================================================================
// RV32I EBREAK Debug Specification (Enhanced Diagnostic)
//==============================================================================
// デバッグ専用: EBREAK命令がパイプラインのどの段階で失われるかを特定
//
// Purpose:
//   - Track EBREAK through all pipeline stages (IF/ID/EX/MEM)
//   - Detect where EBREAK instruction is lost or invalidated
//   - Monitor flush/stall signals that may affect EBREAK
//   - Verify cpu_break signal generation
//==============================================================================

module rv32i_ebreak_debug_spec
    import rv32i_isa_pkg::*;
(
    input logic        clk,
    input logic        rst_n,
    
    // IF Stage
    input logic        if_valid,
    input logic [31:0] if_pc,
    input logic [31:0] if_insn,
    
    // ID Stage
    input logic        id_valid,
    input logic [31:0] id_pc,
    input logic [31:0] id_insn,
    input decode_ctrl_t id_ctrl,
    
    // EX Stage
    input logic        ex_valid,
    input logic [31:0] ex_pc,
    input decode_ctrl_t ex_ctrl,
    
    // MEM Stage
    input logic        mem_valid,
    input logic [31:0] mem_pc,
    input decode_ctrl_t mem_ctrl,
    
    // WB Stage
    input logic        wb_valid,
    input logic [31:0] wb_pc,
    
    // Control
    input logic        cpu_break,
    input logic        cpu_halted,
    input logic        running,
    
    // Hazard signals
    input logic        if_stall,
    input logic        id_stall,
    input logic        if_flush,
    input logic        id_flush,
    input logic        ex_flush
);

    //==========================================================================
    // EBREAK Detection
    //==========================================================================
    
    logic ebreak_in_if, ebreak_in_id, ebreak_in_ex, ebreak_in_mem;
    
    assign ebreak_in_if  = if_valid  && (if_insn == INSN_EBREAK);
    assign ebreak_in_id  = id_valid  && id_ctrl.is_ebreak;
    assign ebreak_in_ex  = ex_valid  && ex_ctrl.is_ebreak;
    assign ebreak_in_mem = mem_valid && mem_ctrl.is_ebreak;
    
    //==========================================================================
    // ASSERTION 1: EBREAK Instruction Encoding Check
    //==========================================================================
    // アドレス0x0010の命令が本当にEBREAKか確認
    
    property ebreak_encoding_at_0x10;
        @(posedge clk) disable iff (!rst_n)
        (if_valid && if_pc == 32'h0000_0010) |-> (if_insn == 32'h0010_0073);
    endproperty
    
    assert_ebreak_encoding: assert property (ebreak_encoding_at_0x10)
        else $error("[EBREAK_DEBUG] PC=0x0010 instruction is 0x%h, expected 0x00100073 @ %0t", 
                    if_insn, $time);
    
    //==========================================================================
    // ASSERTION 2: EBREAK Decode Check
    //==========================================================================
    // INSN_EBREAK → is_ebreak=1 の変換確認
    
    property ebreak_decode_correctness;
        @(posedge clk) disable iff (!rst_n)
        (id_valid && id_insn == INSN_EBREAK) |-> id_ctrl.is_ebreak;
    endproperty
    
    assert_ebreak_decode: assert property (ebreak_decode_correctness)
        else $error("[EBREAK_DEBUG] EBREAK at PC=0x%h not decoded (is_ebreak=%b) @ %0t", 
                    id_pc, id_ctrl.is_ebreak, $time);
    
    //==========================================================================
    // ASSERTION 3: EBREAK Pipeline Progression Tracking
    //==========================================================================
    // EBREAKがIF→ID→EX→MEMに順次伝搬するか監視
    
    // IF→ID伝搬の確認（フラッシュなし）
    property ebreak_propagates_if_to_id;
        @(posedge clk) disable iff (!rst_n)
        (ebreak_in_if && !if_flush && !id_stall) |=> ebreak_in_id;
    endproperty
    
    assert_ebreak_if_to_id: assert property (ebreak_propagates_if_to_id)
        else $error("[EBREAK_DEBUG] EBREAK lost between IF→ID @ %0t (if_flush=%b, id_stall=%b)", 
                    $time, if_flush, id_stall);
    
    // ID→EX伝搬の確認
    property ebreak_propagates_id_to_ex;
        @(posedge clk) disable iff (!rst_n)
        (ebreak_in_id && !id_flush) |=> ebreak_in_ex;
    endproperty
    
    assert_ebreak_id_to_ex: assert property (ebreak_propagates_id_to_ex)
        else $error("[EBREAK_DEBUG] EBREAK lost between ID→EX @ %0t (id_flush=%b)", 
                    $time, id_flush);
    
    // EX→MEM伝搬の確認
    property ebreak_propagates_ex_to_mem;
        @(posedge clk) disable iff (!rst_n)
        (ebreak_in_ex && !ex_flush) |=> ebreak_in_mem;
    endproperty
    
    assert_ebreak_ex_to_mem: assert property (ebreak_propagates_ex_to_mem)
        else $error("[EBREAK_DEBUG] EBREAK lost between EX→MEM @ %0t (ex_flush=%b)", 
                    $time, ex_flush);
    
    //==========================================================================
    // ASSERTION 4: MEM Stage Valid Bit Persistence
    //==========================================================================
    // EBREAKがMEMに到達したとき、validビットが立っているか
    
    property ebreak_mem_valid_check;
        @(posedge clk) disable iff (!rst_n)
        (mem_ctrl.is_ebreak) |-> mem_valid;
    endproperty
    
    assert_ebreak_mem_valid: assert property (ebreak_mem_valid_check)
        else $error("[EBREAK_DEBUG] CRITICAL: is_ebreak=1 but mem_valid=0 at PC=0x%h @ %0t", 
                    mem_pc, $time);
    
    //==========================================================================
    // ASSERTION 5: cpu_break Response Timing
    //==========================================================================
    // ebreak_in_mem → cpu_break の遅延確認
    
    property cpu_break_response_timing;
        @(posedge clk) disable iff (!rst_n)
        $rose(ebreak_in_mem) |-> ##[0:2] cpu_break;
    endproperty
    
    assert_cpu_break_timing: assert property (cpu_break_response_timing)
        else $error("[EBREAK_DEBUG] cpu_break did not assert within 2 cycles of EBREAK @ %0t", $time);
    
    //==========================================================================
    // ASSERTION 6: No Multiple EBREAK in Pipeline
    //==========================================================================
    // パイプライン内に複数のEBREAKが存在しないことを確認
    
    property single_ebreak_in_pipeline;
        @(posedge clk) disable iff (!rst_n)
        (ebreak_in_if + ebreak_in_id + ebreak_in_ex + ebreak_in_mem) <= 1;
    endproperty
    
    assert_single_ebreak: assert property (single_ebreak_in_pipeline)
        else $warning("[EBREAK_DEBUG] Multiple EBREAK instructions in pipeline @ %0t", $time);
    
    //==========================================================================
    // DEBUG MONITORS (Continuous Display)
    //==========================================================================
    
    always @(posedge clk) begin
        // IF段階でのEBREAK検出
        if (ebreak_in_if) begin
            $display("[EBREAK_DEBUG] @ %0t: EBREAK in IF stage, PC=0x%h, insn=0x%h", 
                     $time, if_pc, if_insn);
        end
        
        // ID段階でのEBREAK検出
        if (ebreak_in_id) begin
            $display("[EBREAK_DEBUG] @ %0t: EBREAK in ID stage, PC=0x%h, is_ebreak=%b", 
                     $time, id_pc, id_ctrl.is_ebreak);
        end
        
        // EX段階でのEBREAK検出
        if (ebreak_in_ex) begin
            $display("[EBREAK_DEBUG] @ %0t: EBREAK in EX stage, PC=0x%h", 
                     $time, ex_pc);
        end
        
        // MEM段階でのEBREAK検出（最重要）
        if (ebreak_in_mem) begin
            $display("[EBREAK_DEBUG] @ %0t: ★★★ EBREAK in MEM stage, PC=0x%h, mem_valid=%b ★★★", 
                     $time, mem_pc, mem_valid);
            $display("              cpu_break=%b, cpu_halted=%b, running=%b", 
                     cpu_break, cpu_halted, running);
        end
        
        // フラッシュ信号の監視
        if (if_flush || id_flush || ex_flush) begin
            $display("[EBREAK_DEBUG] @ %0t: FLUSH detected - if_flush=%b, id_flush=%b, ex_flush=%b", 
                     $time, if_flush, id_flush, ex_flush);
            if (ebreak_in_if || ebreak_in_id || ebreak_in_ex) begin
                $display("              ⚠️  WARNING: EBREAK may be flushed!");
            end
        end
        
        // cpu_break信号の変化
        if ($rose(cpu_break)) begin
            $display("[EBREAK_DEBUG] @ %0t: ✅ cpu_break ASSERTED", $time);
        end
        
        if ($fell(cpu_break)) begin
            $display("[EBREAK_DEBUG] @ %0t: cpu_break DEASSERTED", $time);
        end
    end
    
    //==========================================================================
    // ERROR SUMMARY: Pipeline Blockage Detection
    //==========================================================================
    // EBREAKがIF段階で検出されたのにMEMに到達しない場合のサマリー
    
    logic [3:0] ebreak_seen_stages;  // [IF, ID, EX, MEM]
    logic ebreak_tracking;
    logic [31:0] ebreak_pc_tracked;
    int cycle_counter;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ebreak_seen_stages <= 4'b0000;
            ebreak_tracking <= 1'b0;
            ebreak_pc_tracked <= 32'h0;
            cycle_counter <= 0;
        end else begin
            // EBREAKのトラッキング開始
            if (ebreak_in_if && !ebreak_tracking) begin
                ebreak_tracking <= 1'b1;
                ebreak_seen_stages <= 4'b0001;  // IF
                ebreak_pc_tracked <= if_pc;
                cycle_counter <= 0;
                $display("[EBREAK_DEBUG] @ %0t: 🔍 Started tracking EBREAK at PC=0x%h", $time, if_pc);
            end
            
            // 各段階での検出記録
            if (ebreak_tracking) begin
                cycle_counter <= cycle_counter + 1;
                
                if (ebreak_in_id && !ebreak_seen_stages[1]) begin
                    ebreak_seen_stages[1] <= 1'b1;
                    $display("[EBREAK_DEBUG] @ %0t: 📍 EBREAK reached ID (cycle %0d)", $time, cycle_counter);
                end
                
                if (ebreak_in_ex && !ebreak_seen_stages[2]) begin
                    ebreak_seen_stages[2] <= 1'b1;
                    $display("[EBREAK_DEBUG] @ %0t: 📍 EBREAK reached EX (cycle %0d)", $time, cycle_counter);
                end
                
                if (ebreak_in_mem) begin
                    ebreak_seen_stages[3] <= 1'b1;
                    $display("[EBREAK_DEBUG] @ %0t: ✅ EBREAK reached MEM (cycle %0d)", $time, cycle_counter);
                    ebreak_tracking <= 1'b0;  // トラッキング終了
                end
            end
            
            // タイムアウト: 10サイクル経ってもMEMに到達しない
            if (ebreak_tracking && cycle_counter >= 10) begin
                $error("[EBREAK_DEBUG] ❌ TIMEOUT: EBREAK at PC=0x%h did not reach MEM after %0d cycles", 
                       ebreak_pc_tracked, cycle_counter);
                $error("              Stages reached: IF=%b, ID=%b, EX=%b, MEM=%b", 
                       ebreak_seen_stages[0], ebreak_seen_stages[1], 
                       ebreak_seen_stages[2], ebreak_seen_stages[3]);
                
                // 最後に検出されたステージを特定
                if (!ebreak_seen_stages[1]) begin
                    $error("              ⚠️  EBREAK lost between IF→ID");
                end else if (!ebreak_seen_stages[2]) begin
                    $error("              ⚠️  EBREAK lost between ID→EX");
                end else if (!ebreak_seen_stages[3]) begin
                    $error("              ⚠️  EBREAK lost between EX→MEM");
                end
                
                ebreak_tracking <= 1'b0;
                ebreak_seen_stages <= 4'b0000;
            end
        end
    end
    
    //==========================================================================
    // COVERAGE: EBREAK Execution Path
    //==========================================================================
    
    covergroup ebreak_debug_coverage @(posedge clk);
        option.per_instance = 1;
        option.name = "ebreak_debug_cov";
        
        ebreak_if: coverpoint ebreak_in_if {
            bins detected = {1};
        }
        
        ebreak_id: coverpoint ebreak_in_id {
            bins detected = {1};
        }
        
        ebreak_ex: coverpoint ebreak_in_ex {
            bins detected = {1};
        }
        
        ebreak_mem: coverpoint ebreak_in_mem {
            bins detected = {1};
        }
        
        flush_during_ebreak: coverpoint (if_flush || id_flush || ex_flush) {
            bins no_flush = {0};
            bins flush_active = {1};
        }
        
        // EBREAK到達パスのクロス
        ebreak_path: cross ebreak_if, ebreak_id, ebreak_ex, ebreak_mem;
    endgroup
    
    ebreak_debug_coverage ebreak_debug_cov = new();

endmodule : rv32i_ebreak_debug_spec
