#!/usr/bin/env python3
"""
Hardware Diagnostic - Debug register interface timing and sequencing
"""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from axiuart_driver import AXIUARTDriver, registers


def main():
    PORT = 'COM3'
    BAUDRATE = 115200
    
    print("=" * 70)
    print("TD4 CPU Register Interface Diagnostic")
    print("=" * 70)
    
    driver = AXIUARTDriver(PORT, baudrate=BAUDRATE)
    driver.open()
    time.sleep(0.1)
    
    # Test 1: Check CPU status
    print("\n[1] Reading CPU Debug Status...")
    status = driver.read_reg32(registers.REG_CPU_DBG_STATUS)
    halted = (status & 0x01) != 0
    running = (status & 0x02) != 0
    print(f"    Status: 0x{status:08X}")
    print(f"    Halted: {halted}, Running: {running}")
    
    # Test 2: Halt CPU
    print("\n[2] Halting CPU...")
    driver.write_reg32(registers.REG_CPU_DBG_CTRL, 0x00000001)
    time.sleep(0.01)
    status = driver.read_reg32(registers.REG_CPU_DBG_STATUS)
    halted = (status & 0x01) != 0
    print(f"    Status after halt: 0x{status:08X}, Halted={halted}")
    
    # Test 3: Register write/read with various delays
    print("\n[3] Testing register interface timing (R1)...")
    test_value = 0xABCD
    
    print(f"    Writing 0x{test_value:04X} to R1...")
    driver.write_reg32(registers.REG_CPU_REG_INDEX, 1)
    time.sleep(0.002)
    driver.write_reg32(registers.REG_CPU_REG_DATA, test_value)
    time.sleep(0.002)
    
    print(f"    Reading back R1 (with delays)...")
    driver.write_reg32(registers.REG_CPU_REG_INDEX, 1)
    time.sleep(0.002)
    readback1 = driver.read_reg32(registers.REG_CPU_REG_DATA)
    print(f"    Read #1: 0x{readback1:04X}")
    
    # Read without updating index
    readback2 = driver.read_reg32(registers.REG_CPU_REG_DATA)
    print(f"    Read #2 (no index update): 0x{readback2:04X}")
    
    # Read with index update again
    driver.write_reg32(registers.REG_CPU_REG_INDEX, 1)
    time.sleep(0.002)
    readback3 = driver.read_reg32(registers.REG_CPU_REG_DATA)
    print(f"    Read #3 (index updated): 0x{readback3:04X}")
    
    if readback3 == test_value:
        print(f"    ✓ SUCCESS: Register R/W working correctly")
    else:
        print(f"    ✗ FAIL: Expected 0x{test_value:04X}, got 0x{readback3:04X}")
    
    # Test 4: Multiple registers
    print("\n[4] Testing multiple register writes...")
    for i in range(4):
        value = 0x1000 + i
        driver.write_reg32(registers.REG_CPU_REG_INDEX, i)
        time.sleep(0.002)
        driver.write_reg32(registers.REG_CPU_REG_DATA, value)
        time.sleep(0.002)
        print(f"    R{i} <= 0x{value:04X}")
    
    print("    Reading back...")
    all_match = True
    for i in range(4):
        driver.write_reg32(registers.REG_CPU_REG_INDEX, i)
        time.sleep(0.002)
        value = driver.read_reg32(registers.REG_CPU_REG_DATA)
        expected = 0x1000 + i
        match = value == expected
        all_match = all_match and match
        symbol = "✓" if match else "✗"
        print(f"    {symbol} R{i} = 0x{value:04X} (expected 0x{expected:04X})")
    
    if all_match:
        print("    ✓ All registers match!")
    
    # Test 5: Flags register
    print("\n[5] Testing FLAGS register...")
    test_flags = 0x07  # All flags set
    driver.write_reg32(registers.REG_CPU_FLAGS, test_flags)
    time.sleep(0.002)
    flags = driver.read_reg32(registers.REG_CPU_FLAGS)
    z_flag = (flags >> 2) & 1
    n_flag = (flags >> 1) & 1
    c_flag = flags & 1
    print(f"    Flags: 0x{flags:02X} (Z={z_flag}, N={n_flag}, C={c_flag})")
    
    if flags & 0x07 == test_flags:
        print(f"    ✓ FLAGS register working")
    else:
        print(f"    ✗ FLAGS mismatch: expected 0x{test_flags:02X}, got 0x{flags:02X}")
    
    # Test 6: PC register
    print("\n[6] Testing PC register...")
    test_pc = 0x0000
    driver.write_reg32(registers.REG_CPU_PC, test_pc)
    time.sleep(0.002)
    pc = driver.read_reg32(registers.REG_CPU_PC)
    print(f"    PC: 0x{pc:04X}")
    
    if pc == test_pc:
        print(f"    ✓ PC register working")
    else:
        print(f"    ✗ PC mismatch: expected 0x{test_pc:04X}, got 0x{pc:04X}")
    
    # Test 7: Memory interface
    print("\n[7] Testing memory write/read...")
    mem_addr = 0x0000
    mem_data = 0x0280  # ADD R1, R2 instruction
    
    print(f"    Writing 0x{mem_data:04X} to memory[0x{mem_addr:04X}]...")
    driver.write_reg32(registers.REG_CPU_MEM_ADDR, mem_addr)
    time.sleep(0.002)
    driver.write_reg32(registers.REG_CPU_MEM_WDATA, mem_data)
    time.sleep(0.002)
    driver.write_reg32(registers.REG_CPU_MEM_CTRL, 0x00000002)  # Write request
    time.sleep(0.005)
    
    # Check busy flag
    ctrl = driver.read_reg32(registers.REG_CPU_MEM_CTRL)
    busy = (ctrl & 0x02) != 0
    print(f"    Memory control: 0x{ctrl:08X}, Busy={busy}")
    
    # Read back
    print(f"    Reading memory[0x{mem_addr:04X}]...")
    driver.write_reg32(registers.REG_CPU_MEM_ADDR, mem_addr)
    time.sleep(0.002)
    driver.write_reg32(registers.REG_CPU_MEM_CTRL, 0x00000001)  # Read request
    time.sleep(0.005)
    readback = driver.read_reg32(registers.REG_CPU_MEM_RDATA)
    print(f"    Memory read: 0x{readback:04X}")
    
    if readback == mem_data:
        print(f"    ✓ SUCCESS: Memory R/W working")
    else:
        print(f"    ✗ FAIL: Expected 0x{mem_data:04X}, got 0x{readback:04X}")
    
    driver.close()
    print("\n" + "=" * 70)
    print("Diagnostic Complete")
    print("=" * 70)


if __name__ == '__main__':
    main()
