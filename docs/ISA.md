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
