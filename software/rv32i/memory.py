"""RV32I Memory Access Helpers

Low-level memory read/write via CPU debug interface.
Depends on: axiuart_driver

Register addresses (from axiuart_registers.json):
- CPU_MEM_ADDR (0x1228): Memory address (32-bit byte address)
- CPU_MEM_WDATA (0x122C): Write data (32-bit)
- CPU_MEM_RDATA (0x1230): Read data (32-bit)
- CPU_MEM_CTRL (0x1234): Control register

Memory access sequence:
1. Write address to CPU_MEM_ADDR
2. Write data to CPU_MEM_WDATA (for write)
3. Write control word to CPU_MEM_CTRL with write_req/read_req bit
4. Poll busy bit until clear
5. Read CPU_MEM_RDATA (for read)

Usage:
    from axiuart_driver import AXIUARTDriver
    from rv32i.memory import write_cpu_mem, read_cpu_mem
    
    with AXIUARTDriver('/dev/ttyUSB0', 115200) as driver:
        write_cpu_mem(driver, 0x0, 0x12345678)
        data = read_cpu_mem(driver, 0x0)
"""

import time


# Register addresses
CPU_MEM_ADDR_REG = 0x1228
CPU_MEM_WDATA_REG = 0x122C
CPU_MEM_RDATA_REG = 0x1230
CPU_MEM_CTRL_REG = 0x1234

# Control bit masks
CPU_CTRL_BYTE_EN = 0x0F     # [3:0] All bytes enabled
CPU_CTRL_READ_REQ = 0x10    # [4] Read request (W1P)
CPU_CTRL_WRITE_REQ = 0x20   # [5] Write request (W1P)
CPU_CTRL_BUSY = 0x40        # [6] Busy flag (RO)


def _wait_not_busy(driver, timeout=1.0):
    """Wait for memory controller busy flag to clear"""
    start_time = time.time()
    while time.time() - start_time < timeout:
        status = driver.read_reg32(CPU_MEM_CTRL_REG)
        if not (status & CPU_CTRL_BUSY):
            return
        time.sleep(0.001)
    raise TimeoutError("Memory controller busy timeout")


def write_cpu_mem(driver, addr, data):
    """
    Write 32-bit word to CPU memory via debug interface.
    
    CPU must be halted for debug access.
    
    Args:
        driver: AXIUARTDriver instance
        addr: Byte address (must be 4-byte aligned)
        data: 32-bit value to write
    
    Raises:
        ValueError: If addr is not 4-byte aligned
    """
    if addr % 4 != 0:
        raise ValueError(f"Address must be 4-byte aligned, got 0x{addr:x}")
    
    # Write address
    driver.write_reg32(CPU_MEM_ADDR_REG, addr)
    
    # Write data
    driver.write_reg32(CPU_MEM_WDATA_REG, data)
    
    # Trigger write with all byte enables
    driver.write_reg32(CPU_MEM_CTRL_REG, CPU_CTRL_WRITE_REQ | CPU_CTRL_BYTE_EN)
    
    # Wait for completion
    _wait_not_busy(driver)


def read_cpu_mem(driver, addr):
    """
    Read 32-bit word from CPU memory via debug interface.
    
    CPU must be halted for debug access.
    
    Args:
        driver: AXIUARTDriver instance
        addr: Byte address (must be 4-byte aligned)
    
    Returns:
        32-bit value read from memory
    
    Raises:
        ValueError: If addr is not 4-byte aligned
    """
    if addr % 4 != 0:
        raise ValueError(f"Address must be 4-byte aligned, got 0x{addr:x}")
    
    # Write address
    driver.write_reg32(CPU_MEM_ADDR_REG, addr)
    
    # Trigger read with all byte enables
    driver.write_reg32(CPU_MEM_CTRL_REG, CPU_CTRL_READ_REQ | CPU_CTRL_BYTE_EN)
    
    # Wait for completion
    _wait_not_busy(driver)
    
    # Read result
    return driver.read_reg32(CPU_MEM_RDATA_REG)


def verify_memory(driver, addr, expected):
    """
    Verify memory contents match expected value.
    
    Args:
        driver: AXIUARTDriver instance
        addr: Byte address (must be 4-byte aligned)
        expected: Expected 32-bit value
    
    Returns:
        bool: True if match, False otherwise
    """
    actual = read_cpu_mem(driver, addr)
    return actual == expected
