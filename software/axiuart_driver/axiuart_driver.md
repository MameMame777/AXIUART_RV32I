# AXIUART Python Driver Documentation

Production-ready Python driver for AXIUART hardware interface.

## Overview

The AXIUART driver provides high-level Python APIs for register access over UART to AXI4-Lite address space. This enables software control of FPGA registers through a simple serial connection.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Python Application Layer                                │
│  (led_control.py, example_basic.py, etc.)               │
└────────────────┬────────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────────┐
│  AXIUARTDriver Class                                     │
│  - Register read/write operations                        │
│  - Transaction management                                │
│  - Error handling                                        │
└────────────────┬────────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────────┐
│  Protocol Layer                                          │
│  - FrameBuilder: Construct UART frames                   │
│  - FrameParser: Parse responses                          │
│  - CRC-8 calculation                                     │
└────────────────┬────────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────────┐
│  pySerial (Serial Port Interface)                        │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
            UART Hardware
                 │
                 ▼
          FPGA AXIUART Bridge
```

## Module Structure

```
axiuart_driver/
├── __init__.py                 # Package initialization
├── axiuart_driver.py           # Main driver class
├── protocol.py                 # UART protocol implementation
├── README.md                   # Package documentation
├── axiuart_driver.md          # This file
└── examples/
    ├── example_basic.py        # Basic register R/W example
    ├── example_burst.py        # Burst transaction example
    ├── example_diagnostic.py   # Hardware diagnostic tool
    ├── led_control.py          # LED control application
    └── LED_CONTROL_README.md   # LED control documentation
```

## Core Components

### 1. AXIUARTDriver Class

Main driver class providing register access APIs.

**Key Features:**
- Context manager support (with statement)
- Automatic connection management
- CRC verification
- Timeout handling
- Debug logging

**Register Map:**
```python
BASE_ADDR = 0x1000

# System registers
REG_CONTROL   = 0x1000    # Control register
REG_STATUS    = 0x1004    # Status flags
REG_CONFIG    = 0x1008    # Configuration
REG_DEBUG     = 0x100C    # Debug information
REG_TX_COUNT  = 0x1010    # TX transaction counter
REG_RX_COUNT  = 0x1014    # RX transaction counter
REG_FIFO_STAT = 0x1018    # FIFO status
REG_VERSION   = 0x101C    # Hardware version

# Test registers
REG_TEST_0    = 0x1020    # General purpose test register
REG_TEST_1    = 0x1024
REG_TEST_2    = 0x1028
REG_TEST_3    = 0x102C
REG_TEST_4    = 0x1040
REG_TEST_LED  = 0x1044    # 4-bit LED control register
REG_TEST_5    = 0x1050
REG_TEST_6    = 0x1080
REG_TEST_7    = 0x1100
```

**Basic Usage:**
```python
from axiuart_driver import AXIUARTDriver

# Method 1: Context manager (recommended)
with AXIUARTDriver('COM3', baudrate=115200) as driver:
    # Write register
    driver.write_reg32(0x1020, 0xDEADBEEF)
    
    # Read register
    value = driver.read_reg32(0x1020)
    print(f"Value: 0x{value:08X}")

# Method 2: Manual open/close
driver = AXIUARTDriver('COM3', baudrate=115200, debug=True)
driver.open()
try:
    value = driver.read_reg32(driver.REG_VERSION)
finally:
    driver.close()
```

**API Reference:**

#### Constructor
```python
AXIUARTDriver(port: str, baudrate: int = 115200, 
              timeout: float = 1.0, debug: bool = False)
```
- `port`: Serial port device (e.g., 'COM3', '/dev/ttyUSB0')
- `baudrate`: UART baud rate (default: 115200)
- `timeout`: Response timeout in seconds (default: 1.0)
- `debug`: Enable debug logging (default: False)

#### Core Methods
```python
def open() -> None
    """Open serial port connection"""

def close() -> None
    """Close serial port connection"""

def write_reg32(addr: int, value: int) -> None
    """Write 32-bit register"""

def read_reg32(addr: int) -> int
    """Read 32-bit register, returns 32-bit value"""

def write_burst(addr: int, data: List[int], increment: bool = True) -> None
    """Write multiple registers in burst mode"""

def read_burst(addr: int, count: int, increment: bool = True) -> List[int]
    """Read multiple registers in burst mode"""
```

#### Convenience Methods
```python
def get_version() -> int
    """Read VERSION register (0x101C)"""

def get_status() -> int
    """Read STATUS register (0x1004)"""

def get_tx_count() -> int
    """Read TX_COUNT register (0x1010)"""

def get_rx_count() -> int
    """Read RX_COUNT register (0x1014)"""

def get_fifo_status() -> int
    """Read FIFO_STAT register (0x1018)"""
```

### 2. Protocol Layer

Low-level UART protocol implementation.

**FrameBuilder:**
- Constructs command frames with proper formatting
- Calculates CRC-8
- Handles address/data encoding

**FrameParser:**
- Parses response frames
- Validates CRC
- Extracts status, address, and data

**Frame Formats:**

*Write Command:*
```
Host → Device: [0xA5][CMD][ADDR(4)][DATA(4)][CRC]
Device → Host: [0x5A][STATUS][CMD][CRC]
```

*Read Command:*
```
Host → Device: [0xA5][CMD][ADDR(4)][CRC]
Device → Host: [0x5A][STATUS][CMD][ADDR(4)][DATA(4)][CRC]
```

### 3. LED Control Application

Specialized driver for 4-bit LED control via REG_TEST_LED (0x1044).

#### LEDController Class

High-level LED control interface built on AXIUARTDriver.

**Features:**
- Individual bit control (4 LEDs)
- Preset patterns (binary count, knight rider, blink)
- Interactive command-line interface
- Read-modify-write operations

**API Overview:**
```python
from axiuart_driver.examples.led_control import LEDController

with LEDController('COM3') as led:
    # Basic control
    led.set_led(0xF)           # Set all 4 LEDs (0-15)
    value = led.get_led()      # Read current value
    
    # Individual bit control
    led.set_bit(0, True)       # Turn on LED0
    led.set_bit(1, False)      # Turn off LED1
    led.toggle_bit(2)          # Toggle LED2
    
    # Convenience methods
    led.all_on()               # Turn all LEDs on (0xF)
    led.all_off()              # Turn all LEDs off (0x0)
    
    # Animation patterns
    led.pattern_binary_count(delay=0.5, cycles=2)
    led.pattern_knight_rider(delay=0.2, cycles=3)
    led.pattern_blink_all(delay=0.5, count=5)
```

**Usage Modes:**

1. **Interactive Mode:**
```bash
python led_control.py

LED> 15              # Set LED to 0b1111 (all on)
LED> 0xA             # Set LED to 0b1010
LED> 0b0101          # Set LED to 0b0101
LED> on 0            # Turn on LED bit 0
LED> off 2           # Turn off LED bit 2
LED> toggle 1        # Toggle LED bit 1
LED> all_on          # Turn all LEDs on
LED> read            # Read current LED value
LED> count           # Run binary count pattern
LED> knight          # Run knight rider pattern
LED> blink           # Blink all LEDs
LED> quit            # Exit
```

2. **Demo Modes:**
```bash
# Binary counting pattern (0→15)
python led_control.py count

# Knight Rider pattern
python led_control.py knight

# Blink all LEDs
python led_control.py blink

# Run all pattern tests
python led_control.py test
```

3. **Python API:**
```python
from axiuart_driver.examples.led_control import LEDController
import time

with LEDController('COM3', baudrate=115200) as led:
    # Custom pattern example
    for i in range(16):
        led.set_led(i)
        print(f"LED = {i:2d} (0b{i:04b})")
        time.sleep(0.3)
    
    # Bit manipulation example
    led.all_off()
    for bit in range(4):
        led.set_bit(bit, True)
        time.sleep(0.5)
        led.set_bit(bit, False)
```

**LED Register Specification:**

- **Address:** 0x1044 (REG_TEST_LED)
- **Width:** 32-bit register (only bits [3:0] used)
- **Access:** Read/Write
- **Bit Map:**
  - Bit [3]: LED3 control
  - Bit [2]: LED2 control
  - Bit [1]: LED1 control
  - Bit [0]: LED0 control
  - Bits [31:4]: Reserved (read as 0)

**Animation Patterns:**

1. **Binary Count (`pattern_binary_count`):**
   - Counts from 0 to 15 in binary
   - Visual representation of binary numbers
   - Configurable delay and cycle count

2. **Knight Rider (`pattern_knight_rider`):**
   - Single LED sweeps left-right
   - Sequence: 0001 → 0010 → 0100 → 1000 → 0100 → 0010
   - Classic Larson scanner effect

3. **Blink All (`pattern_blink_all`):**
   - All LEDs blink synchronously
   - Configurable on/off timing
   - Simple attention-getting pattern

## Example Applications

### 1. Basic Register Test (example_basic.py)

Demonstrates fundamental register operations.

**Features:**
- VERSION register read
- STATUS register read
- Single register write/read verification
- Multiple pattern testing
- Transaction counter monitoring

**Output Example:**
```
[1] Opening COM3 at 115200 baud...
    ✓ Connected
[2] Reading VERSION register (0x101C)...
    VERSION = 0x00010203
[3] Reading STATUS register (0x1004)...
    STATUS = 0x00000000
[4] Writing test pattern to TEST_0 (0x1020)...
    Written: 0xDEADBEEF
[5] Reading back TEST_0...
    Read: 0xDEADBEEF
    ✓ PASS: Value matches
[6] Testing multiple patterns...
    [1/5] 0x00000000 → 0x00000000 ✓
    [2/5] 0xFFFFFFFF → 0xFFFFFFFF ✓
    [3/5] 0xAAAAAAAA → 0xAAAAAAAA ✓
    [4/5] 0x55555555 → 0x55555555 ✓
    [5/5] 0x12345678 → 0x12345678 ✓
    ✓ All patterns verified
```

### 2. Burst Operations (example_burst.py)

Demonstrates high-performance burst transactions.

**Features:**
- Write multiple registers in single transaction
- Read multiple registers efficiently
- Incremental vs fixed addressing modes
- Performance benchmarking

### 3. Hardware Diagnostic (example_diagnostic.py)

Comprehensive hardware testing tool.

**Features:**
- Register map scan
- Communication test
- FIFO status check
- Error detection
- Performance measurement

### 4. LED Control (led_control.py)

Full-featured LED control application with multiple interfaces.

**Features:**
- Interactive command-line interface
- Preset animation patterns
- Individual bit manipulation
- Real-time LED state display
- Configurable timing parameters

## Error Handling

### Exception Hierarchy

```python
Exception
└── AXIUARTException
    ├── Connection errors (port open failures)
    ├── Timeout errors (no response)
    ├── Protocol errors (invalid frames)
    └── Device errors (STATUS != SUCCESS)
```

### Common Errors

**Port Access Error:**
```python
try:
    driver.open()
except AXIUARTException as e:
    print(f"Failed to open port: {e}")
    # Windows: Check Device Manager
    # Linux: Check permissions (sudo usermod -a -G dialout $USER)
```

**Timeout Error:**
```python
try:
    value = driver.read_reg32(0x1020)
except AXIUARTException as e:
    print(f"Timeout: {e}")
    # Check FPGA programming
    # Verify cable connection
    # Confirm baud rate matches
```

**Invalid Address:**
```python
try:
    driver.write_reg32(0x9999, 0x1234)  # Non-existent register
except AXIUARTException as e:
    print(f"Device returned error: {e}")
    # Check register map
    # Verify address alignment
```

## Configuration

### Serial Port Selection

**Windows:**
```python
PORT = 'COM3'  # Check Device Manager → Ports (COM & LPT)
```

**Linux:**
```python
PORT = '/dev/ttyUSB0'  # USB-UART adapter
PORT = '/dev/ttyACM0'  # Arduino-style boards
```

### Baud Rate

Must match FPGA configuration (default: 115200 baud).

```python
BAUDRATE = 115200  # Standard rate, reliable
BAUDRATE = 230400  # 2x faster (verify FPGA support)
BAUDRATE = 921600  # Maximum (cable quality critical)
```

### Timeout

Adjust based on expected response time and cable length.

```python
TIMEOUT = 1.0   # Default: 1 second
TIMEOUT = 0.5   # Fast local connection
TIMEOUT = 5.0   # Slow/long cable
```

## Performance Considerations

### Single Register Operations

- Write: ~1ms per transaction (at 115200 baud)
- Read: ~2ms per transaction (includes response time)
- Limited by UART bandwidth and protocol overhead

### Burst Operations

- Write N registers: ~1ms + (N × 0.3ms)
- Read N registers: ~2ms + (N × 0.3ms)
- Significant improvement for multiple registers
- Up to 3x faster than individual operations

### Optimization Tips

1. **Use burst operations** for multiple registers
2. **Cache frequently read values** instead of polling
3. **Minimize read-modify-write cycles** where possible
4. **Use appropriate timeout values** to avoid unnecessary waits
5. **Consider higher baud rates** if cable quality permits

## Testing

### Unit Tests

```bash
# Run protocol layer tests
python -m pytest tests/test_protocol.py

# Run driver tests (requires hardware)
python -m pytest tests/test_driver.py --port COM3
```

### Hardware Verification

```bash
# Quick connectivity test
python examples/example_basic.py

# Comprehensive hardware test
python examples/example_diagnostic.py

# LED functionality test
python examples/led_control.py test
```

## Troubleshooting

### Issue: Port Not Found

**Symptoms:** `SerialException: could not open port`

**Solutions:**
- Windows: Verify COM port in Device Manager
- Linux: Check `/dev/ttyUSB*` or `/dev/ttyACM*` exists
- Verify FTDI/USB-UART drivers installed
- Try different USB port

### Issue: Timeout on All Operations

**Symptoms:** `AXIUARTException: Response timeout`

**Solutions:**
- Verify FPGA is programmed with AXIUART design
- Check UART TX/RX connections (not swapped)
- Confirm baud rate matches FPGA (115200)
- Test with loopback (TX→RX) to verify cable
- Check if UART is enabled in FPGA design

### Issue: CRC Errors

**Symptoms:** `AXIUARTException: CRC mismatch`

**Solutions:**
- Check cable quality and length
- Reduce baud rate to 57600 or 38400
- Add delays between transactions
- Verify ground connection between systems

### Issue: Incorrect Read Values

**Symptoms:** Read values don't match written values

**Solutions:**
- Verify register address is correct
- Check address alignment (must be 4-byte aligned)
- Confirm register is writable (not read-only)
- Verify register width (32-bit only)
- Check if register is implemented in hardware

### Issue: LED Not Responding

**Symptoms:** LED writes succeed but no visual change

**Solutions:**
- Verify REG_TEST_LED (0x1044) is implemented
- Check LED connections in hardware design
- Read back register to confirm write succeeded
- Verify LED output is connected to physical LEDs
- Check if LEDs are active-high or active-low

## Development

### Adding Custom Applications

1. Import the driver:
```python
from axiuart_driver import AXIUARTDriver, AXIUARTException
```

2. Create application logic:
```python
def my_application(port: str):
    with AXIUARTDriver(port) as driver:
        # Your custom logic here
        driver.write_reg32(MY_CUSTOM_REG, value)
        result = driver.read_reg32(MY_CUSTOM_REG)
        return result
```

3. Add error handling:
```python
try:
    result = my_application('COM3')
except AXIUARTException as e:
    print(f"Error: {e}")
    sys.exit(1)
```

### Extending the Driver

To add new register definitions:

```python
# In axiuart_driver.py
class AXIUARTDriver:
    REG_MY_CUSTOM = BASE_ADDR + 0x200
    
    def get_my_custom(self) -> int:
        """Read MY_CUSTOM register"""
        return self.read_reg32(self.REG_MY_CUSTOM)
```

## Dependencies

### Required
- **Python 3.7+**
- **pyserial 3.4+** : Serial port communication

### Optional
- **pytest** : For running tests
- **logging** : Built-in, for debug output

### Installation

```bash
# Install dependencies
pip install pyserial

# Install from source
cd software/axiuart_driver
pip install -e .

# Or install specific dependencies
pip install -r requirements.txt
```

## Version History

### v1.1.0 (2025-12-14)
- Added REG_TEST_LED (0x1044) support
- Created LEDController class for LED control
- Added led_control.py with interactive mode
- Added animation patterns (count, knight rider, blink)
- Updated documentation with LED examples

### v1.0.0 (Initial)
- Core AXIUARTDriver implementation
- Protocol layer with CRC-8
- Basic register read/write operations
- Burst transaction support
- Example applications
- Hardware diagnostic tools

## License

See LICENSE file in repository root.

## References

- **Protocol Specification:** `docs/axiuart_bus_protocol.md`
- **RTL Design:** `rtl/README.md`
- **Register Map:** `rtl/register_block/Register_Block.sv`
- **UVM Testbench:** `sim/uvm/UVM_ARCHITECTURE.md`

## Support

For issues, questions, or contributions:
- Repository: MameMame777/AXIUART_
- Documentation: `software/axiuart_driver/examples/LED_CONTROL_README.md`
