# RV32I Core Verification Environment

## Overview

Standalone testbench for RV32I CPU core verification without full AXIUART bridge dependencies.

## Architecture

```
rv32i_core (DUT)
    ├── 5-stage pipeline (IF/ID/EX/MEM/WB)
    ├── 32×32-bit register file (x0 hardwired to zero)
    ├── Full ALU (ADD/SUB/SLL/SRL/SRA/AND/OR/XOR/SLT/SLTU)
    ├── Branch unit (BEQ/BNE/BLT/BGE/BLTU/BGEU)
    ├── Jump unit (JAL/JALR)
    ├── Memory (8KB Block RAM, byte-addressed)
    ├── MMIO LED register (0x407C)
    └── Debug interface (EBREAK, halt/run control)

rv32i_trace_buffer
    ├── 64-entry circular buffer
    ├── 128-bit entries (PC/insn/rd_addr/rd_value)
    └── Direct memory access for verification

rv32i_pipeline_spec (assertions)
    ├── x0 hardwire checks
    ├── Pipeline progression checks
    ├── Hazard detection verification
    └── Branch/jump behavior validation
```

## File Structure

```
sim/uvm/tb/
├── rv32i_tb_top.sv      # Standalone testbench top
├── rv32i_config.f       # DSIM file list
├── Makefile_rv32i       # Build and run scripts
└── README_rv32i.md      # This file
```

## Running Tests

### Quick Start
```bash
cd sim/uvm/tb
make -f Makefile_rv32i all
```

### Individual Steps
```bash
# Compile
make -f Makefile_rv32i compile

# Run simulation
make -f Makefile_rv32i run

# View waveforms
make -f Makefile_rv32i waves
```

### Clean Build
```bash
make -f Makefile_rv32i clean
```

## Test Program

Built-in test program in `rv32i_core.sv` initial block:

1. **ALU operations**: ADD, SUB, SLL, SLT
2. **Immediate operations**: ADDI, ANDI, ORI, XORI
3. **Load upper**: LUI, AUIPC
4. **Branch test**: BEQ (not taken)
5. **Jump test**: JAL with link register
6. **Memory test**: SW/LW to RAM
7. **Debug test**: EBREAK (halts CPU)
8. **MMIO test**: Write to LED register (0x407C)

## Expected Results

- **Instructions executed**: ~20-25 (before EBREAK)
- **LED final value**: 0x5 (last MMIO write)
- **CPU halted**: 1 (EBREAK triggered)
- **Breakpoint hit**: 1 (cpu_break signal)

## Assertions

Bound assertions from `rv32i_pipeline_spec.sv`:

- **SPEC-RF-1/2**: x0 hardwire checks (read zero, ignore writes)
- **SPEC-PIPE-1**: Pipeline stage progression
- **SPEC-PC-1/2/3/4**: PC management and alignment
- **SPEC-FLUSH-1/2/3**: Control hazard flush behavior
- **SPEC-HAZ-1/2**: Data hazard detection
- **SPEC-FWD-1/2**: Forwarding path activation

## Waveform Signals

Key signals to observe:

- **Pipeline stages**: `pc_if`, `pc_id`, `pc_ex`, `pc_mem`, `pc_wb`
- **Instructions**: `insn_if`, `insn_id`, `insn_ex`, `insn_mem`, `insn_wb`
- **Register file**: `rf_raddr1/2`, `rf_rdata1/2`, `rf_waddr`, `rf_wdata`, `rf_wen`
- **Hazards**: `forward_rs1/2`, `hazard_load_use`, `if_stall`, `id_stall`
- **Control**: `pc_sel_branch`, `ex_branch_taken`, `cpu_halt`, `cpu_break`
- **Memory**: `mem_addr`, `mem_load_data`, `mem_byte_enable`
- **MMIO**: `led_reg`

## Known Issues

None - core implementation complete.

## Future Enhancements

- [ ] Add UVM-based random instruction generation
- [ ] Implement coverage collection
- [ ] Add performance counters (IPC, stall rate, branch prediction accuracy)
- [ ] Create ELF loader for external test programs
- [ ] Integrate with UART bridge for full system verification

## References

- RISC-V ISA Specification: https://riscv.org/specifications/
- Migration Diary: `docs/rv32i_migration_diary.md`
- ISA Package: `rtl/cpu/rv32i_isa_pkg.sv`
- Pipeline Spec: `sim/assertions/rv32i_pipeline_spec.sv`
