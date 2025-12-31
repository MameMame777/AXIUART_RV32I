#!/usr/bin/env python3
"""
TD4 CPU Instruction Simulator
Simulates TD4 CPU instruction execution for debugging
"""

class TD4Simulator:
    """Simulates TD4 CPU instruction execution"""
    
    # Opcodes (4-bit, bits [15:12])
    OP_R_ALU = 0x0  # R-type ALU
    OP_LDI   = 0x1  # Load Immediate
    OP_ADDI  = 0x2  # Add Immediate  
    OP_LD    = 0x3  # Load from memory
    OP_ST    = 0x4  # Store to memory
    OP_BR    = 0x5  # Branch
    OP_SYS   = 0x6  # System (BRK)
    OP_STACK = 0x7  # Stack operations
    
    def __init__(self):
        self.regfile = [0] * 8  # 8 registers
        self.pc = 0
        self.ram = {}  # Sparse memory
        self.led_reg = 0
        self.flags = {'Z': False, 'N': False, 'C': False}
        
    def reset(self):
        """Reset CPU state"""
        self.regfile = [0] * 8
        self.pc = 0
        self.led_reg = 0
        self.flags = {'Z': False, 'N': False, 'C': False}
        
    def load_instruction(self, addr, insn):
        """Load instruction into memory"""
        self.ram[addr] = insn
        
    def sign_extend_9bit(self, value):
        """Sign extend 9-bit value to 16-bit"""
        if value & 0x100:  # Bit 8 is set (negative)
            return value | 0xFE00  # Sign extend
        return value
        
    def sign_extend_6bit(self, value):
        """Sign extend 6-bit value to 16-bit"""
        if value & 0x20:  # Bit 5 is set (negative)
            return value | 0xFFC0  # Sign extend
        return value
        
    def execute_ldi(self, rd, imm9):
        """Execute LDI Rd, #imm9"""
        value = self.sign_extend_9bit(imm9)
        self.regfile[rd] = value & 0xFFFF
        print(f"  LDI R{rd}, #0x{imm9:03X} (signed: {value & 0xFFFF:04X}) -> R{rd}=0x{self.regfile[rd]:04X}")
        
    def execute_addi(self, rd, imm9):
        """Execute ADDI Rd, #imm9"""
        imm_signed = self.sign_extend_9bit(imm9)
        imm_actual = imm_signed if imm_signed >= 0 else (imm_signed + 0x10000)
        old_value = self.regfile[rd]
        result = (old_value + imm_signed) & 0xFFFF
        self.regfile[rd] = result
        sign_str = f"+{imm_signed}" if imm_signed >= 0 else f"{imm_signed}"
        print(f"  ADDI R{rd}, #0x{imm9:03X} (decimal: {sign_str}): 0x{old_value:04X} -> 0x{result:04X}")
        
    def execute_ld(self, rd, rb, offset6):
        """Execute LD Rd, [Rb + offset6]"""
        offset_signed = self.sign_extend_6bit(offset6)
        addr = (self.regfile[rb] + offset_signed) & 0xFFFF
        
        if addr == 0x101F:  # LED MMIO
            value = self.led_reg & 0xF
            print(f"  LD R{rd}, [R{rb}+{offset_signed}]: addr=0x{addr:04X} (LED MMIO) -> R{rd}=0x{value:04X}")
        elif addr in self.ram:
            value = self.ram[addr]
            print(f"  LD R{rd}, [R{rb}+{offset_signed}]: addr=0x{addr:04X} (RAM) -> R{rd}=0x{value:04X}")
        else:
            value = 0
            print(f"  LD R{rd}, [R{rb}+{offset_signed}]: addr=0x{addr:04X} (uninitialized) -> R{rd}=0x0000")
            
        self.regfile[rd] = value & 0xFFFF
        
    def execute_st(self, rd, rb, offset6):
        """Execute ST Rd, [Rb + offset6]"""
        offset_signed = self.sign_extend_6bit(offset6)
        addr = (self.regfile[rb] + offset_signed) & 0xFFFF
        value = self.regfile[rd]
        
        if addr == 0x101F:  # LED MMIO
            self.led_reg = value & 0xF
            print(f"  ST R{rd}, [R{rb}+{offset_signed}]: addr=0x{addr:04X} (LED MMIO) <- 0x{value:04X} (LED=0x{self.led_reg:X})")
        else:
            self.ram[addr] = value
            print(f"  ST R{rd}, [R{rb}+{offset_signed}]: addr=0x{addr:04X} (RAM) <- 0x{value:04X}")
            
    def execute(self, insn):
        """Execute single instruction"""
        opcode = (insn >> 12) & 0xF  # 4-bit opcode
        
        if opcode == self.OP_LDI:
            rd = (insn >> 9) & 0x7  # bits [11:9]
            imm9 = insn & 0x1FF     # bits [8:0]
            self.execute_ldi(rd, imm9)
            
        elif opcode == self.OP_ADDI:
            rd = (insn >> 9) & 0x7  # bits [11:9]
            imm9 = insn & 0x1FF     # bits [8:0]
            self.execute_addi(rd, imm9)
            
        elif opcode == self.OP_LD:
            rd = (insn >> 9) & 0x7   # bits [11:9]
            rb = (insn >> 6) & 0x7   # bits [8:6]
            offset6 = insn & 0x3F    # bits [5:0]
            self.execute_ld(rd, rb, offset6)
            
        elif opcode == self.OP_ST:
            rd = (insn >> 9) & 0x7   # bits [11:9]
            rb = (insn >> 6) & 0x7   # bits [8:6]
            offset6 = insn & 0x3F    # bits [5:0]
            self.execute_st(rd, rb, offset6)
            
        elif opcode == self.OP_SYS:
            syscall = insn & 0x7  # 3-bit syscall
            if syscall == 0:  # BRK
                print(f"  SYS BRK - Halting")
                return False
                
        return True
        
    def run_program(self, start_pc, max_steps=1000):
        """Run program from start_pc"""
        self.pc = start_pc
        step = 0
        
        print(f"\n=== Starting execution from PC=0x{start_pc:04X} ===")
        
        while step < max_steps:
            if self.pc not in self.ram:
                print(f"\n[Step {step}] PC=0x{self.pc:04X} - No instruction (HALT)")
                break
                
            insn = self.ram[self.pc]
            print(f"\n[Step {step}] PC=0x{self.pc:04X}: insn=0x{insn:04X}")
            
            if not self.execute(insn):
                break
                
            self.pc += 1
            step += 1
            
        print(f"\n=== Execution completed after {step} steps ===")
        self.print_state()
        
    def print_state(self):
        """Print CPU state"""
        print("\nRegister File:")
        for i in range(8):
            print(f"  R{i} = 0x{self.regfile[i]:04X} ({self.regfile[i]})")
        print(f"\nLED Register: 0x{self.led_reg:X}")
        print(f"PC: 0x{self.pc:04X}")


def test_case_1():
    """Test Case 1: Basic ST to LED MMIO with 31 ADDI iterations"""
    sim = TD4Simulator()
    
    print("\n" + "="*70)
    print("TEST CASE 1: Basic ST to LED MMIO")
    print("="*70)
    
    # Build instruction sequence
    # Goal: R1 = 0x80 + 31*0x80 + 0x1F = 128 + 3968 + 31 = 4127 = 0x101F
    
    addr = 0x0000
    
    # Load test data into R0
    sim.load_instruction(addr, (sim.OP_LDI << 12) | (0 << 9) | 0x00A)  # LDI R0, #0xA
    print(f"[0x{addr:04X}] LDI R0, #0x00A")
    addr += 1
    
    # Initialize R1 with base value
    sim.load_instruction(addr, (sim.OP_LDI << 12) | (1 << 9) | 0x080)  # LDI R1, #0x80
    print(f"[0x{addr:04X}] LDI R1, #0x080 (128 decimal)")
    addr += 1
    
    # Add 31 times ADDI R1, #0x80
    for i in range(31):
        sim.load_instruction(addr, (sim.OP_ADDI << 12) | (1 << 9) | 0x080)  # ADDI R1, #0x80
        if i < 3 or i >= 28:  # Print first 3 and last 3
            print(f"[0x{addr:04X}] ADDI R1, #0x080")
        elif i == 3:
            print(f"  ... (25 more ADDI instructions) ...")
        addr += 1
    
    # Final adjustment
    sim.load_instruction(addr, (sim.OP_ADDI << 12) | (1 << 9) | 0x01F)  # ADDI R1, #0x1F
    print(f"[0x{addr:04X}] ADDI R1, #0x01F (31 decimal)")
    addr += 1
    
    # Store to LED
    sim.load_instruction(addr, (sim.OP_ST << 12) | (0 << 9) | (1 << 6) | 0x00)  # ST R0, [R1+0]
    print(f"[0x{addr:04X}] ST R0, [R1+0]")
    addr += 1
    
    # Break
    sim.load_instruction(addr, (sim.OP_SYS << 12) | 0)  # SYS BRK
    print(f"[0x{addr:04X}] SYS BRK")
    
    # Expected calculation
    print("\n" + "-"*70)
    print("Expected Address Calculation:")
    print(f"  Initial:        0x080 = {0x080} (128 decimal)")
    print(f"  After 31 ADDI:  + 31 * 128 = {31 * 128} (0x{31*128:X})")
    print(f"  Subtotal:       = {128 + 31*128} (0x{128 + 31*128:X})")
    print(f"  Final ADDI:     + 0x01F = {0x1F} (31 decimal)")
    print(f"  Final Address:  = {128 + 31*128 + 31} (0x{128 + 31*128 + 31:X})")
    print(f"  Target LED:     0x101F")
    print(f"  Match: {128 + 31*128 + 31 == 0x101F}")
    print("-"*70)
    
    # Run simulation
    sim.run_program(start_pc=0x0000)
    
    # Verify
    expected_addr = 0x101F
    actual_addr = sim.regfile[1]
    expected_led = 0xA
    actual_led = sim.led_reg
    
    print("\n" + "="*70)
    print("VERIFICATION:")
    print(f"  Expected R1 (address): 0x{expected_addr:04X}")
    print(f"  Actual R1:             0x{actual_addr:04X} {'✓' if actual_addr == expected_addr else '✗'}")
    print(f"  Expected LED:          0x{expected_led:X}")
    print(f"  Actual LED:            0x{actual_led:X} {'✓' if actual_led == expected_led else '✗'}")
    print("="*70)
    
    return actual_addr == expected_addr and actual_led == expected_led


if __name__ == "__main__":
    success = test_case_1()
    print(f"\nTest Result: {'PASS ✓' if success else 'FAIL ✗'}")
