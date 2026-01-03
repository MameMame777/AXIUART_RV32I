#!/usr/bin/env python3
"""Quick CPU halt utility"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from axiuart_driver import AXIUARTDriver

CPU_HALT = (1 << 8)
CPU_HALTED = (1 << 9)

drv = AXIUARTDriver(port='COM3', baudrate=115200)
drv.open()

print("Halting CPU...")
drv.write_reg32(drv.REG_CPU_MEM_CTRL, CPU_HALT)
time.sleep(0.1)

ctrl = drv.read_reg32(drv.REG_CPU_MEM_CTRL)
if ctrl & CPU_HALTED:
    print(f"[OK] CPU halted (CTRL=0x{ctrl:08X})")
else:
    print(f"[WARN] Status unclear (CTRL=0x{ctrl:08X})")

drv.close()
