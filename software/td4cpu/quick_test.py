#!/usr/bin/env python3
"""Quick single ADD test to verify execution"""
import sys
sys.path.insert(0, '..')
from axiuart_driver import axiuart_driver
import axiuart_driver.registers as registers
import time

driver = axiuart_driver.AXIUARTDriver('COM3', 115200)
driver.open()

print("=== Quick ADD Test (1+2=3) ===\n")

# Halt CPU
print("1. Halting CPU...")
driver.write_reg32(registers.REG_CPU_DBG_CTRL, 0x01)
time.sleep(0.01)

# Clear all registers
print("2. Clearing registers...")
for i in range(8):
    driver.write_reg32(registers.REG_CPU_REG_INDEX, i)
    time.sleep(0.005)
    driver.write_reg32(registers.REG_CPU_REG_DATA, 0x0000)
    time.sleep(0.005)

# Setup R1=1, R2=2
print("3. Setting R1=1, R2=2...")
driver.write_reg32(registers.REG_CPU_REG_INDEX, 1)
time.sleep(0.005)
driver.write_reg32(registers.REG_CPU_REG_DATA, 0x0001)
time.sleep(0.005)

driver.write_reg32(registers.REG_CPU_REG_INDEX, 2)
time.sleep(0.005)
driver.write_reg32(registers.REG_CPU_REG_DATA, 0x0002)
time.sleep(0.005)

# Verify setup
driver.write_reg32(registers.REG_CPU_REG_INDEX, 1)
time.sleep(0.005)
r1_before = driver.read_reg32(registers.REG_CPU_REG_DATA) & 0xFFFF
driver.write_reg32(registers.REG_CPU_REG_INDEX, 2)
time.sleep(0.005)
r2_before = driver.read_reg32(registers.REG_CPU_REG_DATA) & 0xFFFF
print(f"   R1 = 0x{r1_before:04X}, R2 = 0x{r2_before:04X}")

# Load instruction ADD R1, R1, R2 (0x0280)
print("4. Loading instruction 0x0280 (ADD R1,R1,R2)...")
driver.write_reg32(registers.REG_CPU_MEM_ADDR, 0x0000)
driver.write_reg32(registers.REG_CPU_MEM_WDATA, 0x0280)
driver.write_reg32(registers.REG_CPU_MEM_CTRL, 0x00000002)  # Write bit
time.sleep(0.001)

# Set PC=0
print("5. Setting PC=0...")
driver.write_reg32(registers.REG_CPU_PC, 0x0000)

# Execute one step
print("6. Executing STEP...")
driver.write_reg32(registers.REG_CPU_DBG_CTRL, 0x00000004)  # Step bit
time.sleep(0.05)

# Read results
print("7. Reading results...")
driver.write_reg32(registers.REG_CPU_REG_INDEX, 1)
time.sleep(0.005)
r1_after = driver.read_reg32(registers.REG_CPU_REG_DATA) & 0xFFFF

flags = driver.read_reg32(registers.REG_CPU_FLAGS) & 0x07
pc = driver.read_reg32(registers.REG_CPU_PC) & 0xFFFF

print(f"   R1 = 0x{r1_after:04X} (expected 0x0003)")
print(f"   FLAGS = 0x{flags:02X}")
print(f"   PC = 0x{pc:04X}")

if r1_after == 0x0003:
    print("\n✓ TEST PASSED")
else:
    print(f"\n✗ TEST FAILED: Expected R1=0x0003, got R1=0x{r1_after:04X}")

driver.close()
