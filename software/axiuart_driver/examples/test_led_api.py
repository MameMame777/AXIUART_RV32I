#!/usr/bin/env python3
"""Quick LED test with Python API"""
import sys
sys.path.insert(0, '..')

from axiuart_driver.examples.led_control import LEDController
import time

print("=" * 60)
print("LED Control API Demo")
print("=" * 60)

with LEDController('COM3', baudrate=115200) as led:
    print("\n[1] Individual bit control")
    led.all_off()
    for bit in range(4):
        print(f"    Turning on LED{bit}...")
        led.set_bit(bit, True)
        time.sleep(0.3)
    
    print("\n[2] Reading LED value")
    value = led.get_led()
    print(f"    LED = {value} (0b{value:04b})")
    
    print("\n[3] Toggling bits")
    for bit in [0, 2]:
        print(f"    Toggling LED{bit}...")
        led.toggle_bit(bit)
        time.sleep(0.3)
        value = led.get_led()
        print(f"    LED = {value} (0b{value:04b})")
    
    print("\n[4] Setting specific patterns")
    patterns = [0x5, 0xA, 0xC, 0x3, 0xF]
    for pattern in patterns:
        led.set_led(pattern)
        print(f"    LED = 0b{pattern:04b}")
        time.sleep(0.3)
    
    print("\n[5] All off")
    led.all_off()
    print("    LEDs turned off")

print("\n" + "=" * 60)
print("Demo completed")
