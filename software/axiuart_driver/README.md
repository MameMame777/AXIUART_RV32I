# AXIUART Driver

Production-ready Python driver for AXIUART Bridge register access over UART.

## Features

- **Protocol Compliant**: Full implementation of `docs/axiuart_bus_protocol.md`
- **CRC-8 Validation**: Automatic CRC calculation and verification
- **Register Access**: 8/16/32-bit read/write operations
- **Burst Transfers**: Multi-beat transfers with auto-increment
- **Error Handling**: Comprehensive exception handling with status codes
- **Soft Reset**: Support for RESET command (0xFF)

## Installation

```bash
# Install dependencies
pip install pyserial

# Add to Python path
export PYTHONPATH="${PYTHONPATH}:/path/to/AXIUART_/software"
```

## Quick Start

```python
from axiuart_driver import AXIUARTDriver

# Connect to device
driver = AXIUARTDriver('/dev/ttyUSB0', baudrate=115200, debug=True)
driver.open()

try:
    # Read VERSION register
    version = driver.get_version()
    print(f"Version: 0x{version:08X}")
    
    # Write test register
    driver.write_reg32(driver.REG_TEST_0, 0xDEADBEEF)
    
    # Read back and verify
    value = driver.read_reg32(driver.REG_TEST_0)
    assert value == 0xDEADBEEF, "Register mismatch"
    
    # Burst write
    driver.write_burst(driver.REG_TEST_0, [0x11111111, 0x22222222, 0x33333333])
    
    # Burst read
    values = driver.read_burst(driver.REG_TEST_0, count=3)
    print(f"Burst read: {[hex(v) for v in values]}")
    
finally:
    driver.close()
```

## Context Manager

```python
with AXIUARTDriver('/dev/ttyUSB0') as driver:
    # Read STATUS register
    status = driver.get_status()
    print(f"Status: 0x{status:08X}")
    
    # Automatic connection management
```

## Register Map

### Auto-Generated Register Constants

Register addresses are **automatically generated** from `register_map/axiuart_registers.json`. Never hard-code register addresses directly.

**Using Generated Constants:**
```python
from axiuart_driver import AXIUARTDriver

with AXIUARTDriver('COM3') as driver:
    # Use generated constants (from registers.py)
    driver.write_reg32(driver.REG_TEST_LED, 0xF)  # ✓ Correct
    driver.write_reg32(0x1044, 0xF)               # ✗ Avoid hard-coding
```

**Available Register Constants** (BASE_ADDR = 0x1000):

| Constant | Address | Access | Description |
|----------|---------|--------|-------------|
| `REG_CONTROL` | 0x1000 | RW | Control register |
| `REG_STATUS` | 0x1004 | RO | Status register |
| `REG_CONFIG` | 0x1008 | RW | Configuration register |
| `REG_DEBUG` | 0x100C | RW | Debug control |
| `REG_TX_COUNT` | 0x1010 | RO | TX transaction counter |
| `REG_RX_COUNT` | 0x1014 | RO | RX transaction counter |
| `REG_FIFO_STAT` | 0x1018 | RO | FIFO status flags |
| `REG_VERSION` | 0x101C | RO | Version register |
| `REG_TEST_0` | 0x1020 | RW | Test register 0 |
| `REG_TEST_1` | 0x1024 | RW | Test register 1 |
| `REG_TEST_2` | 0x1028 | RW | Test register 2 |
| `REG_TEST_3` | 0x102C | RW | Test register 3 |
| `REG_TEST_4` | 0x1040 | RW | Test register 4 (gap test) |
| `REG_TEST_LED` | 0x1044 | RW | 4-bit LED control |

**Regenerate after JSON changes:**
```bash
python software/axiuart_driver/tools/gen_registers.py \
  --in register_map/axiuart_registers.json
```

**Full Documentation:** See [REGISTER_MAP.md](REGISTER_MAP.md) for complete details.

## Protocol Details

### Command Frame (Host → Device)

```
SOF (0xA5) | CMD | ADDR[3:0] | DATA[0:63] | CRC
```

**CMD Byte**: `{RW, INC, SIZE[1:0], LEN[3:0]}`
- RW: 0=write, 1=read
- INC: 0=fixed address, 1=auto-increment
- SIZE: 00=8bit, 01=16bit, 10=32bit
- LEN: Beat count - 1 (0-15 for 1-16 beats)

### Response Frame (Device → Host)

**Write ACK:**
```
SOF (0x5A) | STATUS | CMD_ECHO | CRC
```

**Read Response:**
```
SOF (0x5A) | STATUS | CMD_ECHO | ADDR_ECHO[3:0] | DATA[0:63] | CRC
```

### Status Codes

| Code | Name | Description |
|------|------|-------------|
| 0x00 | SUCCESS | Transaction completed |
| 0x01 | CRC_ERROR | CRC mismatch detected |
| 0x02 | INVALID_CMD | Unsupported command |
| 0x03 | ADDR_ALIGN | Address alignment violation |
| 0x04 | TIMEOUT | AXI timeout |
| 0x05 | AXI_ERROR | AXI slave error |
| 0x06 | BUSY | Bridge busy |
| 0x07 | LEN_RANGE | Length field out of range |

### CRC-8 Calculation

- Polynomial: 0x07 (x^8 + x^2 + x + 1)
- Initial value: 0x00
- No reflection, no final XOR

## Error Handling

```python
from axiuart_driver import AXIUARTDriver, AXIUARTException

try:
    driver = AXIUARTDriver('/dev/ttyUSB0')
    driver.open()
    value = driver.read_reg32(0x1000)
except AXIUARTException as e:
    print(f"Driver error: {e}")
except Exception as e:
    print(f"Unexpected error: {e}")
finally:
    if driver.serial and driver.serial.is_open:
        driver.close()
```

## Advanced Features

### Soft Reset

```python
# Clear RX/TX FIFOs and state machines
# Preserves configuration registers
driver.soft_reset()
```

### Burst Transfers

```python
# Write 4 consecutive registers with auto-increment
driver.write_burst(0x1020, [0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC, 0xDDDDDDDD])

# Read 4 consecutive registers
values = driver.read_burst(0x1020, count=4)
```

### Fixed Address Mode

```python
# Write same address multiple times (INC=0)
driver.write_burst(0x1000, [0x11111111, 0x22222222], inc=False)
```

## Testing

See `examples/` directory for comprehensive test scripts:
- `example_basic.py` - Basic read/write operations
- `example_burst.py` - Burst transfer examples
- `example_diagnostic.py` - Full register map diagnostic

## Requirements

- Python 3.7+
- pyserial 3.5+
- UART connection to AXIUART hardware

## License

See project root LICENSE file.

## References

- Protocol Spec: `docs/axiuart_bus_protocol.md`
- RTL: `rtl/Frame_Parser.sv`, `rtl/Frame_Builder.sv`, `rtl/Register_Block.sv`
- UVM Verification: `sim/uvm/agents/uart/`
