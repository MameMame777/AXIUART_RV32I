"""RV32I CPU Control Functions

High-level CPU control via AXIUART driver using debug interface.
Depends on: axiuart_driver

Register addresses (from axiuart_registers.json):
- CPU_MEM_CTRL (0x1234): Control register
  [9]: cpu_halted (RO) - CPU is halted
  [8]: cpu_halt (W) - Request CPU halt
  [7]: cpu_run (W) - Request CPU run
  [6]: busy (RO) - Memory operation in progress
  [5]: write_req (W1P) - Trigger memory write
  [4]: read_req (W1P) - Trigger memory read
  [3:0]: byte_enables (W) - Byte lane enables

Usage:
    from axiuart_driver import AXIUARTDriver
    from rv32i.cpu_control import halt_cpu, run_cpu, write_program
    
    with AXIUARTDriver('/dev/ttyUSB0', 115200) as driver:
        halt_cpu(driver)
        write_program(driver, [0x13, 0x93, 0x00100073])  # ADDI, EBREAK
        run_cpu(driver)
"""

import time


# Register addresses
CPU_MEM_CTRL_ADDR = 0x1234

# Control bit masks
CPU_CTRL_BYTE_EN = 0x0F     # [3:0] All bytes enabled
CPU_CTRL_READ_REQ = 0x10    # [4] Read request (W1P)
CPU_CTRL_WRITE_REQ = 0x20   # [5] Write request (W1P)
CPU_CTRL_BUSY = 0x40        # [6] Busy flag (RO)
CPU_CTRL_RUN = 0x80         # [7] CPU run
CPU_CTRL_HALT = 0x100       # [8] CPU halt
CPU_CTRL_HALTED = 0x200     # [9] CPU halted status (RO)
CPU_CTRL_BREAK = 0x400      # [10] CPU break status (RO)


def halt_cpu(driver, timeout=1.0):
    """
    Halt CPU execution via CPU_MEM_CTRL register.
    
    Args:
        driver: AXIUARTDriver instance
        timeout: Maximum wait time in seconds (default: 1.0)
    
    Raises:
        TimeoutError: If CPU doesn't halt within timeout
    """
    # Request halt
    driver.write_reg32(CPU_MEM_CTRL_ADDR, CPU_CTRL_HALT)
    
    # Wait for halted status
    start_time = time.time()
    while time.time() - start_time < timeout:
        status = driver.read_reg32(CPU_MEM_CTRL_ADDR)
        if status & CPU_CTRL_HALTED:
            return
        time.sleep(0.01)
    
    raise TimeoutError("CPU failed to halt within timeout")


def run_cpu(driver):
    """
    Resume CPU execution.
    
    Args:
        driver: AXIUARTDriver instance
    """
    # Clear halt bit, set run bit
    driver.write_reg32(CPU_MEM_CTRL_ADDR, CPU_CTRL_RUN)


def reset_cpu(driver):
    """
    Soft reset CPU (halt, then resume from PC=0).
    
    Args:
        driver: AXIUARTDriver instance
    """
    halt_cpu(driver)
    # CPU automatically resets PC to 0 on halt
    run_cpu(driver)


def get_cpu_status(driver):
    """
    Read CPU control register status.
    
    Args:
        driver: AXIUARTDriver instance
    
    Returns:
        dict: Status flags
            - 'halted': CPU is halted
            - 'break': CPU hit EBREAK
            - 'busy': Memory operation in progress
    """
    status = driver.read_reg32(CPU_MEM_CTRL_ADDR)
    return {
        'halted': bool(status & CPU_CTRL_HALTED),
        'break': bool(status & CPU_CTRL_BREAK),
        'busy': bool(status & CPU_CTRL_BUSY)
    }


def write_program(driver, instructions, start_addr=0):
    """
    Write instruction list to CPU memory via debug interface.
    
    CPU must be halted before writing. This function does NOT
    automatically halt the CPU.
    
    Args:
        driver: AXIUARTDriver instance
        instructions: List of 32-bit encoded instructions
        start_addr: Starting byte address (must be 4-byte aligned)
    
    Raises:
        ValueError: If start_addr is not 4-byte aligned
        RuntimeError: If CPU is not halted
    """
    if start_addr % 4 != 0:
        raise ValueError(f"start_addr must be 4-byte aligned, got {start_addr}")
    
    # Verify CPU is halted
    status = get_cpu_status(driver)
    if not status['halted']:
        raise RuntimeError("CPU must be halted before writing program")
    
    # Import memory module (avoid circular dependency)
    try:
        from .memory import write_cpu_mem
    except ImportError:
        from memory import write_cpu_mem
    
    # Write each instruction
    for i, insn in enumerate(instructions):
        addr = start_addr + (i * 4)
        write_cpu_mem(driver, addr, insn)
