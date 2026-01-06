#!/usr/bin/env python3
"""
Check FPGA Reset Status
Reads CPU status to determine if CPU is stuck in reset
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

port = sys.argv[1] if len(sys.argv) > 1 else 'COM3'

print("="*60)
print("FPGA Reset Status Check")
print("="*60)

with AXIUARTDriver(port, 115200) as driver:
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
    from rv32i import get_cpu_status, halt_cpu, run_cpu
    
    print("\n[TEST 1] Check initial CPU status")
    status = get_cpu_status(driver)
    print(f"  CPU Status:")
    print(f"    halted = {status['halted']}")
    print(f"    break  = {status['break']}")
    print(f"    busy   = {status['busy']}")
    
    if not status['halted'] and not status['break']:
        print("  ⚠ CPU is running - may be stuck or executing unknown code")
    
    print("\n[TEST 2] Try to halt CPU")
    try:
        halt_cpu(driver, timeout=2.0)
        print("  ✓ CPU halted successfully")
    except TimeoutError:
        print("  ✗ CPU FAILED to halt within 2 seconds!")
        print("  → This suggests CPU is stuck in RESET")
        print("  → Check if RESET BUTTON is pressed or stuck")
        print()
        print("SOLUTION:")
        print("  1. Check the FPGA board's RESET button")
        print("  2. Make sure it is NOT pressed/stuck")
        print("  3. Press and RELEASE the reset button once")
        print("  4. Run this script again")
        sys.exit(1)
    
    status = get_cpu_status(driver)
    print(f"  After halt: halted={status['halted']}")
    
    print("\n[TEST 3] Try to run CPU")
    run_cpu(driver)
    import time
    time.sleep(0.1)
    status = get_cpu_status(driver)
    print(f"  After run: halted={status['halted']}")
    
    if status['halted']:
        print("  ✗ CPU still halted after RUN command!")
        print("  → CPU is likely held in RESET by hardware button")
    else:
        print("  ✓ CPU can transition between HALT and RUN states")
        print("  → CPU control is working correctly")
    
    print("\n[TEST 4] Halt CPU again")
    halt_cpu(driver)
    status = get_cpu_status(driver)
    print(f"  Final status: halted={status['halted']}")

print("\n" + "="*60)
print("DIAGNOSIS:")
print("="*60)
print()
print("If CPU cannot halt:")
print("  → RESET button is pressed or stuck")
print("  → Release the reset button and try again")
print()
print("If CPU works correctly:")
print("  → The issue is elsewhere (program execution, LED wiring, etc.)")
print("="*60)
