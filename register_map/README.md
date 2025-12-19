# AXIUART Register Map

## Overview

This directory contains the **Single Source of Truth (SSOT)** for all AXIUART register definitions. The register map is maintained in JSON format and automatically generates code for multiple target environments.

## Architecture

```
axiuart_registers.json (SSOT)
        ↓
  gen_registers.py (Code Generator)
        ↓
    ┌───┴────────┬───────────────┐
    ↓            ↓               ↓
Python      SystemVerilog    Markdown
registers.py  reg_pkg.sv    REGISTER_MAP.md
    ↓            ↓               ↓
  Driver    RTL + UVM      Documentation
```

## Files

### Source File

**`axiuart_registers.json`**
- Master register definition file
- Contains all register metadata:
  - Register names and offsets
  - Access types (RW/RO/WO)
  - Descriptions and reset values
  - Base address and stride configuration

### Generated Files

1. **Python Constants** (`../software/axiuart_driver/registers.py`)
   - Register address constants for Python driver
   - Example: `REG_CONTROL = 0x1000`

2. **SystemVerilog Package** (`../rtl/register_block/axiuart_reg_pkg.sv`)
   - Parameter definitions for RTL and UVM
   - Imported by Register_Block.sv and test files

3. **Markdown Documentation** (`../software/axiuart_driver/REGISTER_MAP.md`)
   - Human-readable register reference
   - Complete with addresses, access types, and descriptions

## Usage

### Viewing Current Register Map

```bash
# View JSON source
cat register_map/axiuart_registers.json

# View generated documentation
cat software/axiuart_driver/REGISTER_MAP.md
```

### Modifying Register Map

1. **Edit JSON file:**
   ```bash
   # Edit register_map/axiuart_registers.json
   # Add/modify/remove register definitions
   ```

2. **Validate JSON syntax:**
   ```bash
   python -m json.tool register_map/axiuart_registers.json
   ```

3. **Regenerate all targets:**
   ```bash
   python software/axiuart_driver/tools/gen_registers.py \
     --in register_map/axiuart_registers.json
   ```

4. **Verify changes:**
   ```bash
   # Check Python constants
   cat software/axiuart_driver/registers.py
   
   # Check SystemVerilog package
   cat rtl/register_block/axiuart_reg_pkg.sv
   
   # Check documentation
   cat software/axiuart_driver/REGISTER_MAP.md
   ```

5. **Run regression tests:**
   ```bash
   # Validate with UVM tests
   python mcp_server/mcp_client.py --workspace . \
     --tool run_uvm_simulation_batch \
     --test-name axiuart_reg_rw_test
   
   # Test Python driver
   cd software
   python -m axiuart_driver.examples.led_control
   ```

## JSON Schema

```json
{
  "block_name": "axiuart_registers",
  "base_addr": "0x1000",
  "addr_stride_bytes": 4,
  "registers": [
    {
      "name": "CONTROL",
      "offset": "0x0000",
      "access": "RW",
      "description": "Control register",
      "reset_value": "0x00000000"
    }
  ]
}
```

### Field Definitions

- **block_name**: Register block identifier
- **base_addr**: Base address (hex string)
- **addr_stride_bytes**: Address increment between consecutive registers
- **registers**: Array of register definitions
  - **name**: Register name (uppercase, no REG_ prefix)
  - **offset**: Offset from base (hex string)
  - **access**: Access type (RW/RO/WO)
  - **description**: Human-readable description
  - **reset_value**: Default value on reset (hex string)

## Validation Rules

The generator script enforces the following constraints:

1. **Alignment**: All addresses must be 32-bit aligned (multiples of 4)
2. **Uniqueness**: No duplicate register offsets allowed
3. **Ordering**: Registers must be sorted by offset (enforced during generation)
4. **Naming**: Register names must be valid identifiers
5. **Access Types**: Only RW, RO, WO allowed

## Adding New Registers

### Step-by-Step Guide

1. **Identify address gap:**
   ```bash
   # Check existing addresses
   grep '"offset"' register_map/axiuart_registers.json
   ```

2. **Add register to JSON:**
   ```json
   {
     "name": "NEW_REG",
     "offset": "0x0048",
     "access": "RW",
     "description": "New feature control",
     "reset_value": "0x00000000"
   }
   ```

3. **Regenerate code:**
   ```bash
   python software/axiuart_driver/tools/gen_registers.py \
     --in register_map/axiuart_registers.json
   ```

4. **Update RTL (if needed):**
   ```systemverilog
   // rtl/register_block/Register_Block.sv already imports package
   // Add register implementation logic
   ```

5. **Update UVM test:**
   ```systemverilog
   // sim/tests/your_test.sv
   import axiuart_reg_pkg::*;
   uart_seq.write_then_read(REG_NEW_REG, 32'hTEST_VAL);
   ```

6. **Verify in simulation:**
   ```bash
   python mcp_server/mcp_client.py --workspace . \
     --tool run_uvm_simulation_batch --test-name your_test
   ```

## Generator Script Details

**Location:** `software/axiuart_driver/tools/gen_registers.py`

**Features:**
- Validates JSON schema and alignment rules
- Generates deterministic output (sorted by offset)
- Creates backup timestamps in docstrings
- Reports all validation errors clearly

**Command-line options:**
```bash
python software/axiuart_driver/tools/gen_registers.py \
  --in <json_file>       # Input JSON file (required)
```

## Best Practices

1. **Never hard-code addresses** in RTL, UVM, or Python
2. **Always regenerate** after editing JSON
3. **Commit all generated files** together with JSON changes
4. **Run regression tests** before finalizing changes
5. **Document new registers** with clear descriptions in JSON
6. **Maintain address gaps** for future expansion
7. **Use semantic naming** (e.g., TX_COUNT not REG_0x10)

## Troubleshooting

### Python Import Error (Unicode Escape)

**Problem:** `SyntaxError: malformed \N character escape`

**Solution:** Fixed in generator - docstring uses raw string (`r"""`)

### SystemVerilog Compilation Error

**Problem:** Package not found

**Solution:** Check `sim/uvm/tb/dsim_config.f` includes package before RTL:
```
rtl/register_block/axiuart_reg_pkg.sv
rtl/register_block/Register_Block.sv
```

### Address Mismatch in Simulation

**Problem:** UVM reads wrong value from register

**Solution:**
1. Verify JSON was regenerated
2. Check both Python and SV files were updated
3. Recompile RTL and tests
4. Check waveform for actual AXI transactions

## Version History

- **2024-12-16**: Initial JSON-based register management system
  - Migrated from hard-coded addresses
  - Created generator script with validation
  - Generated Python, SystemVerilog, and Markdown outputs
  - Validated with DSIM regression tests

## References

- **Generator Script:** `../software/axiuart_driver/tools/gen_registers.py`
- **Generated Python:** `../software/axiuart_driver/registers.py`
- **Generated SV Package:** `../rtl/register_block/axiuart_reg_pkg.sv`
- **Generated Docs:** `../software/axiuart_driver/REGISTER_MAP.md`
- **RTL Implementation:** `../rtl/register_block/Register_Block.sv`
- **UVM Tests:** `../sim/tests/axiuart_reg_rw_test.sv`
