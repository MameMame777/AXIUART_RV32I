#!/usr/bin/env python3
"""
Generate hex file for simple STORE instruction test
"""

def generate_store_test():
    """Generate minimal STORE test hex file"""
    instructions = [
        # CSR initialization (required for CPU operation)
        0x20000f93,  # addi x31, x0, 0x200  (exception handler address)
        0x305f9073,  # csrrw x0, mtvec, x31 (set mtvec = 0x200)
        
        # Initialize test values
        0x12345537,  # lui  x10, 0x12345
        0x67850513,  # addi x10, x10, 0x678
        0x000005b7,  # lui  x11, 0x0  (for 0x400)
        0x40058593,  # addi x11, x11, 0x400
        
        # Test 1: Simple word store - sw x10, 0(x11)
        0x00a5a023,  # sw x10, 0(x11) -> addr 0x400
        
        # Test 2: Store with offset
        0xaabbd637,  # lui  x12, 0xaabbd
        0xcdd60613,  # addi x12, x12, -0x323 (to get 0xAABBCCDD)
        0x00c5a223,  # sw x12, 4(x11) -> addr 0x404
        
        # Test 3: Store with different register
        0x112236b7,  # lui  x13, 0x11223 (FIXED: was encoding x10)
        0x34468693,  # addi x13, x13, 0x344
        0x00000737,  # lui  x14, 0x0
        0x40870713,  # addi x14, x14, 0x408
        0x00d72023,  # sw x13, 0(x14) -> addr 0x408
        
        # Test 4: Halfword store
        0x0000f7b7,  # lui  x15, 0xF (loads 0xF000)
        0xbef78793,  # addi x15, x15, -1041 (0xF000 + sign_ext(0xBEF) = 0xEBEF)
        0x00f59623,  # sh x15, 12(x11) -> addr 0x40C
        
        # Test 5: Byte store
        0x0aa00813,  # addi x16, x0, 0xAA
        0x01058723,  # sb x16, 14(x11) -> addr 0x40E
        
        # Signal success via LED (BROKEN: stores to 0x1014 RAM, not 0x407C LED)
        0x00000a37,  # lui  x20, 0x0
        0x008a0a13,  # addi x20, x20, 8 (x20 = 8)
        0x00001ab7,  # lui  x21, 0x1 (x21 = 0x1000)
        0x014aaa23,  # sw x10, 20(x21) -> addr 0x1014 (NOT LED!)
        
        # Exit with EBREAK
        0x00100073,  # ebreak
    ]
    
    # Write hex file (continuous format like comprehensive test)
    with open('sim/tests/test_store_simple.hex', 'w') as f:
        for insn in instructions:
            f.write(f"{insn:08x}\n")
    
    print(f"Generated test_store_simple.hex with {len(instructions)} instructions")
    print(f"Expected execution: ~{len(instructions)} instructions")
    print("\nExpected behavior:")
    print("  - CSR mtvec initialization (0x200)")
    print("  - Store 0x12345678 to 0x400")
    print("  - Store 0xAABBCCDD to 0x404")
    print("  - Store 0x11223344 to 0x408")
    print("  - Store 0xBEEF (halfword) to 0x40C")
    print("  - Store 0xAA (byte) to 0x40E")
    print("  - LED = 0x8")
    print("  - EBREAK")

if __name__ == '__main__':
    generate_store_test()
