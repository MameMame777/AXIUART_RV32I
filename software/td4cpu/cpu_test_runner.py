#!/usr/bin/env python3
"""
TD4CPU Hardware Test Runner

Real-hardware validation tool for TD4 CPU over UART.
Executes 17 ALU tests validated in UVM simulation.

Usage:
    python cpu_test_runner.py --port COM3
    python cpu_test_runner.py --port /dev/ttyUSB0 --baudrate 115200
"""

import sys
import time
import argparse
import logging
from pathlib import Path
from typing import Optional

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from axiuart_driver import AXIUARTDriver, registers
from td4cpu import isa
from td4cpu.test_cases import ALU_TESTS, format_test_result


class Colors:
    """ANSI color codes for terminal output"""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    END = '\033[0m'


class CPUTestRunner:
    """Hardware test runner for TD4 CPU"""
    
    def __init__(self, port: str, baudrate: int = 115200, timeout: float = 2.0):
        """
        Initialize test runner
        
        Args:
            port: Serial port name (e.g., 'COM3' or '/dev/ttyUSB0')
            baudrate: UART baud rate
            timeout: Communication timeout in seconds
        """
        self.driver = AXIUARTDriver(port, baudrate=baudrate, timeout=timeout)
        self.results = []
        
    def open(self):
        """Open UART connection"""
        print(f"{Colors.CYAN}Opening {self.driver.port} @ {self.driver.baudrate} baud...{Colors.END}")
        self.driver.open()
        time.sleep(0.1)  # Let hardware stabilize
        
    def close(self):
        """Close UART connection"""
        self.driver.close()
        
    def reset_cpu(self):
        """Reset CPU to known state"""
        print(f"{Colors.YELLOW}Resetting CPU...{Colors.END}")
        # Halt CPU first (bit 0 of CPU_DBG_CTRL is HALT pulse)
        self.driver.write_reg32(registers.REG_CPU_DBG_CTRL, 0x00000001)
        time.sleep(0.01)
        
        # Clear all general-purpose registers (R0-R7)
        for i in range(8):
            self.write_register(i, 0x0000)
        
    def halt_cpu(self):
        """Halt CPU execution"""
        # Write 1 to bit 0 (HALT pulse bit)
        self.driver.write_reg32(registers.REG_CPU_DBG_CTRL, 0x00000001)
        
    def run_cpu(self):
        """Resume CPU execution"""
        # Write 1 to bit 1 (RUN pulse bit)
        self.driver.write_reg32(registers.REG_CPU_DBG_CTRL, 0x00000002)
        
    def write_register(self, reg_index: int, value: int):
        """
        Write value to CPU general-purpose register
        
        Args:
            reg_index: Register index (0-7 for R0-R7)
            value: 16-bit value to write
        """
        if not (0 <= reg_index <= 7):
            raise ValueError(f"Invalid register index: {reg_index}")
        
        # Ensure CPU is halted (writes only work when halted)
        status = self.driver.read_reg32(registers.REG_CPU_DBG_STATUS)
        if not (status & 0x01):  # Check halted bit
            self.halt_cpu()
            time.sleep(0.005)
        
        # Use indirect access: set index, then write data
        self.driver.write_reg32(registers.REG_CPU_REG_INDEX, reg_index)
        time.sleep(0.005)  # Increased delay for index settle
        self.driver.write_reg32(registers.REG_CPU_REG_DATA, value & 0xFFFF)
        time.sleep(0.005)  # Allow write to propagate
        
    # ============================================================
    # Trace Buffer Control (Hardware Validation)
    # ============================================================
    
    def clear_trace_buffer(self):
        """Clear trace buffer by writing pulse to bit 1"""
        # Write 0x02 to pulse clear (bit 1), preserves enable state
        ctrl_val = self.driver.read_reg32(registers.REG_CPU_TRACE_CTRL)
        enable_bit = ctrl_val & 0x01
        self.driver.write_reg32(registers.REG_CPU_TRACE_CTRL, enable_bit | 0x02)
        time.sleep(0.001)  # Allow pulse to complete
    
    def enable_trace(self, enable: bool = True):
        """Enable/disable trace recording
        
        Args:
            enable: True to enable trace, False to disable
        """
        val = 0x00000001 if enable else 0x00000000
        self.driver.write_reg32(registers.REG_CPU_TRACE_CTRL, val)
    
    def read_trace_count(self) -> int:
        """Read number of trace entries recorded
        
        Returns:
            Number of entries in trace buffer (0-255)
        """
        return self.driver.read_reg32(registers.REG_CPU_TRACE_PTR) & 0xFF
    
    def read_trace_entry(self, index: int) -> tuple:
        """Read trace buffer entry
        
        Args:
            index: Entry index (0-255)
            
        Returns:
            Tuple of (instruction[15:0], result[15:0])
        """
        if not (0 <= index <= 255):
            raise ValueError(f"Invalid trace index: {index}")
        
        # Set trace buffer read address
        self.driver.write_reg32(registers.REG_CPU_TRACE_ADDR, index)
        time.sleep(0.001)  # Small delay for address setup
        
        # Read trace data (format: [31:16]=instruction, [15:0]=result)
        data = self.driver.read_reg32(registers.REG_CPU_TRACE_RDATA)
        
        # Format: [31:16]=instruction, [15:0]=result
        instruction = (data >> 16) & 0xFFFF
        result = data & 0xFFFF
        
        return (instruction, result)
    
    # ============================================================
        
    def read_register(self, reg_index: int) -> int:
        """
        Read value from CPU general-purpose register
        
        Args:
            reg_index: Register index (0-7 for R0-R7)
            
        Returns:
            16-bit register value
        """
        if not (0 <= reg_index <= 7):
            raise ValueError(f"Invalid register index: {reg_index}")
        
        # Use indirect access: set index, then read data
        # The read generates a pulse that latches the register value
        self.driver.write_reg32(registers.REG_CPU_REG_INDEX, reg_index)
        time.sleep(0.005)  # Increased delay for index to settle
        # Do a dummy read-back of index to ensure it's latched in hardware
        _ = self.driver.read_reg32(registers.REG_CPU_REG_INDEX)
        value = self.driver.read_reg32(registers.REG_CPU_REG_DATA)
        return value & 0xFFFF
        
    def read_flags(self) -> int:
        """
        Read CPU flags register
        
        Returns:
            3-bit flags value (Z=bit2, N=bit1, C=bit0)
        """
        value = self.driver.read_reg32(registers.REG_CPU_FLAGS)
        return value & 0x07
        
    def load_instruction(self, address: int, instruction: int):
        """
        Load single instruction into CPU memory
        
        Args:
            address: Memory address (word-aligned)
            instruction: 16-bit instruction word
        """
        # Use debug memory interface
        self.driver.write_reg32(registers.REG_CPU_MEM_ADDR, address)
        self.driver.write_reg32(registers.REG_CPU_MEM_WDATA, instruction & 0xFFFF)
        # Write request (bit 1=WRITE bit)
        self.driver.write_reg32(registers.REG_CPU_MEM_CTRL, 0x00000002)
        time.sleep(0.001)  # Allow write to complete
        
    def execute_single_instruction(self, instruction: int):
        """
        Execute a single instruction and return to halt
        
        Args:
            instruction: 16-bit instruction to execute
        """
        # 1. Halt CPU
        self.halt_cpu()
        time.sleep(0.01)
        
        # 2. Load instruction at address 0
        self.load_instruction(0, instruction)
        
        # 3. Set PC to 0
        self.driver.write_reg32(registers.REG_CPU_PC, 0x0000)
        
        # 4. Execute one step (bit 2 = STEP pulse bit)
        self.driver.write_reg32(registers.REG_CPU_DBG_CTRL, 0x00000004)
        time.sleep(0.05)  # Wait for execution (Phase 3: 4-stage pipeline + writeback cycle)
        
        # 5. Verify CPU halted and pipeline drained
        # Wait for pipeline to fully drain (additional cycles for writeback)
        max_wait = 10  # 10 iterations @ 10ms each = 100ms max
        for _ in range(max_wait):
            status = self.driver.read_reg32(registers.CPU_STATUS)
            halted = (status & 0x01) != 0
            if halted:
                break
            time.sleep(0.01)
        time.sleep(0.01)  # Extra settle time after halt confirmed
        
    def run_test(self, test, test_num: int, total: int) -> dict:
        """
        Run single test case
        
        Args:
            test: TestCase object
            test_num: Current test number
            total: Total number of tests
            
        Returns:
            dict with test results
        """
        print(f"\n{Colors.BOLD}[{test_num}/{total}] {test.name}{Colors.END}")
        print(f"    {test.description}")
        
        try:
            # 1. Reset CPU
            self.reset_cpu()
            
            # 2. Setup registers
            for reg_idx, value in test.setup:
                self.write_register(reg_idx, value)
                print(f"    Setup: R{reg_idx} = 0x{value:04X}")
            
            # 3. Execute instruction
            print(f"    Instruction: 0x{test.instruction:04X}")
            self.execute_single_instruction(test.instruction)
            
            # 4. Read results
            # Determine which register to read based on instruction
            rd = (test.instruction >> 9) & 0x7
            actual_result = self.read_register(rd)
            actual_flags = self.read_flags()
            
            # 5. Compare with expected
            result = format_test_result(test, actual_result, actual_flags)
            
            # 6. Print result
            if result['passed']:
                print(f"    {Colors.GREEN}{result['message']}{Colors.END}")
            else:
                print(f"    {Colors.RED}{result['message']}{Colors.END}")
            
            return result
            
        except Exception as e:
            error_msg = f"✗ ERROR: {str(e)}"
            print(f"    {Colors.RED}{error_msg}{Colors.END}")
            return {
                'passed': False,
                'error': str(e),
                'message': error_msg
            }
            
    def run_all_tests(self):
        """Run complete test suite using trace buffer (matches simulation methodology)"""
        print(f"\n{Colors.HEADER}{'='*70}{Colors.END}")
        print(f"{Colors.HEADER}{Colors.BOLD}TD4 CPU Hardware Validation Suite{Colors.END}")
        print(f"{Colors.HEADER}17 ALU Tests (trace buffer validation){Colors.END}")
        print(f"{Colors.HEADER}{'='*70}{Colors.END}")
        
        self.results = []
        start_time = time.time()
        
        try:
            # ============================================================
            # Phase 1: Prepare trace buffer
            # ============================================================
            print(f"\n{Colors.CYAN}[Phase 1/4] Preparing trace buffer...{Colors.END}")
            self.clear_trace_buffer()
            self.enable_trace(True)
            print(f"    ✓ Trace buffer cleared and enabled")
            
            # ============================================================
            # Phase 2: Halt CPU and load test program
            # ============================================================
            print(f"\n{Colors.CYAN}[Phase 2/4] Loading test program...{Colors.END}")
            self.halt_cpu()
            time.sleep(0.01)
            
            # Set PC to 0
            self.driver.write_reg32(registers.REG_CPU_PC, 0x0000)
            
            # Load all 17 test instructions into memory (PC 0-16)
            for i, test in enumerate(ALU_TESTS):
                # Write instruction to memory at address i
                self.driver.write_reg32(registers.REG_CPU_MEM_ADDR, i)
                self.driver.write_reg32(registers.REG_CPU_MEM_WDATA, test.instruction)
                self.driver.write_reg32(registers.REG_CPU_MEM_CTRL, 0x00000001)  # Write request
                time.sleep(0.002)
                
                # Setup registers for this test
                for reg_idx, value in test.setup:
                    self.write_register(reg_idx, value)
                
                print(f"    [{i:2d}] {test.name}: insn=0x{test.instruction:04X}", end="")
                if test.setup:
                    setup_str = ", ".join([f"R{r}=0x{v:04X}" for r, v in test.setup])
                    print(f" ({setup_str})")
                else:
                    print()
            
            print(f"    ✓ Loaded {len(ALU_TESTS)} test instructions")
            
            # ============================================================
            # Phase 3: Execute test batch
            # ============================================================
            print(f"\n{Colors.CYAN}[Phase 3/4] Executing test batch...{Colors.END}")
            
            # Set PC=0 and execute 17 STEP commands
            self.driver.write_reg32(registers.REG_CPU_PC, 0x0000)
            for i in range(len(ALU_TESTS)):
                # STEP command (bit 2 of CPU_DBG_CTRL)
                self.driver.write_reg32(registers.REG_CPU_DBG_CTRL, 0x00000004)
                time.sleep(0.01)  # Allow instruction execution
            
            # Wait for pipeline drain
            time.sleep(0.1)
            
            trace_count = self.read_trace_count()
            print(f"    ✓ Executed {len(ALU_TESTS)} instructions, trace entries: {trace_count}")
            
            # ============================================================
            # Phase 4: Validate results from trace buffer
            # ============================================================
            print(f"\n{Colors.CYAN}[Phase 4/4] Validating results...{Colors.END}\n")
            
            for i, test in enumerate(ALU_TESTS):
                try:
                    if i >= trace_count:
                        result = {
                            'passed': False,
                            'message': f"✗ No trace entry (count={trace_count})"
                        }
                    else:
                        # Read trace entry
                        insn_trace, result_trace = self.read_trace_entry(i)
                        
                        # Validate instruction match
                        if insn_trace != test.instruction:
                            result = {
                                'passed': False,
                                'message': f"✗ Instruction mismatch: trace=0x{insn_trace:04X}, expected=0x{test.instruction:04X}"
                            }
                        else:
                            # Compare result
                            if result_trace == test.expected_result:
                                result = {
                                    'passed': True,
                                    'message': f"✓ PASS: result=0x{result_trace:04X}"
                                }
                            else:
                                result = {
                                    'passed': False,
                                    'message': f"✗ FAIL: result=0x{result_trace:04X}, expected=0x{test.expected_result:04X}"
                                }
                    
                    # Print result
                    print(f"[{i+1:2d}/{len(ALU_TESTS)}] {test.name:25s} ", end="")
                    if result['passed']:
                        print(f"{Colors.GREEN}{result['message']}{Colors.END}")
                    else:
                        print(f"{Colors.RED}{result['message']}{Colors.END}")
                    
                    self.results.append(result)
                    
                except Exception as e:
                    error_msg = f"✗ ERROR: {str(e)}"
                    print(f"[{i+1:2d}/{len(ALU_TESTS)}] {test.name:25s} {Colors.RED}{error_msg}{Colors.END}")
                    self.results.append({
                        'passed': False,
                        'error': str(e),
                        'message': error_msg
                    })
        
        except Exception as e:
            print(f"\n{Colors.RED}Fatal error during test execution: {e}{Colors.END}")
            import traceback
            traceback.print_exc()
        
        elapsed = time.time() - start_time
        
        # Print summary
        self.print_summary(elapsed)
        
    def print_summary(self, elapsed_time: float):
        """Print test summary"""
        passed = sum(1 for r in self.results if r.get('passed', False))
        failed = len(self.results) - passed
        
        print(f"\n{Colors.HEADER}{'='*70}{Colors.END}")
        print(f"{Colors.BOLD}Test Summary{Colors.END}")
        print(f"{Colors.HEADER}{'='*70}{Colors.END}")
        
        print(f"Total Tests:  {len(self.results)}")
        print(f"{Colors.GREEN}Passed:       {passed}{Colors.END}")
        if failed > 0:
            print(f"{Colors.RED}Failed:       {failed}{Colors.END}")
        else:
            print(f"Failed:       {failed}")
        print(f"Elapsed Time: {elapsed_time:.2f}s")
        
        if failed == 0:
            print(f"\n{Colors.GREEN}{Colors.BOLD}*** ALL TESTS PASSED ***{Colors.END}")
        else:
            print(f"\n{Colors.RED}{Colors.BOLD}*** SOME TESTS FAILED ***{Colors.END}")
            print(f"\nFailed tests:")
            for idx, (test, result) in enumerate(zip(ALU_TESTS, self.results), 1):
                if not result.get('passed', False):
                    print(f"  [{idx}] {test.name}: {result.get('message', 'Unknown error')}")


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='TD4 CPU Hardware Test Runner',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python cpu_test_runner.py --port COM3
  python cpu_test_runner.py --port /dev/ttyUSB0 --baudrate 115200
  python cpu_test_runner.py --port COM3 --verbose
        """
    )
    parser.add_argument('--port', required=True, help='Serial port name')
    parser.add_argument('--baudrate', type=int, default=115200, help='Baud rate (default: 115200)')
    parser.add_argument('--timeout', type=float, default=2.0, help='Timeout in seconds (default: 2.0)')
    parser.add_argument('--verbose', action='store_true', help='Enable verbose logging')
    
    args = parser.parse_args()
    
    # Setup logging
    if args.verbose:
        logging.basicConfig(level=logging.DEBUG, format='%(levelname)s: %(message)s')
    else:
        logging.basicConfig(level=logging.WARNING, format='%(levelname)s: %(message)s')
    
    # Run tests
    runner = CPUTestRunner(args.port, args.baudrate, args.timeout)
    
    try:
        runner.open()
        runner.run_all_tests()
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Test interrupted by user{Colors.END}")
    except Exception as e:
        print(f"\n{Colors.RED}Fatal error: {e}{Colors.END}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)
    finally:
        runner.close()
    
    # Exit code reflects test results
    failed = sum(1 for r in runner.results if not r.get('passed', False))
    sys.exit(0 if failed == 0 else 1)


if __name__ == '__main__':
    main()
