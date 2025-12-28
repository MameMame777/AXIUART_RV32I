
# TD4UART Educational CPU (16-bit Minimal-RISC) — Specification Plan (v0.1 Draft)

## 0. Purpose

This document defines a **teachable** yet **non-trivial** CPU to be integrated into the TD4UART project.
The key requirement is **debuggability via AXIUART**: a host PC communicates over UART, the UART-to-AXI4-Lite bridge performs memory-mapped register access, and the CPU can be halted/stepped/inspected without JTAG.

The intent is to produce an implementation that is:

- Simple enough for logic-circuit education (clear datapath/control separation)
- Complex enough to demonstrate a real CPU (register file, ALU, load/store, branches, stack)
- Practical to debug using the existing AXI4-Lite register block infrastructure

This is a **v0.1 draft**: it is concrete enough to implement, but leaves room for future extensions.

## 1. Top-Level Design Choices (Locked for v1)

- **CPU data width:** 16-bit
- **Register file:** 8 GPRs (`R0..R7`), each 16-bit
- **Special registers:** `PC` (16-bit), `SP` (16-bit), `FLAGS` (Z/N/C)
- **Instruction width:** 16-bit fixed; some instructions use an **extra 16-bit word** (2-word instruction)
- **Microarchitecture:** multi-cycle FSM (FETCH/DECODE/EXEC/MEM/WB)
- **Stack:** supported (CALL/RET and PUSH/POP)
- **Memory addressing:** word-addressed (address selects a 16-bit word)
- **Debug transport:** UART -> AXIUART protocol -> AXI4-Lite -> Register_Block

Non-goals for v1:

- Pipelining, caches, interrupts
- CPU as an AXI master for instruction/data fetch
- Non-intrusive debug while running (v1 debug memory access requires CPU halted)

## 2. Integration Strategy

### 2.1 Why extend the existing Register Block

The current top-level architecture is:

Host UART -> UART-AXI4 bridge (AXI master) -> AXI4-Lite slave Register_Block

There is **only one AXI slave** in the design today. The cleanest v1 is to **extend the same Register_Block** with additional registers for CPU debug and (optionally) CPU-attached internal RAM control.

### 2.2 Register map SSOT requirement

This repository uses JSON-based SSOT:

`register_map/axiuart_registers.json` -> generated SV/Python/Markdown

Therefore, any new CPU/debug registers must be added to the JSON and then regenerated.

### 2.3 ISA SSOT requirement

The ISA encoding is also treated as **SSOT** to prevent drift between RTL decode, software tooling, and documentation.

- SSOT source: `isa/td4cpu_isa.json`
- Generator: `software/axiuart_driver/tools/gen_cpu_isa.py`
- Generated outputs:
	- `rtl/cpu/td4cpu_isa_pkg.sv`
	- `software/td4cpu/isa.py`
	- `docs/ISA.md`

Regeneration command:

```bash
python software/axiuart_driver/tools/gen_cpu_isa.py --in isa/td4cpu_isa.json
```

## 3. CPU Architectural State

### 3.1 Registers

- `R0..R7`: 16-bit general-purpose
- `PC`: 16-bit **word address** (points to the next instruction word)
- `SP`: 16-bit **word address**
- `FLAGS`: at minimum
	- `Z`: zero
	- `N`: negative (sign bit of the 16-bit result)
	- `C`: carry/borrow (see flag rules below)

### 3.2 Reset

- Reset is synchronous, active-high (`rst`).
- On reset:
	- `PC <= RESET_VECTOR` (default: 0x0000)
	- `SP <= RESET_SP` (default: 0xFFFE or another chosen top-of-RAM word address)
	- `FLAGS <= 0`
	- If `HALT_ON_RESET` debug bit is set, CPU enters HALTED state after reset.

### 3.3 Memory model (v1)

- Word-addressed memory.
- `MEM[addr]` is a 16-bit word.

Notes:

- Keeping everything word-addressed eliminates unaligned/byte-lane complexity.
- Byte access can be a v2 extension.

## 4. Multi-cycle Control (Implementation Guidance)

Recommended state machine:

1. `FETCH1`: place `PC` on memory address, start read
2. `FETCH2`: latch instruction word into `IR`, `PC <= PC + 1`
3. `DECODE`: decode opcode, select regs, compute immediates
4. `EXT_FETCH1/2` (only for 2-word instructions): fetch immediate/target word into `IMM16`, `PC <= PC + 1`
5. `EXEC`: perform ALU op / branch decision / effective address calculation
6. `MEM`: perform data memory read/write (for LD/ST and stack ops)
7. `WB`: writeback to reg file and/or flags
8. `HALTED`: CPU clocked but does not advance architectural state unless stepping

For debugging quality:

- Breakpoints should be checked at a single, well-defined boundary: **at instruction fetch boundary** (before executing the instruction at PC).
- `STEP` should execute exactly one architectural instruction (including any extension word fetch).

## 5. Instruction Set Architecture (Minimal-RISC v1)

### 5.1 Summary

The ISA is intentionally small and regular:

- A small set of ALU ops
- One load and one store addressing mode (base + signed offset)
- A single branch instruction with conditions
- Absolute `JMP16` / `CALL16` using a second word (debug-friendly)
- Stack operations
- A `BRK` instruction for software breakpoints

Target size: ~25 instructions.

### 5.2 Addressing conventions

- All offsets for control-flow and memory are in **words**, not bytes.
- `PC` is a word address.

### 5.3 Register encoding

- Registers `R0..R7` are encoded as 3-bit values.

### 5.4 Instruction formats

All instructions are 16-bit. Bit numbering `[15:0]`.

#### Format R (register-register ALU)

- `[15:12]` `OP = 0x0`
- `[11:9]`  `rd`
- `[8:6]`   `rs`
- `[5:0]`   `funct`

#### Format I (register + imm9)

- `[15:12]` `OP`
- `[11:9]`  `rd`
- `[8:0]`   `imm9`

#### Format M (load/store base+off6)

- `[15:12]` `OP`
- `[11:9]`  `rD` (dest for LD, source for ST)
- `[8:6]`   `rB` (base)
- `[5:0]`   `off6` (signed)

#### Format B (branch cond + off9)

- `[15:12]` `OP = 0x5`
- `[11:9]`  `cond`
- `[8:0]`   `off9` (signed)

#### Format X (extended 2-word)

Word0:

- `[15:12]` `OP`
- Remaining bits encode sub-op / optional register

Word1:

- `imm16` (absolute target or constant)

#### Format S (stack)

This is a dedicated stack encoding so that both `PUSH` and `POP` carry a register operand.

- `[15:12]` `OP = 0x7`
- `[11:9]`  `r` (register operand)
- `[8]`     `dir` (0 = PUSH, 1 = POP)
- `[7:0]`   must be zero

### 5.5 Flag rules

Flags are updated as follows:

- `Z`: set if result == 0
- `N`: set if result[15] == 1
- `C`:
	- For `ADD`: carry-out of bit 15
	- For `SUB`/`CMP`: set to 1 if **no borrow** (i.e., `rd >= rs` in unsigned sense)

Logic ops (`AND/OR/XOR`) set `Z`/`N` and leave `C` unchanged (simplest for teaching).

### 5.6 Opcode allocation (v1)

#### OP = 0x0 (R-format ALU, via `funct`)

| funct | Mnemonic | Operation |
|------:|----------|-----------|
| 0x00  | ADD      | `rd = rd + rs` |
| 0x01  | SUB      | `rd = rd - rs` |
| 0x02  | AND      | `rd = rd & rs` |
| 0x03  | OR       | `rd = rd \| rs` |
| 0x04  | XOR      | `rd = rd ^ rs` |
| 0x05  | CMP      | flags from `rd - rs`, no writeback |
| 0x06  | SHL1     | `rd = rd << 1` (shift by 1) |
| 0x07  | SHR1     | `rd = rd >> 1` (logical shift by 1) |
| 0x08  | MOV      | `rd = rs` (flags unchanged) |

Note: MOV as R-format avoids burning an opcode.

#### OP = 0x1 (I-format)

- `LDI rd, imm9` (zero-extend)

#### OP = 0x2 (I-format)

- `ADDI rd, imm9` (sign-extend)

#### OP = 0x3 (M-format)

- `LD rd, [rB + off6]`

#### OP = 0x4 (M-format)

- `ST rD, [rB + off6]` (store the value in rD)

#### OP = 0x5 (B-format)

- `BR cond, off9`

Condition encoding (`cond[2:0]`):

| cond | Meaning |
|-----:|---------|
| 0    | AL (always) |
| 1    | Z |
| 2    | NZ |
| 3    | C |
| 4    | NC |
| 5    | N |
| 6    | NN (not negative) |
| 7    | reserved |

Branch behavior:

- If taken: `PC <= PC + signext(off9)`
- If not taken: PC unchanged (already points to next instruction due to fetch stage)

#### OP = 0x6 (system / control)

Encode subops using lower bits. v1 reserves:

- `RET`
- `BRK` (software breakpoint)

Exact encoding:

- `RET`: `OP=0x6`, remaining bits all zero
- `BRK`: `OP=0x6`, `[0]=1` (all other bits zero)

#### OP = 0x7 (stack)

Use Format S:

- `PUSH r`: `OP=0x7`, `r=reg`, `dir=0`, `[7:0]=0`
- `POP r`:  `OP=0x7`, `r=reg`, `dir=1`, `[7:0]=0`

#### OP = 0xA (extended absolute jump)

- `JMP16 imm16` (2-word)
	- Word0: `OP=0xA`, remaining bits zero
	- Word1: target PC word address

#### OP = 0xB (extended absolute call)

- `CALL16 imm16` (2-word)
	- Word0: `OP=0xB`, remaining bits zero
	- Word1: target PC word address

CALL behavior:

- Push return PC (already points to next instruction after consuming Word1)
- Jump to `imm16`

### 5.7 Stack behavior details

Define SP as “next free word”.

- `PUSH x`:
	- `SP <= SP - 1`
	- `MEM[SP] <= x` (after decrement)
- `POP x`:
	- `x <= MEM[SP]`
	- `SP <= SP + 1`

## 6. Debugging Model over AXIUART

### 6.1 Debug requirements

- Halt / Run / Single-step
- Read/write: PC, SP, FLAGS, general registers (when halted)
- Breakpoints: at least 2 PC breakpoints
- Memory read/write via debug registers (when halted)
- Record halt reason

### 6.2 “Stop-the-world” rule (v1)

To keep v1 implementation safe and simple:

- Debug register writes that affect CPU state are only honored when `HALTED=1`.
- Debug memory operations are only permitted when `HALTED=1`.

If a forbidden operation is attempted while running, set an error bit in status.

### 6.3 Debug register block layout

Register map constraints (existing project convention):

- Base address is `0x1000`.
- Stride is 4 bytes (32-bit registers).
- Addresses and names should be defined in `register_map/axiuart_registers.json` and generated.

Recommended placement: allocate CPU/debug registers starting at **offset 0x200** (absolute address `0x1200`) to avoid collisions with current registers.

All registers are 32-bit; use `[15:0]` for CPU 16-bit values and keep `[31:16]` reserved.

#### CPU_DBG_CTRL (RW) @ BASE+0x200

- bit0 `HALT_REQ` (write 1: request halt; self-clears)
- bit1 `RUN_REQ`  (write 1: run/continue; self-clears)
- bit2 `STEP_REQ` (write 1: execute one instruction; self-clears)
- bit3 `HALT_ON_RESET` (RW, sticky)
- bit4 `CLR_HALT_REASON` (write 1; self-clears)
- bit8 `BP_GLOBAL_EN` (RW)

#### CPU_DBG_STATUS (RO) @ BASE+0x204

- bit0 `HALTED`
- bit1 `RUNNING`
- bit2 `BREAK_HIT`
- bit3 `BRK_HIT`
- bits15:8 `HALT_REASON` enum:
	- 1 reset-halt
	- 2 external halt request
	- 3 step complete
	- 4 breakpoint
	- 5 BRK instruction

#### CPU_PC (RW when halted) @ BASE+0x208

- `[15:0]` PC

#### CPU_SP (RW when halted) @ BASE+0x20C

- `[15:0]` SP

#### CPU_FLAGS (RW when halted) @ BASE+0x210

- bit0 Z, bit1 N, bit2 C

#### CPU_REG_INDEX (RW) @ BASE+0x214

- `[2:0]` register index (0..7)

#### CPU_REG_DATA (RW when halted) @ BASE+0x218

- `[15:0]` selected register value

#### CPU_BP0_PC (RW) @ BASE+0x21C

- `[15:0]` breakpoint 0 PC match

#### CPU_BP1_PC (RW) @ BASE+0x220

- `[15:0]` breakpoint 1 PC match

#### CPU_BP_CTRL (RW) @ BASE+0x224

- bit0 `BP0_EN`
- bit1 `BP1_EN`
- bit2 `BP_MATCH_FETCH` (recommended 1; match at fetch boundary)

#### CPU_MEM_ADDR (RW) @ BASE+0x228

- `[15:0]` word address

#### CPU_MEM_WDATA (WO) @ BASE+0x22C

- `[15:0]` write data

#### CPU_MEM_RDATA (RO) @ BASE+0x230

- `[15:0]` read data

#### CPU_MEM_CTRL (RW) @ BASE+0x234

- bit0 `MEM_READ_REQ` (write 1 triggers read; self-clears)
- bit1 `MEM_WRITE_REQ` (write 1 triggers write; self-clears)
- bit2 `AUTO_INC` (RW)
- bit8 `MEM_BUSY` (RO)
- bit9 `MEM_ERR` (RO; set on invalid access or if CPU not halted)

#### CPU_ID (RO) @ BASE+0x238

- Version/build ID (implementation-defined)

### 6.4 Breakpoint semantics

- When enabled, compare the **next fetch PC** against BP registers.
- On match: enter `HALTED` before executing the instruction at that PC.

### 6.5 Step semantics

- A step executes exactly one **architectural instruction**.
- For 2-word instructions, the extension word is part of the same step.
- After step, CPU halts with reason “step complete”.

## 7. Verification Plan (Minimal but Effective)

### 7.1 CPU bring-up tests

1. Reset + HALT_ON_RESET
	 - Read PC/SP/FLAGS/R registers via debug registers
2. Register file R/W while halted
3. ALU correctness + flag correctness
4. LD/ST to internal memory
5. Stack correctness:
	 - PUSH/POP
	 - CALL16/RET return address correctness

### 7.2 Debug behavior tests over AXIUART

1. Halt/Run/Step sequencing is stable
2. Breakpoint hit halts at correct PC
3. BRK instruction halts with correct reason
4. Debug memory read/write works while halted
5. Debug memory op is rejected while running (`MEM_ERR=1`)

## 8. Implementation Milestones

1. Add CPU/debug registers to SSOT JSON and regenerate outputs
2. Implement CPU core + internal word RAM
3. Wire CPU debug signals to Register_Block extensions
4. Add at least one UVM or simplified test that:
	 - loads a small program into RAM
	 - runs to a BRK or breakpoint
	 - inspects registers over AXIUART

## 9. Open Items (Decisions to confirm later)

- Exact RAM size and reset initialization mechanism (hex/mem file vs hard-coded)
- Whether to expose an instruction for memory-mapped IO (not required for v1 debug)
- Whether to add `LUI` / `ORI` for easier constant formation (optional v1 extension)

