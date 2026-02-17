# TD4CPU ISA (AUTO-GENERATED)

**AUTO-GENERATED FILE - DO NOT EDIT MANUALLY**

- Source: td4cpu_isa.json
- Generated: 2025-12-29 19:43:44

## Opcodes

| Name | Value |
|------|-------|
| R_ALU | 0x0 |
| LDI | 0x1 |
| ADDI | 0x2 |
| LD | 0x3 |
| ST | 0x4 |
| BR | 0x5 |
| SYS | 0x6 |
| STACK | 0x7 |
| JMP16 | 0xA |
| CALL16 | 0xB |

## R-format funct

| Mnemonic | funct |
|----------|-------|
| ADD | 0x00 |
| SUB | 0x01 |
| AND | 0x02 |
| OR | 0x03 |
| XOR | 0x04 |
| CMP | 0x05 |
| SHL1 | 0x06 |
| SHR1 | 0x07 |
| MOV | 0x08 |

## Branch conditions

| Cond | Value |
|------|-------|
| AL | 0 |
| Z | 1 |
| NZ | 2 |
| C | 3 |
| NC | 4 |
| N | 5 |
| NN | 6 |

## Branch Delay Slot

The TD4CPU implements a MIPS/SPARC-style **branch delay slot** architecture. When a BR instruction executes:

1. **Delay Slot Semantics**: The instruction immediately following BR (at PC_BR + 1) ALWAYS executes before the branch is taken
2. **Unconditional Execution**: The delay slot instruction executes regardless of whether the branch condition is met
3. **Timing**: BR takes 2 cycles total (1 for BR decode + condition evaluation, 1 for delay slot execution)

**Example**:
```assembly
0x0002: BR.AL +3      ; Branch always to PC+1+3 = 0x0006
0x0003: LDI R7, #22   ; Delay slot - ALWAYS executes
0x0004: LDI R0, #10   ; Skipped (not in delay slot)
0x0005: LDI R0, #11   ; Skipped
0x0006: LDI R1, #0xFF ; Branch target
```

**Execution Sequence**:
- Cycle 1: BR decoded, condition evaluated (always true)
- Cycle 2: LDI R7, #22 executes (delay slot), PC updated to 0x0006
- Cycle 3: LDI R1, #0xFF fetched from branch target

**Restrictions**:
- **No BR in delay slot**: A BR instruction cannot be placed in another BR's delay slot (undefined behavior)
- **LD/ST Caution**: Memory operations in delay slot are legal but increase complexity

**Programming Guidelines**:
- Fill delay slot with useful instruction (e.g., loop counter increment)
- Use NOP (or any harmless instruction) if no useful work available
- For loops, place loop counter adjustment in delay slot for efficiency

## Instruction list

| Mnemonic | Format | Words | Operands |
|----------|--------|-------|----------|
| ADD | R | 1 | rd, rs |
| SUB | R | 1 | rd, rs |
| AND | R | 1 | rd, rs |
| OR | R | 1 | rd, rs |
| XOR | R | 1 | rd, rs |
| CMP | R | 1 | rd, rs |
| SHL1 | R | 1 | rd |
| SHR1 | R | 1 | rd |
| MOV | R | 1 | rd, rs |
| LDI | I | 1 | rd, imm9u |
| ADDI | I | 1 | rd, imm9s |
| LD | M | 1 | rD, rB, off6s |
| ST | M | 1 | rD, rB, off6s |
| BR | B | 1 | cond, off9s |
| RET | SYS | 1 |  |
| BRK | SYS | 1 |  |
| PUSH | S | 1 | r |
| POP | S | 1 | r |
| JMP16 | X | 2 | imm16 |
| CALL16 | X | 2 | imm16 |
