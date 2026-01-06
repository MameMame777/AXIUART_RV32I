#!/usr/bin/env python3
"""Debug address mapping"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

port = sys.argv[1] if len(sys.argv) > 1 else 'COM3'

with AXIUARTDriver(port, 115200) as driver:
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
    from rv32i import halt_cpu
    from rv32i.memory import write_cpu_mem, read_cpu_mem
    
    halt_cpu(driver)
    
    print("Testing address ranges...")
    print()
    
    # Test different addresses
    test_addrs = [0x0000, 0x0004, 0x1000, 0x1FFC, 0x407C, 0x5000]
    
    for addr in test_addrs:
        test_val = 0xA5A5A500 | addr
        try:
            print(f"Testing 0x{addr:04x}...")
            write_cpu_mem(driver, addr, test_val)
            readback = read_cpu_mem(driver, addr)
            
            if readback == test_val:
                print(f"  ✓ 0x{addr:04x}: Write OK (0x{readback:08x})")
            else:
                print(f"  ✗ 0x{addr:04x}: Write FAILED (wrote 0x{test_val:08x}, read 0x{readback:08x})")
        except Exception as e:
            print(f"  ✗ 0x{addr:04x}: ERROR - {e}")
        print()
    
    # Check if PC can be read
    print("Checking CPU control registers...")
    try:
        # CPU_MEM_CTRL offset in Register_Block
        CPU_MEM_CTRL_OFFSET = 0x1234
        ctrl_val = driver.axi_read(CPU_MEM_CTRL_OFFSET)
        print(f"  CPU_MEM_CTRL (0x{CPU_MEM_CTRL_OFFSET:04x}) = 0x{ctrl_val:08x}")
        print(f"    halted = {bool(ctrl_val & 0x200)}")
        print(f"    running = {bool(ctrl_val & 0x100)}")
    except Exception as e:
        print(f"  ERROR reading CPU_MEM_CTRL: {e}")
