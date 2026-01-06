#!/usr/bin/env python3
"""Quick CPU execution test"""
import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

port = sys.argv[1] if len(sys.argv) > 1 else 'COM3'

with AXIUARTDriver(port, 115200) as driver:
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
    from rv32i import halt_cpu, run_cpu, get_cpu_status
    from rv32i.memory import write_cpu_mem, read_cpu_mem
    from rv32i.encoder import RV32IInstructionEncoder
    
    enc = RV32IInstructionEncoder()
    
    print("Halting CPU...")
    halt_cpu(driver)
    
    # Simple: Write value to memory and EBREAK
    program = [
        enc.lui(1, 0x1),         # x1 = 0x1000
        enc.addi(2, 0, 0x42),    # x2 = 0x42
        enc.sw(2, 1, 0),         # MEM[0x1000] = 0x42
        enc.ebreak()             # Stop
    ]
    
    print("Loading program...")
    for i, insn in enumerate(program):
        write_cpu_mem(driver, i * 4, insn)
    
    # Clear target
    write_cpu_mem(driver, 0x1000, 0x0)
    print(f"Before: 0x1000 = 0x{read_cpu_mem(driver, 0x1000):08x}")
    
    print("Starting CPU...")
    run_cpu(driver)
    time.sleep(0.5)
    
    result = read_cpu_mem(driver, 0x1000)
    status = get_cpu_status(driver)
    
    print(f"After: 0x1000 = 0x{result:08x}")
    print(f"Status: halted={status['halted']}, break={status['break']}")
    
    if result == 0x42:
        print("✓ CPU EXECUTED! Memory was written!")
        if status['break']:
            print("✓ EBREAK works!")
        else:
            print("✗ EBREAK does NOT work")
    else:
        print("✗ CPU did NOT execute - memory unchanged")
