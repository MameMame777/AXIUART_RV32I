#!/usr/bin/env python3
"""RV32I CPU Debug Tool

Diagnose why LEDs are not changing by checking:
- CPU status (halted/running/break)
- Performance counters (instruction count)
- Register file (x10-x18 used in LED programs)
- LED hardware test (direct write)

Usage:
    python debug_cpu.py COM3
    python debug_cpu.py COM3 --registers
    python debug_cpu.py COM3 --led-test
"""

import sys
import os
import time

# Add parent directories to path
script_dir = os.path.dirname(os.path.abspath(__file__))
rv32i_dir = os.path.dirname(script_dir)
software_dir = os.path.dirname(rv32i_dir)
sys.path.insert(0, software_dir)

from axiuart_driver import AXIUARTDriver

# Register addresses
CPU_MEM_CTRL = 0x1234
PERF_INSN_COUNT = 0x1264
DBG_RF_ADDR = 0x1270
DBG_RF_DATA = 0x1274
LED_ADDR_MMIO = 0x407C

REG_NAMES = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
             "s0/fp", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
             "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
             "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"]


def read_cpu_status(driver):
    """Read and decode CPU status register"""
    status = driver.read_reg32(CPU_MEM_CTRL)
    return {
        'raw': status,
        'halted': bool(status & 0x200),
        'break': bool(status & 0x400),
        'busy': bool(status & 0x40)
    }


def read_register(driver, reg_num):
    """Read single register from register file"""
    driver.write_reg32(DBG_RF_ADDR, reg_num)
    time.sleep(0.001)
    return driver.read_reg32(DBG_RF_DATA)


def read_register_file(driver, reg_list=None):
    """Read specified registers (or all if None)"""
    if reg_list is None:
        reg_list = range(32)
    
    registers = {}
    for i in reg_list:
        registers[i] = read_register(driver, i)
    return registers


def test_led_hardware(driver):
    """Test LED hardware by writing patterns directly"""
    print("\n" + "=" * 60)
    print("LED HARDWARE TEST")
    print("=" * 60)
    print(f"Writing test patterns directly to LED MMIO address 0x{LED_ADDR_MMIO:04x}")
    print("Watch the LEDs - they should change every 0.8 seconds\n")
    
    sys.path.insert(0, rv32i_dir)
    from rv32i.memory import write_cpu_mem
    from rv32i import halt_cpu
    
    # Halt CPU first to ensure access
    halt_cpu(driver)
    print("[CPU] Halted for LED test\n")
    
    test_patterns = [
        (0x1, "0001", "LED0 only"),
        (0x2, "0010", "LED1 only"),
        (0x4, "0100", "LED2 only"),
        (0x8, "1000", "LED3 only"),
        (0xF, "1111", "All LEDs"),
        (0x0, "0000", "All OFF"),
        (0x5, "0101", "Alternating 1"),
        (0xA, "1010", "Alternating 2"),
        (0xF, "1111", "All ON"),
        (0x0, "0000", "All OFF")
    ]
    
    for pattern, binary, desc in test_patterns:
        print(f"  Writing 0x{pattern:X} ({binary}) - {desc}")
        write_cpu_mem(driver, LED_ADDR_MMIO, pattern)
        time.sleep(0.8)
    
    print("\n[TEST] Complete!")
    print("Question: Did the LEDs physically change? (This tests hardware)")


def check_program_execution(driver):
    """Check if program is actually executing"""
    print("\n" + "=" * 60)
    print("PROGRAM EXECUTION CHECK")
    print("=" * 60)
    
    try:
        insn1 = driver.read_reg32(PERF_INSN_COUNT)
        print(f"Initial instruction count: {insn1:,}")
        
        time.sleep(1)
        
        insn2 = driver.read32(PERF_INSN_COUNT)
        print(f"After 1 second: {insn2:,}")
        
        if insn2 > insn1:
            print(f"✓ CPU IS EXECUTING ({insn2 - insn1:,} instructions/sec)")
        else:
            print("✗ CPU NOT EXECUTING (instruction count not increasing)")
    except Exception as e:
        print(f"Cannot read instruction count: {e}")


def main():
    if len(sys.argv) < 2:
        print("Usage: python debug_cpu.py <port> [--registers] [--led-test]")
        print("  Examples:")
        print("    python debug_cpu.py COM3")
        print("    python debug_cpu.py COM3 --registers")
        print("    python debug_cpu.py COM3 --led-test")
        return 1
    
    port = sys.argv[1]
    show_all_registers = '--registers' in sys.argv
    led_test = '--led-test' in sys.argv
    
    print(f"[UART] Connecting to {port} at 115200 baud...")
    
    try:
        with AXIUARTDriver(port, 115200) as driver:
            print("[UART] ✓ Connected\n")
            
            # 1. CPU Status
            print("=" * 60)
            print("CPU STATUS")
            print("=" * 60)
            status = read_cpu_status(driver)
            print(f"Raw value:      0x{status['raw']:08x}")
            print(f"CPU Halted:     {status['halted']}")
            print(f"Hit EBREAK:     {status['break']}")
            print(f"Busy:           {status['busy']}")
            
            # 2. Instruction Count
            try:
                insn_count = driver.read_reg32(PERF_INSN_COUNT)
                print(f"Instructions:   {insn_count:,}")
                
                if insn_count == 0:
                    print("  ⚠ WARNING: Zero instructions executed!")
                    print("  → CPU might not have started or reset")
                elif status['break']:
                    print(f"  ✓ Program hit EBREAK after {insn_count} instructions")
                elif status['halted']:
                    print(f"  ⚠ CPU halted after {insn_count} instructions")
                else:
                    print(f"  ✓ CPU running, {insn_count} instructions executed")
            except Exception as e:
                print(f"Instructions:   SKIPPED (register not accessible)")
                print(f"                This is OK - performance counters may not be implemented")
                insn_count = None
            
            # 3. Key Registers (used in LED programs)
            print("\n" + "=" * 60)
            print("KEY REGISTERS (used in LED programs)")
            print("=" * 60)
            
            sys.path.insert(0, rv32i_dir)
            from rv32i import halt_cpu
            
            # Halt CPU to read registers safely
            if not status['halted']:
                print("[NOTE] Halting CPU to read registers safely...")
                halt_cpu(driver)
            
            key_regs = {
                10: "a0 - used in patterns",
                11: "a1 - used in patterns", 
                12: "a2 - used in patterns",
                15: "a5 - LED base (should be 0x4000)",
                16: "a6 - LED addr (should be 0x407C)",
                17: "a7 - LED value (0x5 or 0xA)",
                18: "s2 - LED value (0xA)"
            }
            
            try:
                for reg_num, desc in key_regs.items():
                    value = read_register(driver, reg_num)
                    print(f"x{reg_num:2d} ({REG_NAMES[reg_num]:6s}) = 0x{value:08x}  # {desc}")
                
                # Check if LED address is correct
                x15 = read_register(driver, 15)
                x16 = read_register(driver, 16)
                print(f"\n[ANALYSIS]")
                if x15 == 0x00004000:
                    print(f"  ✓ x15 = 0x{x15:08x} (correct LED base)")
                else:
                    print(f"  ✗ x15 = 0x{x15:08x} (expected 0x00004000)")
                
                if x16 == 0x0000407C:
                    print(f"  ✓ x16 = 0x{x16:08x} (correct LED address)")
                elif x15 == 0x00004000 and (x16 & 0xFFFF) == 0x007C:
                    print(f"  ~ x16 = 0x{x16:08x} (close, offset might be 0x7C)")
                else:
                    print(f"  ✗ x16 = 0x{x16:08x} (expected 0x0000407C)")
            except Exception as e:
                print(f"SKIPPED: Register file debug not accessible ({e})")
                print("This is OK - we can still test LED hardware directly")
            
            # 4. All Registers (if requested)
            if show_all_registers:
                print("\n" + "=" * 60)
                print("ALL REGISTERS (x0-x31)")
                print("=" * 60)
                registers = read_register_file(driver)
                for i in range(0, 32, 4):
                    line = ""
                    for j in range(4):
                        idx = i + j
                        if idx < 32:
                            line += f"x{idx:2d}=0x{registers[idx]:08x}  "
                    print(line)
            
            # 5. LED Hardware Test (if requested)
            if led_test:
                test_led_hardware(driver)
            
            print("\n" + "=" * 60)
            print("DIAGNOSTIC SUMMARY")
            print("=" * 60)
            
            if insn_count == 0:
                print("⚠ ISSUE: No instructions executed")
                print("  Possible causes:")
                print("  1. CPU not started (run_cpu() failed)")
                print("  2. CPU in reset state")
                print("  3. Memory write failed (program not loaded)")
            elif status['halted'] and not status['break']:
                print("⚠ ISSUE: CPU halted without EBREAK")
                print("  Possible causes:")
                print("  1. Exception occurred")
                print("  2. Manual halt after run")
            elif status['break']:
                print("✓ Program executed and hit EBREAK (expected for 'simple' pattern)")
                if x16 != 0x0000407C:
                    print("  But LED address in x16 looks wrong")
                    print("  → Check instruction encoding in patterns.py")
            else:
                print("✓ CPU is running")
                if not led_test:
                    print("  Run with --led-test to verify LED hardware")
            
            print("\n[DONE] Debug complete")
            print("Next steps:")
            print("  1. If LEDs don't work with --led-test, check hardware")
            print("  2. If hardware OK but program doesn't work, check instruction encoding")
            print("  3. Run: python debug_cpu.py COM3 --led-test")
            
    except Exception as e:
        print(f"\n[ERROR] {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
