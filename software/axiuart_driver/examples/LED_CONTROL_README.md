# LED Control for AXIUART

4-bit LED control via REG_TEST_LED register (0x1044)

## Quick Start

### 1. Interactive Mode (Default)
```bash
python led_control.py
```

Interactive commands:
- `0-15` : Set LED value (decimal)
- `0x0-F` : Set LED value (hex)
- `0b0000-1111` : Set LED value (binary)
- `on <bit>` : Turn on LED bit (0-3)
- `off <bit>` : Turn off LED bit (0-3)
- `toggle <bit>` : Toggle LED bit (0-3)
- `all_on` : Turn all LEDs on
- `all_off` : Turn all LEDs off
- `read` : Read current LED value
- `count` : Binary counting pattern demo
- `knight` : Knight Rider pattern demo
- `blink` : Blink all LEDs demo
- `quit` : Exit

### 2. Demo Modes

**Binary counting pattern:**
```bash
python led_control.py count
```

**Knight Rider pattern:**
```bash
python led_control.py knight
```

**Blink all LEDs:**
```bash
python led_control.py blink
```

**All patterns test:**
```bash
python led_control.py test
```

## Python API Usage

```python
from axiuart_driver.examples.led_control import LEDController

# Create controller
with LEDController('COM3', baudrate=115200) as led:
    # Set LED value (0-15)
    led.set_led(0xF)  # All on
    
    # Control individual bits
    led.set_bit(0, True)   # Turn on LED0
    led.set_bit(1, False)  # Turn off LED1
    led.toggle_bit(2)      # Toggle LED2
    
    # Read current value
    value = led.get_led()
    print(f"LED = 0b{value:04b}")
    
    # Quick patterns
    led.all_on()
    led.all_off()
    
    # Animation patterns
    led.pattern_binary_count(delay=0.5, cycles=2)
    led.pattern_knight_rider(delay=0.2, cycles=3)
    led.pattern_blink_all(delay=0.5, count=5)
```

## Register Specification

- **Address:** 0x1044 (REG_TEST_LED)
- **Size:** 32-bit register (only lower 4 bits used)
- **Access:** Read/Write
- **Bits:**
  - [3:0] : LED control bits
  - [31:4] : Reserved (read as 0)

## LED Bit Mapping

```
Bit 3: LED[3]
Bit 2: LED[2]
Bit 1: LED[1]
Bit 0: LED[0]
```

## Examples

### Example 1: Turn on all LEDs
```python
with LEDController('COM3') as led:
    led.all_on()  # 0xF -> 0b1111
```

### Example 2: Binary counter
```python
with LEDController('COM3') as led:
    for i in range(16):
        led.set_led(i)
        time.sleep(0.5)
```

### Example 3: Individual bit control
```python
with LEDController('COM3') as led:
    led.set_bit(0, True)   # LED0 = ON
    led.set_bit(3, True)   # LED3 = ON
    # Result: 0b1001 (LED0 and LED3 are on)
```

## Configuration

Edit the PORT and BAUDRATE constants in led_control.py:

```python
PORT = 'COM3'      # Windows: COM3, COM4, etc.
                   # Linux: /dev/ttyUSB0, /dev/ttyACM0
BAUDRATE = 115200  # Must match FPGA configuration
```

## Troubleshooting

**Port access error:**
- Windows: Check Device Manager for correct COM port
- Linux: Add user to dialout group: `sudo usermod -a -G dialout $USER`

**Timeout errors:**
- Verify FPGA is programmed with AXIUART design
- Check serial port settings (baudrate, port name)
- Ensure UART cable is properly connected

**LED not responding:**
- Verify REG_TEST_LED register is implemented in hardware
- Check that LED output is connected to physical LEDs
- Read back register value to confirm write succeeded

## Dependencies

- pyserial
- axiuart_driver module

Install dependencies:
```bash
pip install pyserial
```

## Related Files

- `axiuart_driver.py` : Main driver implementation
- `example_basic.py` : Basic register read/write example
- `protocol.py` : UART protocol implementation
