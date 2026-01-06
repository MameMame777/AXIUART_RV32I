# Memory Access (MEM) Stage - 詳細設計

**モジュール名:** `rv32i_mem`  
**ファイル:** `rtl/cpu/rv32i_mem.sv`  
**バージョン:** 1.1  
**最終更新:** 2026年1月5日

---

## 設計意図

MEMステージは**メモリアクセスとMMIO制御**を担当：

1. **ロード/ストア**: Block RAM Port Bへのアクセス
2. **アライメント**: バイト/ハーフワード/ワードの適切な処理
3. **MMIO デコード**: LED(0x407C)などのメモリマップドI/O
4. **例外検出**: アドレスミスアライメント、範囲外アクセス

### 主要な設計判断

#### 判断1: Block RAM Port Bを使用 ✅

**理由**:
- Port A: IF専用（命令フェッチ）
- Port B: MEM/Debug共用（データアクセス）
- デュアルポート構成で同時アクセス可能

#### 判断2: MMIOは0x4000-0x4FFF ✅

**MMIOレンジ**:
- 0x4000-0x4FFF: MMIO領域（LEDなど）
- 0x407C: LED制御レジスタ（32ビットライトオンリー）

**検出**:
```systemverilog
assign is_mmio = (ex_mem_alu_result[31:12] == 20'h00004);  // 0x4xxx
assign is_led = (ex_mem_alu_result == 32'h0000_407C);
```

---

## ブロック図

```
                ┌────────────────────────────────────────────┐
                │         rv32i_mem Module                   │
                │                                            │
 ex_mem_alu_res │  ┌──────────────────────────────────────┐  │
    [31:0] ─────┼─►│   Address Decoder                   │  │
                │  │                                      │  │
                │  │  RAM range: 0x0000-0x1FFF           │  │
                │  │  MMIO range: 0x4000-0x4FFF          │  │
                │  │  LED addr: 0x407C                   │  │
                │  └──────┬────────────┬──────────────────┘  │
                │         │            │                     │
                │         ▼            ▼                     │
                │   is_ram_access  is_mmio                   │
                │                                            │
 mem_read ──────┼──►┌──────────────────────────────────┐    │
 mem_write ─────┼──►│  Load/Store Control             │    │
                │   │                                  │    │
                │   │  Load:                           │    │
                │   │   - Generate RAM read addr       │    │
                │   │   - Wait 1 cycle for data        │    │
                │   │  Store:                          │    │
                │   │   - Generate RAM write addr      │    │
                │   │   - Apply byte/half/word mask   │    │
                │   └──────────┬───────────────────────┘    │
                │              │                            │
                │              ▼                            │
                │   ┌──────────────────────────────────┐    │
                │   │  Block RAM Port B Interface     │    │
                │   │  - data_ram_addr[10:0]          │───►│ to Block RAM
                │   │  - data_ram_wdata[31:0]         │───►│
                │   │  - data_ram_wen[3:0]            │───►│
                │   │  - data_ram_rdata[31:0]         │◄───│ from Block RAM
                │   └──────────┬───────────────────────┘    │
                │              │                            │
                │              ▼                            │
                │   ┌──────────────────────────────────┐    │
 mem_size[2:0]──┼──►│  Load Data Aligner              │    │
 mem_unsigned───┼──►│                                  │    │
                │   │  LB/LBU: byte → sign-ext/zero   │    │
                │   │  LH/LHU: halfword → sign-ext/zero│   │
                │   │  LW: word (no alignment)        │    │
                │   └──────────┬───────────────────────┘    │
                │              │ aligned_load_data          │
                │              │                            │
                │   ┌──────────▼───────────────────────┐    │
                │   │  Store Data Aligner             │    │
                │   │  (generates byte write enables) │    │
                │   │                                  │    │
                │   │  SB: byte_en = 4'b0001/0010/..  │    │
                │   │  SH: byte_en = 4'b0011/1100     │    │
                │   │  SW: byte_en = 4'b1111          │    │
                │   └──────────────────────────────────┘    │
                │                                            │
                │   ┌──────────────────────────────────┐    │
                │   │  Exception Detector              │    │
                │   │                                  │    │
                │   │  - Address misalignment         │    │
                │   │  - Out of range access          │    │
                │   └──────────────────────────────────┘    │
                │              │                            │
                │   ┌──────────▼───────────────────────┐    │
                │   │  MEM/WB Pipeline Register        │    │
                │   │                                  │    │
                │   │  - mem_wb_valid                  │    │
                │   │  - mem_wb_alu_result             │    │
                │   │  - mem_wb_load_data              │    │
                │   │  - mem_wb_ctrl                   │    │
                │   └──────────────────────────────────┘    │
                │              │                            │
                └──────────────┼────────────────────────────┘
                               ▼
                        to WB stage
```

---

## 機能詳細

### 3.1 アドレスデコード

```systemverilog
logic is_ram_access, is_mmio, is_led;

// RAMアクセス: 0x0000-0x1FFF (8KB)
assign is_ram_access = (ex_mem_alu_result[31:13] == 19'b0);

// MMIOアクセス: 0x4000-0x4FFF
assign is_mmio = (ex_mem_alu_result[31:12] == 20'h00004);

// LEDレジスタ: 0x407C
assign is_led = (ex_mem_alu_result == 32'h0000_407C);
```

### 3.2 ロードデータアライメント

```systemverilog
logic [31:0] aligned_load_data;
logic [1:0]  byte_offset;

assign byte_offset = ex_mem_alu_result[1:0];

always_comb begin
    case (ex_mem_ctrl.mem_size)
        3'b000: begin  // LB/LBU
            case (byte_offset)
                2'b00: aligned_load_data = ex_mem_ctrl.mem_unsigned ? 
                                          {24'h0, data_ram_rdata[7:0]} :
                                          {{24{data_ram_rdata[7]}}, data_ram_rdata[7:0]};
                2'b01: aligned_load_data = ex_mem_ctrl.mem_unsigned ?
                                          {24'h0, data_ram_rdata[15:8]} :
                                          {{24{data_ram_rdata[15]}}, data_ram_rdata[15:8]};
                // ...
            endcase
        end
        
        3'b001: begin  // LH/LHU
            case (byte_offset[1])
                1'b0: aligned_load_data = ex_mem_ctrl.mem_unsigned ?
                                         {16'h0, data_ram_rdata[15:0]} :
                                         {{16{data_ram_rdata[15]}}, data_ram_rdata[15:0]};
                1'b1: aligned_load_data = ex_mem_ctrl.mem_unsigned ?
                                         {16'h0, data_ram_rdata[31:16]} :
                                         {{16{data_ram_rdata[31]}}, data_ram_rdata[31:16]};
            endcase
        end
        
        3'b010: begin  // LW
            aligned_load_data = data_ram_rdata;
        end
        
        default: aligned_load_data = 32'h0;
    endcase
end
```

### 3.3 ストアデータアライメント

```systemverilog
logic [31:0] aligned_store_data;
logic [3:0]  byte_write_en;

always_comb begin
    case (ex_mem_ctrl.mem_size)
        3'b000: begin  // SB
            case (byte_offset)
                2'b00: begin
                    aligned_store_data = {24'h0, ex_mem_rs2_data[7:0]};
                    byte_write_en = 4'b0001;
                end
                2'b01: begin
                    aligned_store_data = {16'h0, ex_mem_rs2_data[7:0], 8'h0};
                    byte_write_en = 4'b0010;
                end
                // ...
            endcase
        end
        
        3'b001: begin  // SH
            case (byte_offset[1])
                1'b0: begin
                    aligned_store_data = {16'h0, ex_mem_rs2_data[15:0]};
                    byte_write_en = 4'b0011;
                end
                1'b1: begin
                    aligned_store_data = {ex_mem_rs2_data[15:0], 16'h0};
                    byte_write_en = 4'b1100;
                end
            endcase
        end
        
        3'b010: begin  // SW
            aligned_store_data = ex_mem_rs2_data;
            byte_write_en = 4'b1111;
        end
        
        default: begin
            aligned_store_data = 32'h0;
            byte_write_en = 4'b0000;
        end
    endcase
end

// Block RAM Port B書き込み
assign data_ram_addr = ex_mem_alu_result[12:2];  // ワードアドレス
assign data_ram_wdata = aligned_store_data;
assign data_ram_wen = (ex_mem_ctrl.mem_write && is_ram_access) ? byte_write_en : 4'b0000;
```

---

## 実装ガイド

### 4.1 MMIO実装

```systemverilog
// LED書き込み
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        mmio_led_reg <= 32'h0;
    else if (ex_mem_ctrl.mem_write && is_led && ex_mem_valid)
        mmio_led_reg <= ex_mem_rs2_data;
end
```

### 4.2 例外検出

```systemverilog
logic addr_misaligned;

// ワードアクセス: 4バイト境界
// ハーフワードアクセス: 2バイト境界
assign addr_misaligned = (ex_mem_ctrl.mem_size == 3'b010 && ex_mem_alu_result[1:0] != 2'b00) ||
                        (ex_mem_ctrl.mem_size == 3'b001 && ex_mem_alu_result[0] != 1'b0);

assign mem_exception = addr_misaligned && (ex_mem_ctrl.mem_read || ex_mem_ctrl.mem_write);
```

---

## デバッグガイド

```systemverilog
`ifdef DEBUG_MEM_STAGE
always @(posedge clk) begin
    if (ex_mem_ctrl.mem_write)
        $display("[MEM_DEBUG] Store: addr=0x%08X, data=0x%08X, size=%0d, wen=%b",
                 ex_mem_alu_result, ex_mem_rs2_data, ex_mem_ctrl.mem_size, byte_write_en);
    if (ex_mem_ctrl.mem_read)
        $display("[MEM_DEBUG] Load: addr=0x%08X, rdata=0x%08X, aligned=0x%08X",
                 ex_mem_alu_result, data_ram_rdata, aligned_load_data);
end
`endif
```

---

## 関連ドキュメント

- **[04_ex_stage.md](04_ex_stage.md)** - ALU結果（アドレス）
- **[06_wb_stage.md](06_wb_stage.md)** - ロードデータの書き戻し

---

**このドキュメントの目的**: 
MEMステージの**ロード/ストアアライメント**、**MMIO処理**を理解し、正確に実装できる知識を提供します。
