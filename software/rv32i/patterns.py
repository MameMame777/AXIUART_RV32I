"""RV32I LED Pattern Generators

Pre-built LED animation patterns using RV32I instructions.
Depends on: encoder.py

Each generator returns a list of 32-bit encoded instructions
that can be written to CPU memory and executed.

LED MMIO address (CPU perspective): 0x407C
(Last word in 8KB RAM space: 0x0000-0x1FFF)

Usage:
    from rv32i import RV32IInstructionEncoder, generate_led_blink
    from rv32i import halt_cpu, run_cpu, write_program
    from axiuart_driver import AXIUARTDriver
    
    with AXIUARTDriver('/dev/ttyUSB0', 115200) as driver:
        program = generate_led_blink(0x5, 0xA, 10000000)
        halt_cpu(driver)
        write_program(driver, program)
        run_cpu(driver)
"""

try:
    from .encoder import RV32IInstructionEncoder
except ImportError:
    from encoder import RV32IInstructionEncoder


# LED MMIO address (CPU memory space)
LED_ADDR = 0x407C  # Last word in 8KB RAM


def generate_led_simple(value1=0x5, value2=0xA):
    """
    Generate simple LED toggle pattern (no loop).
    
    Program flow:
    1. Load LED base address (0x4000)
    2. Write value1 to LED
    3. Write value2 to LED
    4. EBREAK
    
    Args:
        value1: First LED pattern (default: 0x5 = 0b0101)
        value2: Second LED pattern (default: 0xA = 0b1010)
    
    Returns:
        List of encoded instructions
    """
    enc = RV32IInstructionEncoder()
    
    # x15 = LED base (0x4000), x16 = offset (0x7C)
    # x17 = value1, x18 = value2
    return [
        enc.lui(15, 0x4),           # x15 = 0x4000
        enc.addi(16, 0, 0x7C),      # x16 = 0x7C (LED offset)
        enc.add(16, 15, 16),        # x16 = x15 + x16 = 0x407C
        enc.addi(17, 0, value1),    # x17 = value1
        enc.sw(17, 16, 0),          # MEM[x16] = x17 (write LED)
        enc.addi(18, 0, value2),    # x18 = value2
        enc.sw(18, 16, 0),          # MEM[x16] = x18 (write LED)
        enc.ebreak()                # Stop
    ]


def generate_led_blink(value1=0x5, value2=0xA, delay_cycles=10000000):
    """
    Generate blinking LED pattern with delay loop.
    
    Program flow:
    1. Setup LED address in x15 (0x407C)
    2. Loop:
       a. Write value1 to LED
       b. Delay loop (delay_cycles iterations)
       c. Write value2 to LED
       d. Delay loop
       e. Jump back to loop start
    
    Args:
        value1: First LED pattern (default: 0x5)
        value2: Second LED pattern (default: 0xA)
        delay_cycles: Number of loop iterations for delay
    
    Returns:
        List of encoded instructions
    """
    enc = RV32IInstructionEncoder()
    
    # Register allocation:
    # x10 = LED address (0x407C)
    # x11 = value1
    # x12 = value2
    # x13 = delay counter
    # x14 = delay constant
    
    instructions = []
    
    # Setup: Load LED address
    instructions.append(enc.lui(10, 0x4))           # x10 = 0x4000
    instructions.append(enc.addi(10, 10, 0x7C))     # x10 = 0x407C
    
    # Load values
    instructions.append(enc.addi(11, 0, value1))    # x11 = value1
    instructions.append(enc.addi(12, 0, value2))    # x12 = value2
    
    # Load delay constant (split into upper/lower)
    delay_upper = (delay_cycles >> 12) & 0xFFFFF
    delay_lower = delay_cycles & 0xFFF
    instructions.append(enc.lui(14, delay_upper))   # x14 = delay_upper << 12
    instructions.append(enc.addi(14, 14, delay_lower))  # x14 += delay_lower
    
    # LOOP_START (PC = 6*4 = 24 bytes)
    loop_start_pc = len(instructions) * 4
    
    # Write value1
    instructions.append(enc.sw(11, 10, 0))          # MEM[x10] = x11
    
    # Delay loop 1
    instructions.append(enc.addi(13, 14, 0))        # x13 = x14 (reset counter)
    delay1_pc = len(instructions) * 4
    instructions.append(enc.addi(13, 13, -1))       # x13 -= 1
    instructions.append(enc.bne(13, 0, -4))         # if x13 != 0, jump back
    
    # Write value2
    instructions.append(enc.sw(12, 10, 0))          # MEM[x10] = x12
    
    # Delay loop 2
    instructions.append(enc.addi(13, 14, 0))        # x13 = x14 (reset counter)
    delay2_pc = len(instructions) * 4
    instructions.append(enc.addi(13, 13, -1))       # x13 -= 1
    instructions.append(enc.bne(13, 0, -4))         # if x13 != 0, jump back
    
    # Jump back to loop start
    current_pc = len(instructions) * 4
    offset = loop_start_pc - current_pc
    instructions.append(enc.jal(0, offset))         # Jump to loop start
    
    return instructions


def generate_led_count(start=0, end=15, delay_cycles=5000000):
    """
    Generate binary counter pattern (0→1→2→...→15→0).
    
    Args:
        start: Starting count value (default: 0)
        end: Ending count value (default: 15)
        delay_cycles: Delay between increments
    
    Returns:
        List of encoded instructions
    """
    enc = RV32IInstructionEncoder()
    
    # Register allocation:
    # x10 = LED address (0x407C)
    # x11 = current count
    # x12 = end value
    # x13 = delay counter
    # x14 = delay constant
    
    instructions = []
    
    # Setup: Load LED address
    instructions.append(enc.lui(10, 0x4))           # x10 = 0x4000
    instructions.append(enc.addi(10, 10, 0x7C))     # x10 = 0x407C
    
    # Load initial count and end value
    instructions.append(enc.addi(11, 0, start))     # x11 = start
    instructions.append(enc.addi(12, 0, end))       # x12 = end
    
    # Load delay constant
    delay_upper = (delay_cycles >> 12) & 0xFFFFF
    delay_lower = delay_cycles & 0xFFF
    instructions.append(enc.lui(14, delay_upper))   # x14 = delay_upper << 12
    instructions.append(enc.addi(14, 14, delay_lower))  # x14 += delay_lower
    
    # COUNT_LOOP (PC = 6*4 = 24 bytes)
    count_loop_pc = len(instructions) * 4
    
    # Write current count to LED
    instructions.append(enc.sw(11, 10, 0))          # MEM[x10] = x11
    
    # Delay loop
    instructions.append(enc.addi(13, 14, 0))        # x13 = x14 (reset counter)
    delay_loop_pc = len(instructions) * 4
    instructions.append(enc.addi(13, 13, -1))       # x13 -= 1
    instructions.append(enc.bne(13, 0, -4))         # if x13 != 0, jump back
    
    # Increment count
    instructions.append(enc.addi(11, 11, 1))        # x11 += 1
    
    # Check if reached end
    instructions.append(enc.blt(11, 12, 8))         # if x11 < x12, skip reset
    instructions.append(enc.addi(11, 0, start))     # x11 = start (reset)
    
    # Jump back to count loop
    current_pc = len(instructions) * 4
    offset = count_loop_pc - current_pc
    instructions.append(enc.jal(0, offset))         # Jump to count loop
    
    return instructions


def generate_led_knight_rider():
    """
    Generate knight rider shift pattern (1→2→4→8→1).
    
    Continuously shifts LED pattern left with wraparound.
    
    Returns:
        List of encoded instructions
    """
    enc = RV32IInstructionEncoder()
    
    # Register allocation:
    # x10 = LED address (0x407C)
    # x11 = current pattern
    # x12 = delay counter
    # x13 = delay constant
    
    delay_cycles = 5000000
    
    instructions = []
    
    # Setup: Load LED address
    instructions.append(enc.lui(10, 0x4))           # x10 = 0x4000
    instructions.append(enc.addi(10, 10, 0x7C))     # x10 = 0x407C
    
    # Load initial pattern (1)
    instructions.append(enc.addi(11, 0, 1))         # x11 = 1
    
    # Load delay constant
    delay_upper = (delay_cycles >> 12) & 0xFFFFF
    delay_lower = delay_cycles & 0xFFF
    instructions.append(enc.lui(13, delay_upper))   # x13 = delay_upper << 12
    instructions.append(enc.addi(13, 13, delay_lower))  # x13 += delay_lower
    
    # SHIFT_LOOP (PC = 5*4 = 20 bytes)
    shift_loop_pc = len(instructions) * 4
    
    # Write pattern to LED
    instructions.append(enc.sw(11, 10, 0))          # MEM[x10] = x11
    
    # Delay loop
    instructions.append(enc.addi(12, 13, 0))        # x12 = x13 (reset counter)
    delay_loop_pc = len(instructions) * 4
    instructions.append(enc.addi(12, 12, -1))       # x12 -= 1
    instructions.append(enc.bne(12, 0, -4))         # if x12 != 0, jump back
    
    # Shift left
    instructions.append(enc.slli(11, 11, 1))        # x11 <<= 1
    
    # Check if overflow (pattern > 8)
    instructions.append(enc.addi(15, 0, 8))         # x15 = 8
    instructions.append(enc.blt(11, 15, 8))         # if x11 <= 8, skip reset
    instructions.append(enc.addi(11, 0, 1))         # x11 = 1 (reset)
    
    # Jump back to shift loop
    current_pc = len(instructions) * 4
    offset = shift_loop_pc - current_pc
    instructions.append(enc.jal(0, offset))         # Jump to shift loop
    
    return instructions


def generate_led_complex_pattern(delay_cycles=5000000):
    """
    Generate complex multi-mode LED pattern program.
    
    Cycles through 4 distinct LED patterns automatically:
    - Mode 0: Binary counter (0→15)
    - Mode 1: Knight Rider scan (1→2→4→8→4→2→1)
    - Mode 2: Blink all LEDs (0xF ↔ 0x0)
    - Mode 3: Alternating pattern (0x5 ↔ 0xA)
    
    Each mode runs for approximately 2 seconds before transitioning.
    
    Args:
        delay_cycles: Number of cycles for each pattern iteration (default: 5M = 40ms @ 125MHz)
        fast_sim: If True, use minimal delays for simulation (1000 cycles = 8μs @ 125MHz)
    
    Register allocation:
        x1  : Current LED pattern value
        x2  : Mode counter (0-3)
        x3  : Inner delay counter (runtime)
        x4  : Outer delay counter (runtime)
        x5  : Large immediate holder (via LUI)
        x10 : Pattern iteration counter
        x11 : Pattern max/temp value
        x15 : LED base address (0x4000)
        x16 : LED full address (0x407C)
        x18 : Mode iteration counter (how many times pattern shown)
    
    Returns:
        List of RV32I instructions (approximately 100 instructions)
    """
    enc = RV32IInstructionEncoder()
    instructions = []
    
    # Override delay_cycles for fast simulation
    if fast_sim:
        delay_cycles = 1000  # 8μs @ 125MHz
    
    # ========== SETUP ==========
    # Initialize LED address
    instructions.append(enc.lui(15, 0x4))           # x15 = 0x4000
    instructions.append(enc.addi(16, 15, 0x7C))     # x16 = 0x407C (LED address)
    
    # Initialize mode counter
    instructions.append(enc.addi(2, 0, 0))          # x2 = 0 (start at mode 0)
    
    # Delay constants (outer and inner loop counts)
    if fast_sim:
        # Simple delay: just use x4 as counter (no nested loop)
        outer_count = delay_cycles
        instructions.append(enc.addi(5, 0, outer_count & 0x7FF))  # x5 = delay count (11-bit immediate)
        instructions.append(enc.addi(4, 5, 0))                     # x4 = x5 (copy for use)
    else:
        outer_count = delay_cycles // 5000
        instructions.append(enc.lui(5, outer_count >> 12))     # x5 = outer count upper
        instructions.append(enc.addi(4, 5, outer_count & 0xFFF))  # x4 = outer count full
    
    # ========== MODE DISPATCH ==========
    mode_dispatch_pc = len(instructions) * 4
    
    # Check mode 0 (Counter)
    instructions.append(enc.addi(11, 0, 0))         # x11 = 0
    instructions.append(enc.beq(2, 11, 12))         # if x2 == 0, goto mode 0
    
    # Check mode 1 (Knight Rider)
    instructions.append(enc.addi(11, 0, 1))         # x11 = 1
    instructions.append(enc.beq(2, 11, 44))         # if x2 == 1, goto mode 1
    
    # Check mode 2 (Blink)
    instructions.append(enc.addi(11, 0, 2))         # x11 = 2
    instructions.append(enc.beq(2, 11, 84))         # if x2 == 2, goto mode 2
    
    # Mode 3 (Alternating) - fallthrough
    
    # ========== MODE 3: ALTERNATING (0x5 ↔ 0xA) ==========
    mode3_start_pc = len(instructions) * 4
    instructions.append(enc.addi(1, 0, 0x5))        # x1 = 0x5 (initial pattern)
    instructions.append(enc.addi(18, 0, 50))        # x18 = 50 iterations per mode
    
    mode3_loop_pc = len(instructions) * 4
    # Write pattern
    instructions.append(enc.sw(1, 16, 0))           # MEM[0x407C] = x1
    
    # Delay loop
    if fast_sim:
        # Simple loop for fast simulation
        instructions.append(enc.addi(4, 5, 0))      # Reset counter
        mode3_delay_pc = len(instructions) * 4
        instructions.append(enc.addi(4, 4, -1))     # x4--
        instructions.append(enc.bne(4, 0, -4))      # Loop
    else:
        # Nested loop for FPGA (longer delays)
        instructions.append(enc.addi(4, 5, 0))          # Reset outer counter
        mode3_outer_pc = len(instructions) * 4
        instructions.append(enc.addi(3, 0, 5000))       # Inner = 5000
        mode3_inner_pc = len(instructions) * 4
        instructions.append(enc.addi(3, 3, -1))         # x3--
        instructions.append(enc.bne(3, 0, -4))          # Inner loop
        instructions.append(enc.addi(4, 4, -1))         # Outer--
        instructions.append(enc.bne(4, 0, mode3_inner_pc - (len(instructions) * 4 + 4)))  # Outer loop
    
    # Toggle pattern (0x5 XOR 0xF = 0xA, 0xA XOR 0xF = 0x5)
    instructions.append(enc.xori(1, 1, 0xF))        # x1 ^= 0xF
    
    # Decrement iteration counter
    instructions.append(enc.addi(18, 18, -1))       # x18--
    instructions.append(enc.bne(18, 0, mode3_loop_pc - (len(instructions) * 4 + 4)))  # Loop
    
    # Mode transition
    instructions.append(enc.addi(2, 2, 1))          # x2++ (next mode)
    instructions.append(enc.addi(11, 0, 4))         # x11 = 4
    instructions.append(enc.blt(2, 11, mode_dispatch_pc - (len(instructions) * 4 + 4)))  # if x2 < 4, dispatch
    instructions.append(enc.addi(2, 0, 0))          # x2 = 0 (reset mode)
    instructions.append(enc.jal(0, mode_dispatch_pc - (len(instructions) * 4 + 4)))  # Jump to dispatch
    
    # ========== MODE 0: BINARY COUNTER (0→15) ==========
    mode0_start_pc = len(instructions) * 4
    if fast_sim:
        instructions.append(enc.addi(4, 5, 0))      # Reset counter
        mode0_delay_pc = len(instructions) * 4
        instructions.append(enc.addi(4, 4, -1))     # x4--
        instructions.append(enc.bne(4, 0, -4))      # Loop
    else:
        instructions.append(enc.addi(4, 5, 0))          # Reset outer counter
        mode0_outer_pc = len(instructions) * 4
        instructions.append(enc.addi(3, 0, 5000))       # Inner = 5000
        mode0_inner_pc = len(instructions) * 4
        instructions.append(enc.addi(3, 3, -1))         # x3--
        instructions.append(enc.bne(3, 0, -4))          # Inner loop
        instructions.append(enc.addi(4, 4, -1))         # Outer--
        # Delay loop
    instructions.append(enc.addi(4, 5, 0))          # Reset outer counter
    mode0_outer_pc = len(instructions) * 4
    instructions.append(enc.addi(3, 0, 5000))       # Inner = 5000
    mode0_inner_pc = len(instructions) * 4
    instructions.append(enc.addi(3, 3, -1))         # x3--
    instructions.append(enc.bne(3, 0, -4))          # Inner loop
    instructions.append(enc.addi(4, 4, -1))         # Outer--
    instructions.append(enc.bne(4, 0, mode0_inner_pc - (len(instructions) * 4 + 4)))  # Outer loop
    
    # Increment counter
    instructions.append(enc.addi(1, 1, 1))          # x1++
    instructions.append(enc.andi(1, 1, 0xF))        # x1 &= 0xF (keep 4 bits)
    
    # Decrement iteration counter
    instructions.append(enc.addi(18, 18, -1))       # x18--
    instructions.append(enc.bne(18, 0, mode0_loop_pc - (len(instructions) * 4 + 4)))  # Loop
    
    # Mode transition
    if fast_sim:
        instructions.append(enc.addi(4, 5, 0))      # Reset counter
        mode1_delay_pc = len(instructions) * 4
        instructions.append(enc.addi(4, 4, -1))     # x4--
        instructions.append(enc.bne(4, 0, -4))      # Loop
    else:
        instructions.append(enc.addi(4, 5, 0))          # Reset outer counter
        mode1_outer_pc = len(instructions) * 4
        instructions.append(enc.addi(3, 0, 5000))       # Inner = 5000
        mode1_inner_pc = len(instructions) * 4
        instructions.append(enc.addi(3, 3, -1))         # x3--
        instructions.append(enc.bne(3, 0, -4))          # Inner loop
        instructions.append(enc.addi(4, 4, -1))         # Outer--
        instructions.append(enc.addi(10, 0, 1))         # x10 = 1 (shift direction: 1=left, -1=right)
    
    mode1_loop_pc = len(instructions) * 4
    # Write pattern
    instructions.append(enc.sw(1, 16, 0))           # MEM[0x407C] = x1
    
    # Delay loop
    instructions.append(enc.addi(4, 5, 0))          # Reset outer counter
    mode1_outer_pc = len(instructions) * 4
    instructions.append(enc.addi(3, 0, 5000))       # Inner = 5000
    mode1_inner_pc = len(instructions) * 4
    instructions.append(enc.addi(3, 3, -1))         # x3--
    instructions.append(enc.bne(3, 0, -4))          # Inner loop
    instructions.append(enc.addi(4, 4, -1))         # Outer--
    instructions.append(enc.bne(4, 0, mode1_inner_pc - (len(instructions) * 4 + 4)))  # Outer loop
    
    # Shift pattern
    instructions.append(enc.addi(11, 0, 1))         # x11 = 1 (compare value)
    instructions.append(enc.beq(10, 11, 12))        # if direction == 1, shift left
    
    # Shift right branch
    instructions.append(enc.srli(1, 1, 1))          # x1 >>= 1
    instructions.append(enc.addi(11, 0, 1))         # x11 = 1
    instructions.append(enc.bne(1, 11, 20))         # if x1 != 1, skip direction change
    instructions.append(enc.addi(10, 0, 1))         # x10 = 1 (change to left)
    instructions.append(enc.jal(0, 16))             # Skip left shift
    
    # Shift left branch
    instructions.append(enc.slli(1, 1, 1))          # x1 <<= 1
    instructions.append(enc.addi(11, 0, 8))         # x11 = 8
    instructions.append(enc.bne(1, 11, 8))          # if x1 != 8, skip direction change
    instructions.append(enc.addi(10, 0, -1))        # x10 = -1 (change to right)
    
    # Decrement iteration counter
    instructions.append(enc.addi(18, 18, -1))       # x18--
    instructions.append(enc.bne(18, 0, mode1_loop_pc - (len(instructions) * 4 + 4)))  # Loop
    
    # Mode transition
    instructions
    if fast_sim:
        instructions.append(enc.addi(4, 5, 0))      # Reset counter
        mode2_delay_pc = len(instructions) * 4
        instructions.append(enc.addi(4, 4, -1))     # x4--
        instructions.append(enc.bne(4, 0, -4))      # Loop
    else:
        # Longer delay for blink visibility on FPGA
        instructions.append(enc.addi(4, 5, 0))          # Reset outer counter
        instructions.append(enc.addi(4, 4, 0))          # x4 = x4 (double delay)
        mode2_outer_pc = len(instructions) * 4
        instructions.append(enc.addi(3, 0, 5000))       # Inner = 5000
        mode2_inner_pc = len(instructions) * 4
        instructions.append(enc.addi(3, 3, -1))         # x3--
        instructions.append(enc.bne(3, 0, -4))          # Inner loop
        instructions.append(enc.addi(4, 4, -1))         # Outer--
        # Write pattern
    instructions.append(enc.sw(1, 16, 0))           # MEM[0x407C] = x1
    
    # Delay loop (longer for blink visibility)
    instructions.append(enc.addi(4, 5, 0))          # Reset outer counter
    instructions.append(enc.addi(4, 4, 0))          # x4 = x4 (double delay)
    mode2_outer_pc = len(instructions) * 4
    instructions.append(enc.addi(3, 0, 5000))       # Inner = 5000
    mode2_inner_pc = len(instructions) * 4
    instructions.append(enc.addi(3, 3, -1))         # x3--
    instructions.append(enc.bne(3, 0, -4))          # Inner loop
    instructions.append(enc.addi(4, 4, -1))         # Outer--
    instructions.append(enc.bne(4, 0, mode2_inner_pc - (len(instructions) * 4 + 4)))  # Outer loop
    
    # Toggle pattern (0xF XOR 0xF = 0x0, 0x0 XOR 0xF = 0xF)
    instructions.append(enc.xori(1, 1, 0xF))        # x1 ^= 0xF
    
    # Decrement iteration counter
    instructions.append(enc.addi(18, 18, -1))       # x18--
    instructions.append(enc.bne(18, 0, mode2_loop_pc - (len(instructions) * 4 + 4)))  # Loop
    
    # Mode transition
    instructions.append(enc.addi(2, 2, 1))          # x2++ (next mode)
    instructions.append(enc.jal(0, mode_dispatch_pc - (len(instructions) * 4 + 4)))  # Jump to dispatch
    
    return instructions


def generate_led_complex_pattern_fast(delay_cycles=200):
    """
    Generate complex multi-mode LED pattern program (FAST SIMULATION VERSION).
    
    This is a high-speed variant optimized for short simulation runs.
    Default delay of 200 cycles allows 24+ LED changes in 100μs @ 125MHz.
    
    Cycles through 4 distinct LED patterns automatically:
    - Mode 0: Binary counter (1→6, 6 iterations)
    - Mode 1: Knight Rider scan (1→2→4→8→4→2, 6 steps)
    - Mode 2: Blink all LEDs (0xF ↔ 0x0, 6 toggles)
    - Mode 3: Alternating pattern (0x5 ↔ 0xA, 6 toggles)
    
    Args:
        delay_cycles: Number of cycles for each pattern iteration (default: 200)
                     200 cycles = 1.6μs @ 125MHz
                     24 changes in ~40μs (fits easily in 100μs)
    
    Returns:
        List of RV32I instructions (approximately 80 instructions)
    """
    enc = RV32IInstructionEncoder()
    instructions = []
    
    # ========== SETUP ==========
    # Initialize LED address
    instructions.append(enc.lui(15, 0x4))           # x15 = 0x4000
    instructions.append(enc.addi(16, 15, 0x7C))     # x16 = 0x407C (LED address)
    
    # Initialize mode counter
    instructions.append(enc.addi(2, 0, 0))          # x2 = 0 (start at mode 0)
    
    # Delay constant (much shorter for simulation)
    instructions.append(enc.addi(5, 0, delay_cycles & 0x7FF))  # x5 = delay count (max 2047)
    
    # ========== MODE DISPATCH ==========
    mode_dispatch_pc = len(instructions) * 4
    
    # Placeholder: will be patched with correct offsets
    mode0_beq_idx = len(instructions)
    instructions.append(enc.addi(11, 0, 0))         # x11 = 0
    instructions.append(enc.beq(2, 11, 0))          # PLACEHOLDER: if x2 == 0, goto mode 0
    
    mode1_beq_idx = len(instructions)
    instructions.append(enc.addi(11, 0, 1))         # x11 = 1
    instructions.append(enc.beq(2, 11, 0))          # PLACEHOLDER: if x2 == 1, goto mode 1
    
    mode2_beq_idx = len(instructions)
    instructions.append(enc.addi(11, 0, 2))         # x11 = 2
    instructions.append(enc.beq(2, 11, 0))          # PLACEHOLDER: if x2 == 2, goto mode 2
    
    # Mode 3 (Alternating) - fallthrough
    
    # ========== MODE 3: ALTERNATING (0x5 ↔ 0xA) ==========
    mode3_start_pc = len(instructions) * 4
    instructions.append(enc.addi(1, 0, 0x5))        # x1 = 0x5 (initial pattern)
    instructions.append(enc.addi(18, 0, 6))         # x18 = 6 iterations (fast sim)
    
    mode3_loop_pc = len(instructions) * 4
    # Write pattern
    instructions.append(enc.sw(1, 16, 0))           # MEM[0x407C] = x1
    
    # Simple delay loop (no nested loops for speed)
    instructions.append(enc.addi(3, 5, 0))          # x3 = delay count
    mode3_delay_pc = len(instructions) * 4
    instructions.append(enc.addi(3, 3, -1))         # x3--
    instructions.append(enc.bne(3, 0, -4))          # Loop if non-zero
    
    # Toggle pattern
    instructions.append(enc.xori(1, 1, 0xF))        # x1 ^= 0xF (0x5 ↔ 0xA)
    
    # Decrement iteration counter
    instructions.append(enc.addi(18, 18, -1))       # x18--
    instructions.append(enc.bne(18, 0, mode3_loop_pc - (len(instructions) * 4 + 4)))  # Loop
    
    # Mode transition
    instructions.append(enc.addi(2, 2, 1))          # x2++ (next mode)
    instructions.append(enc.addi(11, 0, 4))         # x11 = 4
    instructions.append(enc.blt(2, 11, mode_dispatch_pc - (len(instructions) * 4 + 4)))  # if x2 < 4, dispatch
    instructions.append(enc.addi(2, 0, 0))          # x2 = 0 (reset mode)
    instructions.append(enc.jal(0, mode_dispatch_pc - (len(instructions) * 4 + 4)))  # Jump to dispatch
    
    # ========== MODE 0: BINARY COUNTER (0→15) ==========
    mode0_start_pc = len(instructions) * 4
    instructions.append(enc.addi(1, 0, 1))          # x1 = 1 (start from 1, not 0)
    instructions.append(enc.addi(18, 0, 6))         # x18 = 6 iterations (fast sim)
    
    mode0_loop_pc = len(instructions) * 4
    # Write pattern
    instructions.append(enc.sw(1, 16, 0))           # MEM[0x407C] = x1
    
    # Simple delay loop
    instructions.append(enc.addi(3, 5, 0))          # x3 = delay count
    mode0_delay_pc = len(instructions) * 4
    instructions.append(enc.addi(3, 3, -1))         # x3--
    instructions.append(enc.bne(3, 0, -4))          # Loop
    
    # Increment counter
    instructions.append(enc.addi(1, 1, 1))          # x1++
    instructions.append(enc.andi(1, 1, 0xF))        # x1 &= 0xF (keep 4 bits)
    
    # Decrement iteration counter
    instructions.append(enc.addi(18, 18, -1))       # x18--
    instructions.append(enc.bne(18, 0, mode0_loop_pc - (len(instructions) * 4 + 4)))  # Loop
    
    # Mode transition
    instructions.append(enc.addi(2, 2, 1))          # x2++ (next mode)
    instructions.append(enc.jal(0, mode_dispatch_pc - (len(instructions) * 4 + 4)))  # Jump to dispatch
    
    # ========== MODE 1: KNIGHT RIDER (1→2→4→8) ==========
    mode1_start_pc = len(instructions) * 4
    instructions.append(enc.addi(1, 0, 1))          # x1 = 1 (start pattern)
    instructions.append(enc.addi(18, 0, 6))         # x18 = 6 iterations (fast sim)
    
    mode1_loop_pc = len(instructions) * 4
    # Write pattern
    instructions.append(enc.sw(1, 16, 0))           # MEM[0x407C] = x1
    
    # Simple delay loop
    instructions.append(enc.addi(3, 5, 0))          # x3 = delay count
    mode1_delay_pc = len(instructions) * 4
    instructions.append(enc.addi(3, 3, -1))         # x3--
    instructions.append(enc.bne(3, 0, -4))          # Loop
    
    # Shift left
    instructions.append(enc.slli(1, 1, 1))          # x1 <<= 1
    instructions.append(enc.andi(1, 1, 0xF))        # Keep in range
    
    # Decrement iteration counter
    instructions.append(enc.addi(18, 18, -1))       # x18--
    instructions.append(enc.bne(18, 0, mode1_loop_pc - (len(instructions) * 4 + 4)))  # Loop
    
    # Mode transition
    instructions.append(enc.addi(2, 2, 1))          # x2++ (next mode)
    instructions.append(enc.jal(0, mode_dispatch_pc - (len(instructions) * 4 + 4)))  # Jump to dispatch
    
    # ========== MODE 2: BLINK ALL (0xF ↔ 0x0) ==========
    mode2_start_pc = len(instructions) * 4
    instructions.append(enc.addi(1, 0, 0xF))        # x1 = 0xF (all on)
    instructions.append(enc.addi(18, 0, 6))         # x18 = 6 iterations (fast sim)
    
    mode2_loop_pc = len(instructions) * 4
    # Write pattern
    instructions.append(enc.sw(1, 16, 0))           # MEM[0x407C] = x1
    
    # Simple delay loop
    instructions.append(enc.addi(3, 5, 0))          # x3 = delay count
    mode2_delay_pc = len(instructions) * 4
    instructions.append(enc.addi(3, 3, -1))         # x3--
    instructions.append(enc.bne(3, 0, -4))          # Loop
    
    # Toggle pattern
    instructions.append(enc.xori(1, 1, 0xF))        # x1 ^= 0xF (0xF ↔ 0x0)
    
    # Decrement iteration counter
    instructions.append(enc.addi(18, 18, -1))       # x18--
    instructions.append(enc.bne(18, 0, mode2_loop_pc - (len(instructions) * 4 + 4)))  # Loop
    
    # Mode transition
    instructions.append(enc.addi(2, 2, 1))          # x2++ (next mode)
    instructions.append(enc.jal(0, mode_dispatch_pc - (len(instructions) * 4 + 4)))  # Jump to dispatch
    
    # ========== PATCH BRANCH OFFSETS ==========
    # Now that we know all mode start addresses, patch the dispatch branches
    # RV32I branch offset is relative to the branch instruction PC
    # BEQ is at index (mode_beq_idx + 1), which has PC = (mode_beq_idx + 1) * 4
    beq_pc_mode0 = (mode0_beq_idx + 1) * 4
    beq_pc_mode1 = (mode1_beq_idx + 1) * 4
    beq_pc_mode2 = (mode2_beq_idx + 1) * 4
    
    beq_offset_mode0 = mode0_start_pc - beq_pc_mode0
    beq_offset_mode1 = mode1_start_pc - beq_pc_mode1
    beq_offset_mode2 = mode2_start_pc - beq_pc_mode2
    
    instructions[mode0_beq_idx + 1] = enc.beq(2, 11, beq_offset_mode0)  # Patch mode 0 branch
    instructions[mode1_beq_idx + 1] = enc.beq(2, 11, beq_offset_mode1)  # Patch mode 1 branch
    instructions[mode2_beq_idx + 1] = enc.beq(2, 11, beq_offset_mode2)  # Patch mode 2 branch
    
    return instructions

