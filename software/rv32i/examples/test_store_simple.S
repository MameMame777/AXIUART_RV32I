# Simple STORE instruction test
# Tests basic STORE operations without complexity

.section .text
.globl _start

_start:
    # Initialize test values
    li   x10, 0x12345678    # Test data
    li   x11, 0x00000400    # Data address (start of data RAM)
    
    # Test 1: Simple word store
    sw   x10, 0(x11)        # Store to 0x400
    
    # Test 2: Store with offset
    li   x12, 0xAABBCCDD
    sw   x12, 4(x11)        # Store to 0x404
    
    # Test 3: Store with different register
    li   x13, 0x11223344
    li   x14, 0x00000408
    sw   x13, 0(x14)        # Store to 0x408
    
    # Test 4: Halfword store
    li   x15, 0x0000BEEF
    sh   x15, 12(x11)       # Store halfword to 0x40C
    
    # Test 5: Byte store
    li   x16, 0x000000AA
    sb   x16, 14(x11)       # Store byte to 0x40E
    
    # Signal success via LED
    li   x20, 0x00000008    # Success pattern
    li   x21, 0x00001000    # LED MMIO address
    sw   x20, 0(x21)        # Write to LED
    
    # Exit with EBREAK
    ebreak

.section .data
# Data section not used in this test
