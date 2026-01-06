# RV32I Control Flow Diagrams

**Document Type:** Control Flow Specification  
**Version:** 1.0  
**Date:** January 4, 2026  
**Status:** Design Phase - Pre-Implementation

---

## Table of Contents

1. [Overview](#overview)
2. [Hazard Detection State Machine](#hazard-detection-state-machine)
3. [Forwarding Priority Selection](#forwarding-priority-selection)
4. [Stall/Flush Propagation](#stallflush-propagation)
5. [Branch/Jump Control Flow](#branchjump-control-flow)
6. [Exception Trap Sequence](#exception-trap-sequence)
7. [MRET Return Sequence](#mret-return-sequence)
8. [Memory Arbitration State Machine](#memory-arbitration-state-machine)
9. [References](#references)

---

## Overview

This document provides Mermaid state machine and flowchart diagrams for key control logic components in the RV32I modular processor. These diagrams complement the module specifications by visualizing complex decision trees and state transitions.

### Document Purpose

- **Design Review:** Visualize control flow for architectural validation
- **Implementation Reference:** Guide RTL coding with clear decision logic
- **Verification Planning:** Identify state coverage requirements
- **Debugging Aid:** Trace control flow during simulation analysis

---

## Hazard Detection State Machine

### 2.1 RAW Hazard Detection Flow

```mermaid
flowchart TD
    START([RAW Hazard Check])
    
    CHECK_RS1{ID stage<br/>uses RS1?}
    CHECK_RS2{ID stage<br/>uses RS2?}
    
    RS1_X0{RS1 == x0?}
    RS2_X0{RS2 == x0?}
    
    RS1_EX{RS1 == EX.rd?}
    RS1_MEM{RS1 == MEM.rd?}
    RS1_WB{RS1 == WB.rd?}
    
    RS2_EX{RS2 == EX.rd?}
    RS2_MEM{RS2 == MEM.rd?}
    RS2_WB{RS2 == WB.rd?}
    
    HAZARD_RS1_EX[RS1 Hazard: EX]
    HAZARD_RS1_MEM[RS1 Hazard: MEM]
    HAZARD_RS1_WB[RS1 Hazard: WB]
    NO_HAZARD_RS1[RS1 No Hazard]
    
    HAZARD_RS2_EX[RS2 Hazard: EX]
    HAZARD_RS2_MEM[RS2 Hazard: MEM]
    HAZARD_RS2_WB[RS2 Hazard: WB]
    NO_HAZARD_RS2[RS2 No Hazard]
    
    FORWARD[Set Forwarding<br/>Control Signals]
    END([End])
    
    START --> CHECK_RS1
    START --> CHECK_RS2
    
    CHECK_RS1 -->|No| NO_HAZARD_RS1
    CHECK_RS1 -->|Yes| RS1_X0
    
    RS1_X0 -->|Yes| NO_HAZARD_RS1
    RS1_X0 -->|No| RS1_EX
    
    RS1_EX -->|Yes & EX.rf_wen| HAZARD_RS1_EX
    RS1_EX -->|No| RS1_MEM
    
    RS1_MEM -->|Yes & MEM.rf_wen| HAZARD_RS1_MEM
    RS1_MEM -->|No| RS1_WB
    
    RS1_WB -->|Yes & WB.rf_wen| HAZARD_RS1_WB
    RS1_WB -->|No| NO_HAZARD_RS1
    
    CHECK_RS2 -->|No| NO_HAZARD_RS2
    CHECK_RS2 -->|Yes| RS2_X0
    
    RS2_X0 -->|Yes| NO_HAZARD_RS2
    RS2_X0 -->|No| RS2_EX
    
    RS2_EX -->|Yes & EX.rf_wen| HAZARD_RS2_EX
    RS2_EX -->|No| RS2_MEM
    
    RS2_MEM -->|Yes & MEM.rf_wen| HAZARD_RS2_MEM
    RS2_MEM -->|No| RS2_WB
    
    RS2_WB -->|Yes & WB.rf_wen| HAZARD_RS2_WB
    RS2_WB -->|No| NO_HAZARD_RS2
    
    HAZARD_RS1_EX --> FORWARD
    HAZARD_RS1_MEM --> FORWARD
    HAZARD_RS1_WB --> FORWARD
    NO_HAZARD_RS1 --> FORWARD
    
    HAZARD_RS2_EX --> FORWARD
    HAZARD_RS2_MEM --> FORWARD
    HAZARD_RS2_WB --> FORWARD
    NO_HAZARD_RS2 --> FORWARD
    
    FORWARD --> END
    
    style HAZARD_RS1_EX fill:#ff6b6b
    style HAZARD_RS1_MEM fill:#ffa500
    style HAZARD_RS1_WB fill:#ffd700
    style HAZARD_RS2_EX fill:#ff6b6b
    style HAZARD_RS2_MEM fill:#ffa500
    style HAZARD_RS2_WB fill:#ffd700
    style NO_HAZARD_RS1 fill:#90ee90
    style NO_HAZARD_RS2 fill:#90ee90
```

---

### 2.2 Load-Use Hazard Detection

```mermaid
flowchart TD
    START([Load-Use Check])
    
    EX_LOAD{EX stage<br/>is Load?}
    ID_USE_RS1{ID uses<br/>RS1?}
    ID_USE_RS2{ID uses<br/>RS2?}
    
    RS1_MATCH{RS1 ==<br/>EX.rd?}
    RS2_MATCH{RS2 ==<br/>EX.rd?}
    
    STALL[Assert Stall<br/>stall_pipeline = 1]
    BUBBLE[Insert Bubble<br/>in EX stage]
    NO_STALL[No Stall<br/>stall_pipeline = 0]
    
    END([End])
    
    START --> EX_LOAD
    
    EX_LOAD -->|No| NO_STALL
    EX_LOAD -->|Yes| ID_USE_RS1
    EX_LOAD --> ID_USE_RS2
    
    ID_USE_RS1 -->|Yes| RS1_MATCH
    ID_USE_RS1 -->|No| ID_USE_RS2
    
    ID_USE_RS2 -->|Yes| RS2_MATCH
    ID_USE_RS2 -->|No| NO_STALL
    
    RS1_MATCH -->|Yes| STALL
    RS1_MATCH -->|No| ID_USE_RS2
    
    RS2_MATCH -->|Yes| STALL
    RS2_MATCH -->|No| NO_STALL
    
    STALL --> BUBBLE
    BUBBLE --> END
    NO_STALL --> END
    
    style STALL fill:#ff6b6b
    style BUBBLE fill:#ffa500
    style NO_STALL fill:#90ee90
```

---

## Forwarding Priority Selection

### 3.1 RS1 Forwarding Multiplexer Control

```mermaid
flowchart TD
    START([Select RS1<br/>Source])
    
    EX_HAZARD{EX stage<br/>RAW hazard?}
    MEM_HAZARD{MEM stage<br/>RAW hazard?}
    WB_HAZARD{WB stage<br/>RAW hazard?}
    
    FWD_EX[forward_rs1_sel = 01<br/>Source: EX result]
    FWD_MEM[forward_rs1_sel = 10<br/>Source: MEM result]
    FWD_WB[forward_rs1_sel = 11<br/>Source: WB result]
    FWD_ID[forward_rs1_sel = 00<br/>Source: ID register]
    
    END([EX Stage<br/>Receives Data])
    
    START --> EX_HAZARD
    
    EX_HAZARD -->|Yes| FWD_EX
    EX_HAZARD -->|No| MEM_HAZARD
    
    MEM_HAZARD -->|Yes| FWD_MEM
    MEM_HAZARD -->|No| WB_HAZARD
    
    WB_HAZARD -->|Yes| FWD_WB
    WB_HAZARD -->|No| FWD_ID
    
    FWD_EX --> END
    FWD_MEM --> END
    FWD_WB --> END
    FWD_ID --> END
    
    style FWD_EX fill:#ff6b6b
    style FWD_MEM fill:#ffa500
    style FWD_WB fill:#ffd700
    style FWD_ID fill:#90ee90
```

**Priority Encoding:**
```
EX > MEM > WB > ID (highest to lowest priority)
```

**Rationale:** Newer data (closer to EX) takes precedence over older data.

---

### 3.2 RS2 Forwarding Multiplexer Control

```mermaid
flowchart TD
    START([Select RS2<br/>Source])
    
    EX_HAZARD{EX stage<br/>RAW hazard?}
    MEM_HAZARD{MEM stage<br/>RAW hazard?}
    WB_HAZARD{WB stage<br/>RAW hazard?}
    
    FWD_EX[forward_rs2_sel = 01<br/>Source: EX result]
    FWD_MEM[forward_rs2_sel = 10<br/>Source: MEM result]
    FWD_WB[forward_rs2_sel = 11<br/>Source: WB result]
    FWD_ID[forward_rs2_sel = 00<br/>Source: ID register]
    
    END([EX Stage<br/>Receives Data])
    
    START --> EX_HAZARD
    
    EX_HAZARD -->|Yes| FWD_EX
    EX_HAZARD -->|No| MEM_HAZARD
    
    MEM_HAZARD -->|Yes| FWD_MEM
    MEM_HAZARD -->|No| WB_HAZARD
    
    WB_HAZARD -->|Yes| FWD_WB
    WB_HAZARD -->|No| FWD_ID
    
    FWD_EX --> END
    FWD_MEM --> END
    FWD_WB --> END
    FWD_ID --> END
    
    style FWD_EX fill:#ff6b6b
    style FWD_MEM fill:#ffa500
    style FWD_WB fill:#ffd700
    style FWD_ID fill:#90ee90
```

**Note:** RS2 forwarding logic is identical to RS1 (independent parallel paths).

---

## Stall/Flush Propagation

### 4.1 Pipeline Control State Machine

```mermaid
stateDiagram-v2
    [*] --> NORMAL
    
    NORMAL: Normal Execution
    STALLED: Pipeline Stalled
    FLUSHING: Pipeline Flushing
    
    NORMAL --> STALLED: Load-Use Hazard
    NORMAL --> FLUSHING: Branch Taken
    NORMAL --> FLUSHING: Jump (JAL/JALR)
    NORMAL --> FLUSHING: Exception Trap
    NORMAL --> FLUSHING: MRET
    
    STALLED --> NORMAL: Stall Cleared (1 cycle)
    STALLED --> FLUSHING: Branch in IF during stall
    
    FLUSHING --> NORMAL: Flush Complete (1 cycle)
    
    note right of NORMAL
        IF: Fetch next PC+4
        ID: Decode instruction
        EX: Execute
        MEM: Memory access
        WB: Register write
    end note
    
    note right of STALLED
        IF: Hold PC
        ID: Hold instruction
        EX: Insert bubble (NOP)
        MEM: Continue
        WB: Continue
    end note
    
    note right of FLUSHING
        IF: Redirect to target PC
        ID: Flush (bubble)
        EX: Flush (bubble)
        MEM: Flush (bubble, except trap source)
        WB: Continue
    end note
```

---

### 4.2 Stall Signal Propagation

```mermaid
flowchart LR
    HAZARD[Hazard Unit<br/>Load-Use Detected]
    
    IF_STALL[IF Stage<br/>pc_hold = 1]
    ID_STALL[ID Stage<br/>insn_hold = 1]
    EX_BUBBLE[EX Stage<br/>Insert Bubble]
    MEM_CONT[MEM Stage<br/>Continue]
    WB_CONT[WB Stage<br/>Continue]
    
    HAZARD -->|stall_pipeline| IF_STALL
    HAZARD -->|stall_pipeline| ID_STALL
    HAZARD -->|insert_bubble| EX_BUBBLE
    
    IF_STALL -->|Hold PC| IF_STALL
    ID_STALL -->|Hold Instruction| ID_STALL
    EX_BUBBLE -->|NOP to MEM| MEM_CONT
    MEM_CONT --> WB_CONT
    
    style HAZARD fill:#ff6b6b
    style IF_STALL fill:#ffa500
    style ID_STALL fill:#ffa500
    style EX_BUBBLE fill:#ffd700
    style MEM_CONT fill:#90ee90
    style WB_CONT fill:#90ee90
```

**Stall Duration:** 1 cycle (load result available in MEM stage for forwarding).

---

### 4.3 Flush Signal Propagation

```mermaid
flowchart LR
    SOURCE{Flush Source}
    
    BRANCH[Branch Taken<br/>in EX]
    JUMP[Jump<br/>in EX]
    TRAP[Exception<br/>in MEM]
    MRET[MRET<br/>in MEM]
    
    IF_FLUSH[IF Stage<br/>Flush + Redirect PC]
    ID_FLUSH[ID Stage<br/>Flush to Bubble]
    EX_FLUSH[EX Stage<br/>Flush to Bubble]
    MEM_CONT[MEM Stage<br/>Continue]
    WB_CONT[WB Stage<br/>Continue]
    
    SOURCE --> BRANCH
    SOURCE --> JUMP
    SOURCE --> TRAP
    SOURCE --> MRET
    
    BRANCH -->|flush_if<br/>flush_id| IF_FLUSH
    BRANCH -->|flush_id| ID_FLUSH
    
    JUMP -->|flush_if<br/>flush_id| IF_FLUSH
    JUMP -->|flush_id| ID_FLUSH
    
    TRAP -->|flush_if<br/>flush_id<br/>flush_ex| IF_FLUSH
    TRAP -->|flush_id<br/>flush_ex| ID_FLUSH
    TRAP -->|flush_ex| EX_FLUSH
    
    MRET -->|flush_if<br/>flush_id<br/>flush_ex| IF_FLUSH
    MRET -->|flush_id<br/>flush_ex| ID_FLUSH
    MRET -->|flush_ex| EX_FLUSH
    
    IF_FLUSH --> MEM_CONT
    ID_FLUSH --> MEM_CONT
    EX_FLUSH --> MEM_CONT
    MEM_CONT --> WB_CONT
    
    style SOURCE fill:#87ceeb
    style BRANCH fill:#ff6b6b
    style JUMP fill:#ff6b6b
    style TRAP fill:#ff0000
    style MRET fill:#ffa500
    style IF_FLUSH fill:#ffd700
    style ID_FLUSH fill:#ffd700
    style EX_FLUSH fill:#ffd700
```

**Flush Scope:**
- **Branch/Jump (EX):** Flush IF, ID (2 stages)
- **Trap/MRET (MEM):** Flush IF, ID, EX (3 stages)

---

## Branch/Jump Control Flow

### 5.1 Branch Decision Flow

```mermaid
flowchart TD
    START([Branch Instruction<br/>in EX Stage])
    
    COMPARE[Branch Comparator<br/>Evaluate Condition]
    
    BEQ{BEQ:<br/>rs1 == rs2?}
    BNE{BNE:<br/>rs1 != rs2?}
    BLT{BLT:<br/>rs1 < rs2<br/>(signed)?}
    BGE{BGE:<br/>rs1 >= rs2<br/>(signed)?}
    BLTU{BLTU:<br/>rs1 < rs2<br/>(unsigned)?}
    BGEU{BGEU:<br/>rs1 >= rs2<br/>(unsigned)?}
    
    TAKEN[Branch Taken<br/>PC = PC + imm]
    NOT_TAKEN[Branch Not Taken<br/>PC = PC + 4]
    
    FLUSH_IF[Flush IF Stage]
    FLUSH_ID[Flush ID Stage]
    
    UPDATE_PC[Update PC in IF]
    
    END([Continue Execution])
    
    START --> COMPARE
    
    COMPARE --> BEQ
    COMPARE --> BNE
    COMPARE --> BLT
    COMPARE --> BGE
    COMPARE --> BLTU
    COMPARE --> BGEU
    
    BEQ -->|Equal| TAKEN
    BEQ -->|Not Equal| NOT_TAKEN
    
    BNE -->|Not Equal| TAKEN
    BNE -->|Equal| NOT_TAKEN
    
    BLT -->|Less| TAKEN
    BLT -->|Greater/Equal| NOT_TAKEN
    
    BGE -->|Greater/Equal| TAKEN
    BGE -->|Less| NOT_TAKEN
    
    BLTU -->|Less| TAKEN
    BLTU -->|Greater/Equal| NOT_TAKEN
    
    BGEU -->|Greater/Equal| TAKEN
    BGEU -->|Less| NOT_TAKEN
    
    TAKEN --> FLUSH_IF
    TAKEN --> FLUSH_ID
    FLUSH_IF --> UPDATE_PC
    FLUSH_ID --> UPDATE_PC
    
    NOT_TAKEN --> END
    UPDATE_PC --> END
    
    style TAKEN fill:#ff6b6b
    style NOT_TAKEN fill:#90ee90
    style FLUSH_IF fill:#ffd700
    style FLUSH_ID fill:#ffd700
```

**Branch Penalty:**
- **Taken:** 2 cycles (flush IF, ID)
- **Not Taken:** 0 cycles (sequential execution)

---

### 5.2 Jump Flow (JAL/JALR)

```mermaid
flowchart TD
    START([Jump Instruction<br/>in EX Stage])
    
    JAL{Instruction<br/>Type?}
    
    JAL_TARGET[JAL:<br/>target = PC + imm<br/>rd = PC + 4]
    JALR_TARGET[JALR:<br/>target = (rs1 + imm) & ~1<br/>rd = PC + 4]
    
    FLUSH_IF[Flush IF Stage]
    FLUSH_ID[Flush ID Stage]
    
    UPDATE_PC[Update PC to target]
    SAVE_RA[Save return address<br/>to rd (link register)]
    
    END([Continue at Target])
    
    START --> JAL
    
    JAL -->|JAL| JAL_TARGET
    JAL -->|JALR| JALR_TARGET
    
    JAL_TARGET --> FLUSH_IF
    JALR_TARGET --> FLUSH_IF
    
    JAL_TARGET --> SAVE_RA
    JALR_TARGET --> SAVE_RA
    
    FLUSH_IF --> FLUSH_ID
    FLUSH_ID --> UPDATE_PC
    
    UPDATE_PC --> END
    SAVE_RA --> END
    
    style JAL_TARGET fill:#87ceeb
    style JALR_TARGET fill:#87ceeb
    style FLUSH_IF fill:#ffd700
    style FLUSH_ID fill:#ffd700
    style SAVE_RA fill:#90ee90
```

**Jump Penalty:** Always 2 cycles (unconditional redirect).

**JALR LSB Clear:** Target address bit [0] cleared to ensure instruction alignment.

---

## Exception Trap Sequence

### 6.1 Exception Detection and Trap Flow

```mermaid
flowchart TD
    START([Instruction in<br/>MEM Stage])
    
    CHECK{Exception<br/>Condition?}
    
    EBREAK[EBREAK:<br/>Breakpoint]
    ECALL[ECALL:<br/>Environment Call]
    ILLEGAL[Illegal Instruction]
    MISALIGN_L[Load Misaligned]
    MISALIGN_S[Store Misaligned]
    FAULT_L[Load Access Fault]
    FAULT_S[Store Access Fault]
    
    SAVE_CSR[Save to CSRs:<br/>mepc = PC<br/>mcause = code<br/>mtval = address]
    
    FLUSH_IF[Flush IF Stage]
    FLUSH_ID[Flush ID Stage]
    FLUSH_EX[Flush EX Stage]
    
    REDIRECT[Redirect PC<br/>to mtvec]
    
    TRAP_HANDLER([Execute Trap<br/>Handler])
    
    NO_TRAP([Continue<br/>Normal Execution])
    
    START --> CHECK
    
    CHECK -->|Yes| EBREAK
    CHECK -->|Yes| ECALL
    CHECK -->|Yes| ILLEGAL
    CHECK -->|Yes| MISALIGN_L
    CHECK -->|Yes| MISALIGN_S
    CHECK -->|Yes| FAULT_L
    CHECK -->|Yes| FAULT_S
    CHECK -->|No| NO_TRAP
    
    EBREAK -->|code=3| SAVE_CSR
    ECALL -->|code=11| SAVE_CSR
    ILLEGAL -->|code=2| SAVE_CSR
    MISALIGN_L -->|code=4| SAVE_CSR
    MISALIGN_S -->|code=6| SAVE_CSR
    FAULT_L -->|code=5| SAVE_CSR
    FAULT_S -->|code=7| SAVE_CSR
    
    SAVE_CSR --> FLUSH_IF
    SAVE_CSR --> FLUSH_ID
    SAVE_CSR --> FLUSH_EX
    
    FLUSH_IF --> REDIRECT
    FLUSH_ID --> REDIRECT
    FLUSH_EX --> REDIRECT
    
    REDIRECT --> TRAP_HANDLER
    
    style EBREAK fill:#ff6b6b
    style ECALL fill:#ff6b6b
    style ILLEGAL fill:#ff6b6b
    style MISALIGN_L fill:#ff6b6b
    style MISALIGN_S fill:#ff6b6b
    style FAULT_L fill:#ff6b6b
    style FAULT_S fill:#ff6b6b
    style SAVE_CSR fill:#ffa500
    style FLUSH_IF fill:#ffd700
    style FLUSH_ID fill:#ffd700
    style FLUSH_EX fill:#ffd700
    style NO_TRAP fill:#90ee90
```

**Exception Priority (highest to lowest):**
1. Instruction fetch exceptions (not implemented)
2. Illegal instruction (ID stage)
3. Breakpoint (EBREAK)
4. Load/Store address misaligned
5. Load/Store access fault
6. Environment call (ECALL)

---

### 6.2 Exception State Machine

```mermaid
stateDiagram-v2
    [*] --> NORMAL
    
    NORMAL: Normal Execution
    TRAP_DETECT: Exception Detected
    TRAP_SAVE: Save CSRs
    TRAP_FLUSH: Flush Pipeline
    TRAP_REDIRECT: Redirect to mtvec
    HANDLER: Trap Handler Execution
    
    NORMAL --> TRAP_DETECT: Exception in MEM
    
    TRAP_DETECT --> TRAP_SAVE: exception_trap = 1
    
    TRAP_SAVE --> TRAP_FLUSH: mepc/mcause/mtval updated
    
    TRAP_FLUSH --> TRAP_REDIRECT: IF/ID/EX flushed
    
    TRAP_REDIRECT --> HANDLER: PC = mtvec
    
    HANDLER --> HANDLER: Execute trap handler code
    HANDLER --> NORMAL: MRET instruction
    
    note right of TRAP_DETECT
        MEM stage detects:
        - EBREAK/ECALL
        - Misalignment
        - Access fault
    end note
    
    note right of TRAP_SAVE
        Atomic CSR update:
        mepc   = exception_pc
        mcause = exception_code
        mtval  = exception_tval
    end note
    
    note right of HANDLER
        Software trap handler:
        - Save context
        - Handle exception
        - Restore context
        - Execute MRET
    end note
```

---

## MRET Return Sequence

### 7.1 MRET Flow

```mermaid
flowchart TD
    START([MRET Instruction<br/>in MEM Stage])
    
    DETECT[Detect MRET<br/>mret_req = 1]
    
    READ_MEPC[Read mepc<br/>from CSR]
    
    FLUSH_IF[Flush IF Stage]
    FLUSH_ID[Flush ID Stage]
    FLUSH_EX[Flush EX Stage]
    
    RESTORE_PC[Restore PC<br/>PC = mepc]
    
    RESUME([Resume Execution<br/>at Saved PC])
    
    START --> DETECT
    DETECT --> READ_MEPC
    
    READ_MEPC --> FLUSH_IF
    READ_MEPC --> FLUSH_ID
    READ_MEPC --> FLUSH_EX
    
    FLUSH_IF --> RESTORE_PC
    FLUSH_ID --> RESTORE_PC
    FLUSH_EX --> RESTORE_PC
    
    RESTORE_PC --> RESUME
    
    style DETECT fill:#87ceeb
    style READ_MEPC fill:#90ee90
    style FLUSH_IF fill:#ffd700
    style FLUSH_ID fill:#ffd700
    style FLUSH_EX fill:#ffd700
    style RESTORE_PC fill:#98fb98
```

**MRET Characteristics:**
- **Privilege:** Machine-mode only (no privilege change in M-only core)
- **PC Restore:** Jumps to mepc (saved exception PC)
- **Pipeline Flush:** 3 stages (IF/ID/EX)
- **CSR Preservation:** mepc/mcause/mtval remain unchanged

---

### 7.2 Exception-MRET Round Trip

```mermaid
sequenceDiagram
    participant User as User Code
    participant CPU as CPU Pipeline
    participant CSR as CSR Module
    participant Handler as Trap Handler
    
    User->>CPU: Execute EBREAK
    CPU->>CPU: Detect in MEM stage
    CPU->>CSR: exception_trap=1<br/>exception_pc=0x100<br/>exception_code=3
    CSR->>CSR: Save mepc=0x100<br/>mcause=3<br/>mtval=0
    CSR->>CPU: trap_vector=mtvec (0x1000)
    CPU->>CPU: Flush IF/ID/EX
    CPU->>Handler: Redirect PC to 0x1000
    Handler->>Handler: Save context
    Handler->>Handler: Handle breakpoint
    Handler->>Handler: Restore context
    Handler->>CPU: Execute MRET
    CPU->>CSR: mret_req=1
    CSR->>CPU: mret_pc=mepc (0x100)
    CPU->>CPU: Flush IF/ID/EX
    CPU->>User: Restore PC to 0x100
    User->>User: Resume execution
    
    Note over CPU,CSR: Exception trap (cycle N)
    Note over Handler: Trap handler execution<br/>(variable cycles)
    Note over CPU,CSR: MRET return (cycle M)
```

---

## Memory Arbitration State Machine

### 8.1 Block RAM Port B Arbiter

```mermaid
stateDiagram-v2
    [*] --> CPU_ACCESS
    
    CPU_ACCESS: CPU Access (running=1)
    DEBUG_ACCESS: Debug Access (running=0)
    
    CPU_ACCESS --> DEBUG_ACCESS: CPU halted<br/>(running = 0)
    DEBUG_ACCESS --> CPU_ACCESS: CPU resumed<br/>(running = 1)
    
    note right of CPU_ACCESS
        Port B controlled by MEM stage:
        - addr = mem_addr[12:2]
        - wdata = store_data
        - we = byte_write_enables
        - rdata → load_data
    end note
    
    note right of DEBUG_ACCESS
        Port B controlled by Debug:
        - addr = dbg_addr
        - wdata = dbg_wdata
        - we = dbg_we
        - rdata → dbg_rdata
    end note
```

**Arbitration Logic:**
```systemverilog
assign ram_port_b_addr  = running ? mem_addr : dbg_addr;
assign ram_port_b_wdata = running ? mem_wdata : dbg_wdata;
assign ram_port_b_we    = running ? mem_we : dbg_we;
```

**Port Assignment:**
- **Port A:** IF stage (instruction fetch, read-only)
- **Port B:** MEM stage (data access) or Debug (when halted)

---

## References

### Related Module Specifications
- **[rv32i_if_spec.md](../rtl/cpu/rv32i_if_spec.md)** - PC control, branch redirect
- **[rv32i_hazard_spec.md](../rtl/cpu/rv32i_hazard_spec.md)** - RAW detection, forwarding
- **[rv32i_ex_spec.md](../rtl/cpu/rv32i_ex_spec.md)** - Branch comparator, jump target
- **[rv32i_mem_spec.md](../rtl/cpu/rv32i_mem_spec.md)** - Exception detection
- **[rv32i_csr_spec.md](../rtl/cpu/rv32i_csr_spec.md)** - Exception trap, MRET handling

### Architecture Documents
- **[rv32i_modular_architecture_spec.md](rv32i_modular_architecture_spec.md)** - Overall architecture
- **[rv32i_pipeline_interfaces.md](rv32i_pipeline_interfaces.md)** - Pipeline register structures

### Verification References
- **Assertion Modules:** All state transitions and control flow decisions covered by SVA
- **UVM Sequences:** Test scenarios exercising each control path
- **Coverage Models:** FSM state coverage and transition coverage

---

**Document Version:** 1.0  
**Last Updated:** 2026-01-04  
**Status:** Design Phase - Pre-Implementation
