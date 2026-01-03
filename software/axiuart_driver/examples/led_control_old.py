#!/usr/bin/env python3
"""
LED Control Example for AXIUART
Control 4-bit LED register (REG_TEST_LED from register map)
"""

import sys
import time
import logging
from axiuart_driver import AXIUARTDriver, AXIUARTException


class LEDController:
    """4-bit LED controller for AXIUART"""
    
    # Use register constant from driver (auto-generated from register map)
    LED_MASK = 0x0F        # 4-bit mask for LED values
    
    def __init__(self, port: str, baudrate: int = 115200, debug: bool = False):
        """
        Initialize LED controller
        
        Args:
            port: Serial port (e.g., 'COM3' or '/dev/ttyUSB0')
            baudrate: UART baud rate (default 115200)
            debug: Enable debug logging
        """
        self.driver = AXIUARTDriver(port, baudrate=baudrate, debug=debug)
        self.current_value = 0
    
    def open(self) -> None:
        """Open connection to AXIUART device"""
        self.driver.open()
        # Read current LED value
        self.current_value = self.get_led() & self.LED_MASK
    
    def close(self) -> None:
        """Close connection"""
        self.driver.close()
    
    def __enter__(self):
        """Context manager entry"""
        self.open()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.close()
    
    def set_led(self, value: int) -> None:
        """
        Set LED value (4-bit)
        
        Args:
            value: LED value (0-15), where each bit controls one LED
        """
        if not (0 <= value <= 15):
            raise ValueError(f"LED value must be 0-15, got {value}")
        
        self.driver.write_reg32(self.driver.REG_TEST_LED, value & self.LED_MASK)
        self.current_value = value & self.LED_MASK
    
    def get_led(self) -> int:
        """
        Read current LED value
        
        Returns:
            Current 4-bit LED value
        """
        value = self.driver.read_reg32(self.driver.REG_TEST_LED)
        return value & self.LED_MASK
    
    def set_bit(self, bit: int, state: bool = True) -> None:
        """
        Set or clear individual LED bit
        
        Args:
            bit: Bit position (0-3)
            state: True to turn on, False to turn off
        """
        if not (0 <= bit <= 3):
            raise ValueError(f"LED bit must be 0-3, got {bit}")
        
        if state:
            self.current_value |= (1 << bit)
        else:
            self.current_value &= ~(1 << bit)
        
        self.set_led(self.current_value)
    
    def toggle_bit(self, bit: int) -> None:
        """
        Toggle individual LED bit
        
        Args:
            bit: Bit position (0-3)
        """
        if not (0 <= bit <= 3):
            raise ValueError(f"LED bit must be 0-3, got {bit}")
        
        self.current_value ^= (1 << bit)
        self.set_led(self.current_value)
    
    def all_on(self) -> None:
        """Turn all LEDs on"""
        self.set_led(0xF)
    
    def all_off(self) -> None:
        """Turn all LEDs off"""
        self.set_led(0x0)
    
    def pattern_binary_count(self, delay: float = 0.5, cycles: int = 2) -> None:
        """
        Display binary counting pattern
        
        Args:
            delay: Delay between steps in seconds
            cycles: Number of complete cycles (0-15)
        """
        for _ in range(cycles):
            for i in range(16):
                self.set_led(i)
                print(f"LED = {i:4d} (0b{i:04b})")
                time.sleep(delay)
    
    def pattern_knight_rider(self, delay: float = 0.2, cycles: int = 3) -> None:
        """
        Knight Rider style LED pattern
        
        Args:
            delay: Delay between steps in seconds
            cycles: Number of complete cycles
        """
        sequence = [0x1, 0x2, 0x4, 0x8, 0x4, 0x2]
        
        for _ in range(cycles):
            for pattern in sequence:
                self.set_led(pattern)
                print(f"LED = 0b{pattern:04b}")
                time.sleep(delay)
    
    def pattern_blink_all(self, delay: float = 0.5, count: int = 5) -> None:
        """
        Blink all LEDs on/off
        
        Args:
            delay: Delay between on/off in seconds
            count: Number of blinks
        """
        for i in range(count):
            self.all_on()
            print(f"[{i+1}/{count}] LEDs ON  (0b1111)")
            time.sleep(delay)
            
            self.all_off()
            print(f"[{i+1}/{count}] LEDs OFF (0b0000)")
            time.sleep(delay)


def demo_interactive(controller: LEDController) -> None:
    """Interactive LED control demo"""
    print("\n" + "=" * 60)
    print("Interactive LED Control")
    print("=" * 60)
    print("Commands:")
    print("  0-15  : Set LED value (decimal)")
    print("  0x0-F : Set LED value (hex)")
    print("  0b0000-1111 : Set LED value (binary)")
    print("  on <bit>  : Turn on LED bit (0-3)")
    print("  off <bit> : Turn off LED bit (0-3)")
    print("  toggle <bit> : Toggle LED bit (0-3)")
    print("  all_on  : Turn all LEDs on")
    print("  all_off : Turn all LEDs off")
    print("  read : Read current LED value")
    print("  count : Binary counting pattern")
    print("  knight : Knight Rider pattern")
    print("  blink : Blink all LEDs")
    print("  quit : Exit")
    print("=" * 60)
    
    while True:
        try:
            cmd = input("\nLED> ").strip().lower()
            
            if not cmd:
                continue
            
            if cmd == 'quit' or cmd == 'q':
                break
            
            elif cmd == 'read' or cmd == 'r':
                value = controller.get_led()
                print(f"LED = {value} (0b{value:04b}, 0x{value:X})")
            
            elif cmd == 'all_on':
                controller.all_on()
                print("All LEDs ON")
            
            elif cmd == 'all_off':
                controller.all_off()
                print("All LEDs OFF")
            
            elif cmd == 'count':
                print("Running binary count pattern...")
                controller.pattern_binary_count(delay=0.3, cycles=1)
            
            elif cmd == 'knight':
                print("Running Knight Rider pattern...")
                controller.pattern_knight_rider(delay=0.15, cycles=3)
            
            elif cmd == 'blink':
                print("Blinking all LEDs...")
                controller.pattern_blink_all(delay=0.5, count=5)
            
            elif cmd.startswith('on '):
                bit = int(cmd.split()[1])
                controller.set_bit(bit, True)
                print(f"LED bit {bit} turned ON")
            
            elif cmd.startswith('off '):
                bit = int(cmd.split()[1])
                controller.set_bit(bit, False)
                print(f"LED bit {bit} turned OFF")
            
            elif cmd.startswith('toggle '):
                bit = int(cmd.split()[1])
                controller.toggle_bit(bit)
                value = controller.get_led()
                print(f"LED bit {bit} toggled → 0b{value:04b}")
            
            else:
                # Try to parse as number
                if cmd.startswith('0x'):
                    value = int(cmd, 16)
                elif cmd.startswith('0b'):
                    value = int(cmd, 2)
                else:
                    value = int(cmd)
                
                controller.set_led(value)
                print(f"LED = {value} (0b{value:04b}, 0x{value:X})")
        
        except ValueError as e:
            print(f"Error: Invalid input - {e}")
        except KeyboardInterrupt:
            print("\nInterrupted")
            break
        except Exception as e:
            print(f"Error: {e}")


def main():
    """Main function with demo modes"""
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Configure serial port (adjust for your system)
    PORT = 'COM3'  # Linux: /dev/ttyUSB0, Windows: COM3/COM4
    BAUDRATE = 115200
    
    print("=" * 60)
    print("AXIUART LED Control Demo")
    print("=" * 60)
    print(f"Port: {PORT}")
    print(f"Baudrate: {BAUDRATE}")
    print(f"LED Register: 0x{AXIUARTDriver.REG_TEST_LED:04X} (REG_TEST_LED)")
    print("=" * 60)
    
    # Parse command line arguments
    if len(sys.argv) > 1:
        mode = sys.argv[1].lower()
    else:
        mode = 'interactive'
    
    try:
        with LEDController(PORT, baudrate=BAUDRATE, debug=False) as led:
            print(f"\n[OK] Connected to {PORT}")
            
            # Read initial LED value
            initial = led.get_led()
            print(f"Initial LED value: {initial} (0b{initial:04b})")
            
            if mode == 'interactive' or mode == 'i':
                demo_interactive(led)
            
            elif mode == 'count':
                print("\n[Demo] Binary counting pattern")
                led.pattern_binary_count(delay=0.5, cycles=2)
            
            elif mode == 'knight':
                print("\n[Demo] Knight Rider pattern")
                led.pattern_knight_rider(delay=0.2, cycles=5)
            
            elif mode == 'blink':
                print("\n[Demo] Blink all LEDs")
                led.pattern_blink_all(delay=0.5, count=10)
            
            elif mode == 'test':
                print("\n[Demo] All patterns test")
                print("\n1. Blink test...")
                led.pattern_blink_all(delay=0.3, count=3)
                
                print("\n2. Binary count test...")
                led.pattern_binary_count(delay=0.2, cycles=1)
                
                print("\n3. Knight Rider test...")
                led.pattern_knight_rider(delay=0.15, cycles=3)
            
            else:
                print(f"\nUnknown mode: {mode}")
                print("Available modes: interactive, count, knight, blink, test")
                return 1
            
            # Cleanup: turn off LEDs
            print("\n[OK] Demo completed")
            led.all_off()
            print("LEDs turned off")
    
    except AXIUARTException as e:
        print(f"\n[ERROR] AXIUART Error: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"\n[ERROR] Error: {e}", file=sys.stderr)
        return 1
    
    print("\n" + "=" * 60)
    print("Disconnected")
    return 0


if __name__ == '__main__':
    sys.exit(main())
