#!/usr/bin/env python3
"""
RV32I CPU LED Control via MMIO
Demonstrates loading and running a program on the RV32I CPU to control LEDs
"""

import sys
import os
import time

# Add parent directory to path for importing axiuart_driver package
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from axiuart_driver import AXIUARTDriver

# Configuration
SERIAL_PORT = 'COM3'
BAUDRATE = 115200

# LED MMIO address in RV32I address space
LED_MMIO_ADDR = 0x407C  # From rtl/cpu/rv32i_isa_pkg.sv

# CPU Control bits in REG_CPU_MEM_CTRL
CPU_RUN = (1 << 7)      # Start CPU
CPU_HALT = (1 << 8)     # Halt CPU
CPU_HALTED = (1 << 9)   # CPU halted status (RO)
CPU_BREAK = (1 << 10)   # CPU breakpoint (RO)
MEM_READ = (1 << 4)     # Memory read request
MEM_WRITE = (1 << 5)    # Memory write request
MEM_BUSY = (1 << 6)     # Memory busy (RO)

def write_cpu_mem(driver, word_addr, data):
    """Write to CPU memory via debug interface"""
    # Write address (word-aligned)
    driver.write_reg32(driver.REG_CPU_MEM_ADDR, word_addr << 2)
    # Write data
    driver.write_reg32(driver.REG_CPU_MEM_WDATA, data)
    # Trigger write (full word = 0xF byte enables)
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, MEM_WRITE | 0xF)
    # Wait for completion
    for _ in range(10):
        ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
        if not (ctrl & MEM_BUSY):
            break
        time.sleep(0.001)

def read_cpu_mem(driver, word_addr):
    """Read from CPU memory via debug interface"""
    # Write address
    driver.write_reg32(driver.REG_CPU_MEM_ADDR, word_addr << 2)
    # Trigger read
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, MEM_READ | 0xF)
    # Wait for completion
    for _ in range(10):
        ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
        if not (ctrl & MEM_BUSY):
            break
        time.sleep(0.001)
    # Read data
    return driver.read_reg32(driver.REG_CPU_MEM_RDATA)

def halt_cpu(driver):
    """Halt the CPU"""
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_HALT)
    # Wait for halted status
    for _ in range(100):
        ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
        if ctrl & CPU_HALTED:
            return True
        time.sleep(0.001)
    return False

def run_cpu(driver):
    """Start/resume CPU execution"""
    driver.write_reg32(driver.REG_CPU_MEM_CTRL, CPU_RUN)

def load_led_program(driver, led_value):
    """
    Load RV32I program to set LED value
    
    Program:
        LUI x17, 0x4         # x17 = 0x4000 (MMIO base)
        ADDI x1, x0, VALUE   # x1 = led_value
        SW x1, 0x7C(x17)     # Write to LED at 0x407C
        EBREAK               # Halt
    """
    print(f"\nLoading LED program (value = 0x{led_value:X})...")
    
    # Halt CPU before loading
    if not halt_cpu(driver):
        print("[FAIL] Failed to halt CPU")
        return False
    print("[OK] CPU halted")
    
    # Encode instructions
    insn_lui = 0x000048B7              # LUI x17, 0x4
    insn_addi = 0x00000093 | (led_value << 20)  # ADDI x1, x0, led_value
    insn_sw = 0x0618AE23               # SW x1, 0x7C(x17)
    insn_ebreak = 0x00100073           # EBREAK
    
    # Write program to memory
    write_cpu_mem(driver, 0, insn_lui)
    write_cpu_mem(driver, 1, insn_addi)
    write_cpu_mem(driver, 2, insn_sw)
    write_cpu_mem(driver, 3, insn_ebreak)
    
    # Verify program
    verify = [
        read_cpu_mem(driver, 0),
        read_cpu_mem(driver, 1),
        read_cpu_mem(driver, 2),
        read_cpu_mem(driver, 3)
    ]
    
    expected = [insn_lui, insn_addi, insn_sw, insn_ebreak]
    if verify == expected:
        print(f"[OK] Program loaded and verified")
        print(f"  {len(expected)} instructions written")
        return True
    else:
        print(f"[FAIL] Program verification failed")
        return False

def read_led_via_mmio(driver):
    """Read LED value through CPU MMIO (requires CPU to be running or use debug mem access)"""
    # Use debug memory interface to read LED MMIO location
    # LED is at 0x407C, which is word address 0x101F in CPU memory space
    led_addr_word = LED_MMIO_ADDR >> 2
    return read_cpu_mem(driver, led_addr_word) & 0xF

def main():
    print("=" * 60)
    print("RV32I CPU LED Control Demo")
    print("=" * 60)
    
    driver = AXIUARTDriver(SERIAL_PORT, baudrate=BAUDRATE, debug=False)
    
    try:
        # Connect
        driver.open()
        print("[OK] Connected to FPGA")
        
        # Get CPU status
        ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
        print(f"\nInitial CPU status:")
        print(f"  - Halted: {bool(ctrl & CPU_HALTED)}")
        print(f"  - Break:  {bool(ctrl & CPU_BREAK)}")
        
        # Test sequence
        led_values = [0x1, 0x2, 0x4, 0x8, 0xF, 0x0, 0x5, 0xA]
        
        for i, led_val in enumerate(led_values, 1):
            print(f"\n[{i}/{len(led_values)}] Setting LED = 0b{led_val:04b} (0x{led_val:X})")
            
            # Load program
            if not load_led_program(driver, led_val):
                print("[FAIL] Failed to load program")
                break
            
            # Run CPU
            run_cpu(driver)
            print("[OK] CPU started")
            
            # Wait for CPU to complete (check for EBREAK)
            completed = False
            for _ in range(50):  # Wait up to 500ms
                ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
                if ctrl & CPU_BREAK:
                    completed = True
                    break
                time.sleep(0.01)
            
            # Check CPU status
            ctrl = driver.read_reg32(driver.REG_CPU_MEM_CTRL)
            print(f"  CPU status: halted={bool(ctrl & CPU_HALTED)}, break={bool(ctrl & CPU_BREAK)}, busy={bool(ctrl & MEM_BUSY)}")
            
            if ctrl & CPU_BREAK:
                print("[OK] CPU hit EBREAK")
            else:
                print("[WARN] CPU did not hit EBREAK (may still be running)")
            
            # Read LED value
            led_read = read_led_via_mmio(driver)
            print(f"[OK] LED value read: 0b{led_read:04b} (0x{led_read:X})")
            
            if led_read == led_val:
                print("[PASS] LED value MATCH")
            else:
                print(f"[FAIL] LED mismatch (expected 0x{led_val:X}, got 0x{led_read:X})")
            
            time.sleep(0.3)
        
        print("\n" + "=" * 60)
        print("Demo completed successfully!")
        
    except Exception as e:
        print(f"\n[ERROR] {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    finally:
        driver.close()
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
