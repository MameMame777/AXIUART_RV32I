#!/usr/bin/env python3
"""
RV32I CPU Hardware Test Runner

Real hardware validation tool for RV32I CPU over UART.
Executes comprehensive ISA test suite validated in UVM simulation.

Usage:
    python cpu_test_runner.py --port COM3
    python cpu_test_runner.py --port /dev/ttyUSB0 --suite alu
"""

import sys
import time
import argparse
from pathlib import Path
from typing import List

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from rv32i import RV32ICPUDriver
from rv32i.test_cases import ALL_TESTS, ALU_TESTS, IMMEDIATE_TESTS, MEMORY_TESTS, BRANCH_TESTS


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


class RV32ITestRunner:
    """Hardware test runner for RV32I CPU"""
    
    def __init__(self, port: str, baudrate: int = 115200, timeout: float = 2.0):
        """
        Initialize test runner
        
        Args:
            port: Serial port name (e.g., 'COM3' or '/dev/ttyUSB0')
            baudrate: UART baud rate
            timeout: Communication timeout in seconds
        """
        self.driver = RV32ICPUDriver(port, baudrate=baudrate, timeout=timeout)
        self.results = []
        
    def open(self):
        """Open UART connection"""
        self.driver.open()
        
    def close(self):
        """Close UART connection"""
        self.driver.close()
        
    def run_test(self, test) -> bool:
        """
        Run single test case
        
        Args:
            test: TestCase object
            
        Returns:
            True if test passed, False otherwise
        """
        print(f"\n[{len(self.results)+1}] {Colors.BOLD}{test.name}{Colors.END}")
        print(f"    {test.description}")
        print(f"    Program: {len(test.program)} instructions")
        
        try:
            # Load program
            self.driver.load_program(test.program)
            
            # Run CPU
            print(f"    Running CPU...")
            self.driver.run_cpu()
            
            # Wait for completion (EBREAK)
            if not self.driver.wait_for_breakpoint(timeout=test.timeout):
                print(f"    {Colors.RED}✗ TIMEOUT{Colors.END}")
                self.results.append((test.name, False, "Timeout"))
                return False
                
            # Check LED value
            actual_led = self.driver.read_led()
            expected_led = test.expected_led & 0xF  # LED is 4-bit
            
            if actual_led == expected_led:
                print(f"    {Colors.GREEN}✓ PASS{Colors.END}: LED={actual_led} (expected {expected_led})")
                self.results.append((test.name, True, None))
                return True
            else:
                print(f"    {Colors.RED}✗ FAIL{Colors.END}: LED={actual_led} (expected {expected_led})")
                self.results.append((test.name, False, f"LED mismatch: {actual_led} != {expected_led}"))
                return False
                
        except Exception as e:
            print(f"    {Colors.RED}✗ ERROR{Colors.END}: {e}")
            self.results.append((test.name, False, str(e)))
            return False
            
    def run_suite(self, tests: List):
        """Run test suite"""
        print("\n" + "="*70)
        print(f"{Colors.HEADER}{Colors.BOLD}RV32I CPU Hardware Validation Suite{Colors.END}")
        print(f"{len(tests)} Tests")
        print("="*70)
        
        start_time = time.time()
        
        for test in tests:
            self.run_test(test)
            
        elapsed = time.time() - start_time
        
        # Print summary
        passed = sum(1 for _, success, _ in self.results if success)
        failed = len(self.results) - passed
        
        print("\n" + "="*70)
        print(f"{Colors.BOLD}Test Summary{Colors.END}")
        print("="*70)
        print(f"Total Tests:  {len(self.results)}")
        print(f"Passed:       {Colors.GREEN}{passed}{Colors.END}")
        print(f"Failed:       {Colors.RED}{failed}{Colors.END}")
        print(f"Elapsed Time: {elapsed:.2f}s")
        print()
        
        if failed == 0:
            print(f"{Colors.GREEN}{Colors.BOLD}*** ALL TESTS PASSED ***{Colors.END}")
        else:
            print(f"{Colors.RED}{Colors.BOLD}*** SOME TESTS FAILED ***{Colors.END}")
            print(f"\n{Colors.YELLOW}Failed Tests:{Colors.END}")
            for name, success, error in self.results:
                if not success:
                    print(f"  - {name}: {error}")
                    
        return failed == 0


def main():
    parser = argparse.ArgumentParser(description='RV32I CPU Hardware Test Runner')
    parser.add_argument('--port', required=True, help='Serial port (e.g., COM3 or /dev/ttyUSB0)')
    parser.add_argument('--baudrate', type=int, default=115200, help='UART baud rate')
    parser.add_argument('--suite', choices=['all', 'alu', 'imm', 'mem', 'branch'], 
                       default='all', help='Test suite to run')
    parser.add_argument('--verbose', action='store_true', help='Verbose output')
    
    args = parser.parse_args()
    
    # Select test suite
    if args.suite == 'alu':
        tests = ALU_TESTS
    elif args.suite == 'imm':
        tests = IMMEDIATE_TESTS
    elif args.suite == 'mem':
        tests = MEMORY_TESTS
    elif args.suite == 'branch':
        tests = BRANCH_TESTS
    else:
        tests = ALL_TESTS
        
    # Run tests
    runner = RV32ITestRunner(args.port, baudrate=args.baudrate)
    runner.open()
    
    try:
        success = runner.run_suite(tests)
        sys.exit(0 if success else 1)
    finally:
        runner.close()


if __name__ == '__main__':
    main()
