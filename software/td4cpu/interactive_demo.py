#!/usr/bin/env python3
"""
TD4 CPU Interactive Demo Tool
Provides interactive control of FPGA hardware for LED control and CPU demos
"""

import sys
import time
import argparse
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from axiuart_driver import AXIUARTDriver, registers
from td4cpu.isa import *

class InteractiveDemo:
    def __init__(self, port: str, baudrate: int = 115200):
        self.port = port
        self.baudrate = baudrate
        self.driver = None
        
    def connect(self):
        """Connect to FPGA"""
        print(f"Connecting to {self.port} @ {self.baudrate} baud...")
        self.driver = AXIUARTDriver(self.port, baudrate=self.baudrate, timeout=2.0)
        self.driver.open()
        
        # Read version
        version = self.driver.read_reg32(registers.REG_VERSION)
        print(f"Hardware version: 0x{version:08X}")
        
    def disconnect(self):
        """Disconnect from FPGA"""
        if self.driver:
            self.driver.close()
            print("Disconnected.")
    
    def led_pattern(self, pattern: int):
        """Set LED pattern (0-15)"""
        if not (0 <= pattern <= 15):
            print(f"Error: Pattern must be 0-15")
            return
        self.driver.write_reg32(registers.REG_TEST_LED, pattern & 0x0F)
        print(f"LED pattern set to: {pattern:04b}")
    
    def led_chika(self, duration: float = 5.0, speed: float = 0.2):
        """LED Lチカ demo - cycling through patterns"""
        print(f"Running LED demo for {duration:.1f} seconds (speed={speed:.2f}s)...")
        print("Press Ctrl+C to stop early")
        
        start_time = time.time()
        pattern = 0
        
        try:
            while (time.time() - start_time) < duration:
                self.driver.write_reg32(registers.REG_TEST_LED, pattern)
                print(f"  LED: {pattern:04b} ({pattern})", end='\r')
                time.sleep(speed)
                pattern = (pattern + 1) % 16
            print()  # Newline after demo
            print("LED demo complete!")
        except KeyboardInterrupt:
            print("\nLED demo stopped by user")
    
    def led_binary_count(self, duration: float = 10.0):
        """Binary counter on LEDs"""
        print(f"Binary counter demo for {duration:.1f} seconds...")
        self.led_chika(duration=duration, speed=0.5)
    
    def led_chase(self, duration: float = 5.0):
        """Chase pattern on LEDs"""
        print(f"LED chase demo for {duration:.1f} seconds...")
        patterns = [0b0001, 0b0010, 0b0100, 0b1000, 0b0100, 0b0010]
        start_time = time.time()
        idx = 0
        
        try:
            while (time.time() - start_time) < duration:
                pattern = patterns[idx % len(patterns)]
                self.driver.write_reg32(registers.REG_TEST_LED, pattern)
                print(f"  LED: {pattern:04b}", end='\r')
                time.sleep(0.15)
                idx += 1
            print()
            print("LED chase complete!")
        except KeyboardInterrupt:
            print("\nLED chase stopped by user")
    
    def cpu_halt(self):
        """Halt CPU"""
        self.driver.write_reg32(registers.REG_CPU_DBG_CTRL, 0x00000001)
        time.sleep(0.01)
        status = self.driver.read_reg32(registers.REG_CPU_DBG_STATUS)
        print(f"CPU halted (status=0x{status:08X})")
    
    def cpu_status(self):
        """Display CPU status"""
        status = self.driver.read_reg32(registers.REG_CPU_DBG_STATUS)
        pc = self.driver.read_reg32(registers.REG_CPU_PC)
        sp = self.driver.read_reg32(registers.REG_CPU_SP)
        flags = self.driver.read_reg32(registers.REG_CPU_FLAGS)
        
        halted = (status >> 0) & 0x1
        running = (status >> 1) & 0x1
        halt_reason = (status >> 8) & 0xFF
        
        print("=" * 50)
        print("CPU Status:")
        print(f"  State:       {'HALTED' if halted else 'RUNNING'}")
        print(f"  PC:          0x{pc:04X}")
        print(f"  SP:          0x{sp:04X}")
        print(f"  Flags:       Z={flags>>2&1} N={flags>>1&1} C={flags&1}")
        print(f"  Halt Reason: 0x{halt_reason:02X}")
        print("=" * 50)
    
    def cpu_read_reg(self, reg_idx: int) -> int:
        """Read CPU register"""
        self.driver.write_reg32(registers.REG_CPU_REG_INDEX, reg_idx)
        return self.driver.read_reg32(registers.REG_CPU_REG_DATA) & 0xFFFF
    
    def cpu_write_reg(self, reg_idx: int, value: int):
        """Write CPU register"""
        self.driver.write_reg32(registers.REG_CPU_REG_INDEX, reg_idx)
        self.driver.write_reg32(registers.REG_CPU_REG_DATA, value & 0xFFFF)
        time.sleep(0.001)
    
    def cpu_show_registers(self):
        """Display all CPU registers"""
        print("CPU Registers:")
        for i in range(8):
            val = self.cpu_read_reg(i)
            print(f"  R{i} = 0x{val:04X} ({val:5d})")
    
    def cpu_load_memory(self, addr: int, data: int):
        """Load word into CPU memory"""
        self.driver.write_reg32(registers.REG_CPU_MEM_ADDR, addr)
        self.driver.write_reg32(registers.REG_CPU_MEM_WDATA, data & 0xFFFF)
        self.driver.write_reg32(registers.REG_CPU_MEM_CTRL, 0x00000002)  # WRITE
        time.sleep(0.001)
    
    def cpu_read_memory(self, addr: int) -> int:
        """Read word from CPU memory"""
        self.driver.write_reg32(registers.REG_CPU_MEM_ADDR, addr)
        self.driver.write_reg32(registers.REG_CPU_MEM_CTRL, 0x00000001)  # READ
        time.sleep(0.001)
        return self.driver.read_reg32(registers.REG_CPU_MEM_RDATA) & 0xFFFF
    
    def cpu_step(self):
        """Execute single instruction"""
        self.driver.write_reg32(registers.REG_CPU_DBG_CTRL, 0x00000004)  # STEP
        time.sleep(0.01)
    
    def trace_read_entry(self, index: int):
        """Read trace buffer entry"""
        self.driver.write_reg32(registers.REG_CPU_TRACE_ADDR, index & 0xFF)
        data = self.driver.read_reg32(registers.REG_CPU_TRACE_RDATA)
        insn = (data >> 16) & 0xFFFF
        result = data & 0xFFFF
        return insn, result
    
    def trace_show_recent(self, count: int = 10):
        """Show recent trace entries"""
        ptr = self.driver.read_reg32(registers.REG_CPU_TRACE_PTR)
        print(f"Trace buffer (pointer={ptr}, showing last {count} entries):")
        print("  Idx | Instruction | Result")
        print("  ----|-------------|--------")
        
        for i in range(count):
            idx = (ptr - count + i) % 256
            insn, result = self.trace_read_entry(idx)
            print(f"  {idx:3d} | 0x{insn:04X}      | 0x{result:04X}")
    
    def demo_fibonacci(self, n: int = 10):
        """Run Fibonacci sequence demo on CPU"""
        print(f"=" * 60)
        print(f"Fibonacci Demo: Computing first {n} numbers")
        print(f"=" * 60)
        
        # Halt CPU
        self.cpu_halt()
        
        # Program:
        # R0 = current fib number
        # R1 = previous fib number
        # R2 = temp for addition
        # R3 = counter
        
        program = [
            # addr 0: Initialize
            0x1001,  # LDI R0, 1      ; fib(1) = 1
            0x1081,  # LDI R1, 1      ; fib(0) = 1
            (n << 9) | 0x01A1,  # LDI R3, n     ; counter
            
            # addr 3: Loop
            0x0100,  # ADD R2, R0, R1 ; R2 = R0 + R1
            0x0208,  # MOV R1, R0     ; R1 = R0 (previous)
            0x0008,  # MOV R0, R2     ; R0 = R2 (current)
            
            # Decrement counter and loop
            0x25E3,  # ADDI R3, -2    ; R3 -= 2 (signed)
            0x5018,  # BR NZ, -8      ; if R3 != 0, goto addr 3
            
            # End: R0 contains result
            0x6001,  # BRK
        ]
        
        # Load program
        print("Loading Fibonacci program...")
        for i, insn in enumerate(program):
            self.cpu_load_memory(i, insn)
        
        # Setup
        self.driver.write_reg32(registers.REG_CPU_PC, 0x0000)
        self.driver.write_reg32(registers.REG_CPU_TRACE_CTRL, 0x00000001)  # Enable trace
        
        # Execute step by step
        print("Executing...")
        for step in range(min(n * 5, 50)):  # Safety limit
            self.cpu_step()
            status = self.driver.read_reg32(registers.REG_CPU_DBG_STATUS)
            if (status >> 3) & 0x1:  # BRK hit
                break
        
        # Show results
        print("\nResults:")
        self.cpu_show_registers()
        
        r0 = self.cpu_read_reg(0)
        print(f"\nFibonacci({n}) = {r0}")
        
    def demo_counter(self, duration: float = 10.0):
        """Run simple counter demo that displays on LEDs"""
        print(f"=" * 60)
        print(f"Counter Demo: CPU-driven LED counter for {duration:.1f}s")
        print(f"=" * 60)
        
        self.cpu_halt()
        
        # Simple program: increment R0, mask to 4 bits, write to LED
        # (This is conceptual - actual LED control would need memory-mapped IO)
        # For now, we'll do it in software
        
        print("Running counter...")
        start_time = time.time()
        counter = 0
        
        try:
            while (time.time() - start_time) < duration:
                self.driver.write_reg32(registers.REG_TEST_LED, counter & 0x0F)
                print(f"  Counter: {counter:4d} | LED: {counter&0x0F:04b}", end='\r')
                counter += 1
                time.sleep(0.1)
        except KeyboardInterrupt:
            print("\nCounter stopped by user")
        
        print("\nCounter demo complete!")
        self.driver.write_reg32(registers.REG_TEST_LED, 0x0)
    
    def demo_simple_alu(self):
        """Simple ALU demonstration"""
        print(f"=" * 60)
        print("Simple ALU Demo")
        print(f"=" * 60)
        
        self.cpu_halt()
        
        tests = [
            ("ADD", 5, 3, OP_R_ALU << 12 | 1 << 9 | 2 << 6 | FUNCT_ADD, 8),
            ("SUB", 10, 3, OP_R_ALU << 12 | 1 << 9 | 2 << 6 | FUNCT_SUB, 7),
            ("AND", 0xFF, 0x0F, OP_R_ALU << 12 | 1 << 9 | 2 << 6 | FUNCT_AND, 0x0F),
            ("OR", 0xF0, 0x0F, OP_R_ALU << 12 | 1 << 9 | 2 << 6 | FUNCT_OR, 0xFF),
        ]
        
        for name, a, b, insn, expected in tests:
            # Load instruction
            self.cpu_load_memory(0, insn)
            
            # Setup registers
            self.cpu_write_reg(1, a)
            self.cpu_write_reg(2, b)
            
            # Execute
            self.driver.write_reg32(registers.REG_CPU_PC, 0)
            self.cpu_step()
            
            # Read result
            result = self.cpu_read_reg(1)
            
            status = "✓" if result == expected else "✗"
            print(f"  {status} {name:4s}: {a} op {b} = {result} (expected {expected})")
        
        print("\nALU demo complete!")
    
    def interactive_menu(self):
        """Interactive menu system"""
        while True:
            print("\n" + "=" * 60)
            print("TD4 CPU Interactive Demo")
            print("=" * 60)
            print("LED Demos:")
            print("  1) LED Lチカ (binary counter)")
            print("  2) LED Chase pattern")
            print("  3) Set LED pattern manually")
            print("\nCPU Demos:")
            print("  4) Simple ALU operations")
            print("  5) Fibonacci sequence")
            print("  6) CPU-driven counter")
            print("\nInfo:")
            print("  7) Show CPU status")
            print("  8) Show CPU registers")
            print("  9) Show trace buffer")
            print("\nControl:")
            print("  h) Halt CPU")
            print("  s) Single step")
            print("  q) Quit")
            print("=" * 60)
            
            choice = input("Select option: ").strip().lower()
            
            try:
                if choice == '1':
                    self.led_binary_count(duration=10.0)
                elif choice == '2':
                    self.led_chase(duration=8.0)
                elif choice == '3':
                    pattern = int(input("Enter LED pattern (0-15): "))
                    self.led_pattern(pattern)
                elif choice == '4':
                    self.demo_simple_alu()
                elif choice == '5':
                    n = int(input("Enter n for Fibonacci (1-20): "))
                    self.demo_fibonacci(n)
                elif choice == '6':
                    self.demo_counter(duration=10.0)
                elif choice == '7':
                    self.cpu_status()
                elif choice == '8':
                    self.cpu_show_registers()
                elif choice == '9':
                    count = int(input("Number of entries to show (1-50): "))
                    self.trace_show_recent(min(count, 50))
                elif choice == 'h':
                    self.cpu_halt()
                elif choice == 's':
                    self.cpu_step()
                    print("Stepped one instruction")
                    self.cpu_status()
                elif choice == 'q':
                    print("Exiting...")
                    break
                else:
                    print(f"Unknown option: {choice}")
            except KeyboardInterrupt:
                print("\nOperation cancelled")
            except Exception as e:
                print(f"Error: {e}")


def main():
    parser = argparse.ArgumentParser(description='TD4 CPU Interactive Demo Tool')
    parser.add_argument('--port', default='COM3', help='Serial port (default: COM3)')
    parser.add_argument('--baudrate', type=int, default=115200, help='Baud rate (default: 115200)')
    parser.add_argument('--demo', choices=['led', 'alu', 'fib', 'counter'], 
                       help='Run specific demo and exit')
    
    args = parser.parse_args()
    
    demo = InteractiveDemo(args.port, args.baudrate)
    
    try:
        demo.connect()
        
        if args.demo:
            # Run specific demo
            if args.demo == 'led':
                demo.led_binary_count(duration=10.0)
            elif args.demo == 'alu':
                demo.demo_simple_alu()
            elif args.demo == 'fib':
                demo.demo_fibonacci(10)
            elif args.demo == 'counter':
                demo.demo_counter(duration=10.0)
        else:
            # Interactive menu
            demo.interactive_menu()
            
    except KeyboardInterrupt:
        print("\nInterrupted by user")
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        demo.disconnect()


if __name__ == "__main__":
    main()
