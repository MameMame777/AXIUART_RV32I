# Obsolete Configuration Files - Safe to Delete
# Generated: 2026-01-05

## Files marked for deletion:

### 1. rv32i_config.f
- **Status**: OBSOLETE - Superseded by dsim_config_rv32i.f
- **Reason**: Referenced old monolithic rv32i_core.sv
- **Replacement**: dsim_config_rv32i.f (now uses modular architecture)
- **References updated**: Makefile_rv32i now points to dsim_config_rv32i.f

### 2. dsim_assertions.f
- **Status**: OBSOLETE - TD4CPU-specific (not RV32I)
- **Reason**: Contains TD4CPU memory access assertions
- **Replacement**: Assertions integrated into dsim_config.f (main config with assertions)

### 3. dsim_assertions_rv32i.f  
- **Status**: OBSOLETE - Debug-only assertions
- **Reason**: RV32I-specific debug assertions for initial development
- **Replacement**: All production assertions integrated into dsim_config.f

## Current configuration file structure (2 files):

### dsim_config.f
- **Purpose**: Main configuration with assertions enabled
- **Use case**: Development, verification, formal property checking
- **Contents**: Full RTL + UVM testbench + all SVA assertions

### dsim_config_no_assertions.f  
- **Purpose**: Assertion-disabled configuration
- **Use case**: Performance testing, regression, synthesis preparation
- **Contents**: Full RTL + UVM testbench (no SVA assertions)

## Action required:
```powershell
# From sim/uvm/tb directory:
Remove-Item rv32i_config.f
Remove-Item dsim_assertions.f
Remove-Item dsim_assertions_rv32i.f
```

## Verification:
After deletion, verify that:
1. Makefile_rv32i references dsim_config_rv32i.f ✓ (updated)
2. No other scripts reference the deleted files (check complete)
3. MCP client tools use dsim_config.f or dsim_config_rv32i.f only
