#!/usr/bin/env python3
"""
Regression Test Runner for AXIUART UVM Testbench
Executes test suites defined in regression_tests.json and generates reports
Designed for local execution and CI/CD integration (Jenkins, GitHub Actions, etc.)
"""

import json
import subprocess
import sys
import time
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple
import argparse


class RegressionRunner:
    """Manages regression test execution and reporting"""
    
    def __init__(self, workspace: Path, config_file: Path):
        self.workspace = workspace
        self.config_file = config_file
        self.results = []
        self.start_time = None
        self.end_time = None
        
        # Load test configuration
        with open(config_file, 'r') as f:
            self.config = json.load(f)
    
    def run_single_test_standalone(self, test_name: str) -> Dict:
        """
        Run a single test by name (not part of a suite)
        
        Args:
            test_name: Name of the test to run
            
        Returns:
            Summary dictionary with pass/fail counts
        """
        default_config = self.config['default_config']
        
        print(f"\n{'='*80}")
        print(f"Running Single Test: {test_name}")
        print(f"{'='*80}\n")
        
        self.start_time = datetime.now()
        self.results = []
        
        result = self._run_single_test(
            test_name=test_name,
            verbosity=default_config['verbosity'],
            waves=default_config['waves'],
            coverage=default_config['coverage']
        )
        
        result['description'] = f"Standalone execution of {test_name}"
        result['expected_duration'] = 0
        self.results.append(result)
        
        if result['status'] == 'PASS':
            print(f"  [PASS] ({result['duration']:.1f}s)")
        elif result['status'] == 'FAIL':
            print(f"  [FAIL] ({result['duration']:.1f}s)")
            print(f"    Error: {result['error']}")
        else:
            print(f"  [SKIP] - {result['error']}")
        
        self.end_time = datetime.now()
        
        summary = {
            'suite': f"single_test_{test_name}",
            'total': 1,
            'passed': 1 if result['status'] == 'PASS' else 0,
            'failed': 1 if result['status'] == 'FAIL' else 0,
            'skipped': 1 if result['status'] not in ('PASS', 'FAIL') else 0,
            'duration': (self.end_time - self.start_time).total_seconds(),
            'timestamp': self.start_time.isoformat()
        }
        
        return summary
    
    def run_suite(self, suite_name: str, stop_on_failure: bool = False) -> Dict:
        """
        Run a test suite
        
        Args:
            suite_name: Name of suite from regression_tests.json
            stop_on_failure: Stop execution on first failure
            
        Returns:
            Summary dictionary with pass/fail counts
        """
        if suite_name not in self.config['regression_suites']:
            raise ValueError(f"Unknown suite: {suite_name}. Available: {list(self.config['regression_suites'].keys())}")
        
        suite = self.config['regression_suites'][suite_name]
        default_config = self.config['default_config']
        
        print(f"\n{'='*80}")
        print(f"Running Regression Suite: {suite_name}")
        print(f"Description: {suite['description']}")
        print(f"Tests: {len(suite['tests'])}")
        print(f"{'='*80}\n")
        
        self.start_time = datetime.now()
        self.results = []
        
        passed = 0
        failed = 0
        skipped = 0
        
        for idx, test in enumerate(suite['tests'], 1):
            test_name = test['name']
            
            print(f"\n[{idx}/{len(suite['tests'])}] Running: {test_name}")
            print(f"  Description: {test['description']}")
            
            result = self._run_single_test(
                test_name=test_name,
                verbosity=default_config['verbosity'],
                waves=default_config['waves'],
                coverage=default_config['coverage']
            )
            
            result['description'] = test['description']
            result['expected_duration'] = test.get('expected_duration', 0)
            self.results.append(result)
            
            if result['status'] == 'PASS':
                passed += 1
                print(f"  [PASS] ({result['duration']:.1f}s)")
            elif result['status'] == 'FAIL':
                failed += 1
                print(f"  [FAIL] ({result['duration']:.1f}s)")
                print(f"    Error: {result['error']}")
                
                if stop_on_failure:
                    print(f"\n[WARNING] Stopping on failure (--stop-on-failure enabled)")
                    break
            else:
                skipped += 1
                print(f"  [SKIP] - {result['error']}")
        
        self.end_time = datetime.now()
        
        summary = {
            'suite': suite_name,
            'total': len(self.results),
            'passed': passed,
            'failed': failed,
            'skipped': skipped,
            'duration': (self.end_time - self.start_time).total_seconds(),
            'timestamp': self.start_time.isoformat()
        }
        
        return summary
    
    def _run_single_test(
        self,
        test_name: str,
        verbosity: str,
        waves: bool,
        coverage: bool
    ) -> Dict:
        """
        Run a single test without timeout (prevents license issues)
        
        Returns:
            Dictionary with test result
        """
        start = time.time()
        
        # Build command
        cmd = [
            sys.executable,
            str(self.workspace / 'mcp_server' / 'mcp_client.py'),
            '--workspace', str(self.workspace),
            '--tool', 'run_uvm_simulation',
            '--test-name', test_name,
            '--mode', 'run',
            '--verbosity', verbosity
        ]
        
        if not waves:
            cmd.append('--no-waves')
        
        if coverage:
            cmd.append('--coverage')
        
        # Execute test (no timeout - prevent license issues from interrupted processes)
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=None,  # No timeout - let tests run to completion
                cwd=str(self.workspace),
                encoding='utf-8',
                errors='replace'
            )
            
            duration = time.time() - start
            
            # Parse JSON output from MCP client
            try:
                output = json.loads(result.stdout)
                
                # MCP client directly returns the tool result (dsim_uvm_server response)
                # Check status field directly
                test_status = output.get('status', 'unknown')
                
                # DEBUG: Print status for verification
                uvm_errors = output.get('uvm_error_count', 0)
                print(f"  DEBUG: {test_name} - status = {test_status}, uvm_error_count = {uvm_errors}")
                
                # Only 'success' means PASS - everything else is FAIL
                if test_status == 'success' and uvm_errors == 0:
                    return {
                        'test': test_name,
                        'status': 'PASS',
                        'duration': duration,
                        'log_file': output.get('log_file', ''),
                        'log_file_absolute': output.get('log_file_absolute', ''),
                        'seed': output.get('seed', 1)
                    }
                else:
                    # Any non-success status or errors means FAIL
                    error_msg = output.get('error', '')
                    if not error_msg:
                        if uvm_errors > 0:
                            error_msg = f"Test has {uvm_errors} UVM errors"
                        elif test_status == 'failure':
                            error_msg = "Test failed"
                        else:
                            error_msg = f"Test status: {test_status}"
                    
                    return {
                        'test': test_name,
                        'status': 'FAIL',
                        'duration': duration,
                        'error': error_msg,
                        'log_file': output.get('log_file', ''),
                        'log_file_absolute': output.get('log_file_absolute', '')
                    }
                    
            except json.JSONDecodeError:
                # Not JSON output - likely execution error
                return {
                    'test': test_name,
                    'status': 'FAIL',
                    'duration': duration,
                    'error': f"Failed to parse test output (exit code: {result.returncode})",
                    'stdout': result.stdout[:500] if result.stdout else '',
                    'stderr': result.stderr[:500] if result.stderr else ''
                }
        
        except Exception as e:
            duration = time.time() - start
            return {
                'test': test_name,
                'status': 'FAIL',
                'duration': duration,
                'error': f'Exception: {str(e)}'
            }
    
    def generate_report(self, output_dir: Path, format: str = 'json') -> Path:
        """
        Generate test report
        
        Args:
            output_dir: Directory for report output
            format: 'json', 'html', or 'junit'
            
        Returns:
            Path to generated report file
        """
        output_dir.mkdir(parents=True, exist_ok=True)
        timestamp = self.start_time.strftime('%Y%m%d_%H%M%S')
        
        if format == 'json':
            report_file = output_dir / f'regression_report_{timestamp}.json'
            report_data = {
                'start_time': self.start_time.isoformat(),
                'end_time': self.end_time.isoformat(),
                'duration': (self.end_time - self.start_time).total_seconds(),
                'results': self.results,
                'summary': self._calculate_summary()
            }
            
            with open(report_file, 'w') as f:
                json.dump(report_data, f, indent=2)
            
            return report_file
        
        elif format == 'html':
            report_file = output_dir / f'regression_report_{timestamp}.html'
            html_content = self._generate_html_report()
            
            with open(report_file, 'w', encoding='utf-8') as f:
                f.write(html_content)
            
            return report_file
        
        elif format == 'junit':
            report_file = output_dir / f'regression_report_{timestamp}.xml'
            xml_content = self._generate_junit_xml()
            
            with open(report_file, 'w', encoding='utf-8') as f:
                f.write(xml_content)
            
            return report_file
        
        else:
            raise ValueError(f"Unknown format: {format}")
    
    def _calculate_summary(self) -> Dict:
        """Calculate summary statistics"""
        total = len(self.results)
        passed = sum(1 for r in self.results if r['status'] == 'PASS')
        failed = sum(1 for r in self.results if r['status'] == 'FAIL')
        skipped = total - passed - failed
        
        return {
            'total': total,
            'passed': passed,
            'failed': failed,
            'skipped': skipped,
            'pass_rate': (passed / total * 100) if total > 0 else 0
        }
    
    def _generate_html_report(self) -> str:
        """Generate HTML report"""
        summary = self._calculate_summary()
        
        html = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Regression Test Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; }}
        h1 {{ color: #333; }}
        .summary {{ background: #f0f0f0; padding: 15px; border-radius: 5px; margin: 20px 0; }}
        .summary-item {{ display: inline-block; margin-right: 30px; }}
        table {{ border-collapse: collapse; width: 100%; margin-top: 20px; }}
        th, td {{ border: 1px solid #ddd; padding: 12px; text-align: left; }}
        th {{ background-color: #4CAF50; color: white; }}
        tr:nth-child(even) {{ background-color: #f2f2f2; }}
        .pass {{ color: green; font-weight: bold; }}
        .fail {{ color: red; font-weight: bold; }}
        .skip {{ color: orange; font-weight: bold; }}
        a {{ color: #0066cc; text-decoration: none; }}
        a:hover {{ text-decoration: underline; }}
    </style>
</head>
<body>
    <h1>Regression Test Report</h1>
    <div class="summary">
        <div class="summary-item"><strong>Date:</strong> {self.start_time.strftime('%Y-%m-%d %H:%M:%S')}</div>
        <div class="summary-item"><strong>Duration:</strong> {(self.end_time - self.start_time).total_seconds():.1f}s</div>
        <div class="summary-item"><strong>Total:</strong> {summary['total']}</div>
        <div class="summary-item"><strong>Passed:</strong> <span class="pass">{summary['passed']}</span></div>
        <div class="summary-item"><strong>Failed:</strong> <span class="fail">{summary['failed']}</span></div>
        <div class="summary-item"><strong>Pass Rate:</strong> {summary['pass_rate']:.1f}%</div>
    </div>
    
    <h2>Test Results</h2>
    <table>
        <tr>
            <th>#</th>
            <th>Test Name</th>
            <th>Description</th>
            <th>Status</th>
            <th>Duration</th>
            <th>Log File</th>
            <th>Details</th>
        </tr>
"""
        
        for idx, result in enumerate(self.results, 1):
            status_class = result['status'].lower()
            details = result.get('error', '') if result['status'] == 'FAIL' else ''
            log_file = result.get('log_file', '')
            
            # Generate log link if available
            log_link = ''
            if log_file:
                # log_file from MCP server is relative to sim/uvm/ like "../../exec/logs/test.log"
                # Reports are in sim/reports/, so we need to convert the path
                
                # Check for absolute path in log_file_absolute field
                log_file_abs = result.get('log_file_absolute', '')
                if log_file_abs:
                    log_path = Path(log_file_abs)
                    if log_path.exists():
                        # Make path relative to sim/reports/
                        try:
                            rel_path = log_path.relative_to(self.workspace / 'sim' / 'reports')
                            log_link = f'<a href="{rel_path}" target="_blank">View Log</a>'
                        except ValueError:
                            # Make relative to workspace, then adjust for reports directory
                            try:
                                rel_path = log_path.relative_to(self.workspace)
                                # From sim/reports/ to log file - normalize path separators for HTML
                                rel_path_str = str(rel_path).replace('\\', '/')
                                log_link = f'<a href="../{rel_path_str}" target="_blank">View Log</a>'
                            except ValueError:
                                # Fallback: use absolute path
                                log_link = f'<a href="file:///{log_file_abs.replace(chr(92), "/")}" target="_blank">View Log</a>'
                    else:
                        log_link = f'<span style="color: gray;">{log_path.name} (not found)</span>'
                else:
                    # Fallback to log_file field - extract filename
                    log_filename = Path(log_file).name
                    log_link = f'<span style="color: gray;">{log_filename}</span>'
            
            html += f"""        <tr>
            <td>{idx}</td>
            <td>{result['test']}</td>
            <td>{result.get('description', '')}</td>
            <td class="{status_class}">{result['status']}</td>
            <td>{result['duration']:.1f}s</td>
            <td>{log_link}</td>
            <td>{details}</td>
        </tr>
"""
        
        html += """    </table>
</body>
</html>
"""
        return html
    
    def _generate_junit_xml(self) -> str:
        """Generate JUnit XML report for CI/CD integration"""
        summary = self._calculate_summary()
        duration = (self.end_time - self.start_time).total_seconds()
        
        xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<testsuites tests="{summary['total']}" failures="{summary['failed']}" time="{duration:.3f}">
    <testsuite name="AXIUART_Regression" tests="{summary['total']}" failures="{summary['failed']}" time="{duration:.3f}">
"""
        
        for result in self.results:
            test_name = result['test']
            duration = result['duration']
            
            if result['status'] == 'PASS':
                xml += f'        <testcase name="{test_name}" time="{duration:.3f}"/>\n'
            else:
                error_msg = result.get('error', 'Unknown error')
                xml += f'        <testcase name="{test_name}" time="{duration:.3f}">\n'
                xml += f'            <failure message="{error_msg}"/>\n'
                xml += f'        </testcase>\n'
        
        xml += """    </testsuite>
</testsuites>
"""
        return xml
    
    def print_summary(self, summary: Dict):
        """Print test summary to console"""
        print(f"\n{'='*80}")
        print("REGRESSION TEST SUMMARY")
        print(f"{'='*80}")
        print(f"Suite:        {summary['suite']}")
        print(f"Total Tests:  {summary['total']}")
        print(f"Passed:       {summary['passed']}")
        print(f"Failed:       {summary['failed']}")
        print(f"Skipped:      {summary['skipped']}")
        print(f"Duration:     {summary['duration']:.1f}s")
        print(f"Pass Rate:    {(summary['passed']/summary['total']*100 if summary['total'] > 0 else 0):.1f}%")
        print(f"{'='*80}\n")


def main():
    parser = argparse.ArgumentParser(
        description='Run AXIUART regression test suite',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run smoke test suite
  python run_regression.py --suite smoke
  
  # Run full regression with HTML report
  python run_regression.py --suite full --format html
  
  # Stop on first failure
  python run_regression.py --suite smoke --stop-on-failure
  
  # Generate JUnit XML for Jenkins
  python run_regression.py --suite full --format junit
"""
    )
    
    parser.add_argument(
        '--workspace',
        type=Path,
        default=Path(__file__).parent.parent,
        help='Workspace root directory'
    )
    
    parser.add_argument(
        '--config',
        type=Path,
        help='Regression test configuration file (default: sim/regression_tests.json)'
    )
    
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        '--suite',
        type=str,
        help='Test suite to run (smoke, register, cpu, full)'
    )
    
    group.add_argument(
        '--test',
        type=str,
        help='Run a single test by name (e.g., axiuart_cpu_simple_mem_test)'
    )
    
    parser.add_argument(
        '--stop-on-failure',
        action='store_true',
        help='Stop execution on first test failure (only applies to --suite)'
    )
    
    parser.add_argument(
        '--format',
        type=str,
        choices=['json', 'html', 'junit'],
        default='json',
        help='Report format'
    )
    
    parser.add_argument(
        '--output-dir',
        type=Path,
        help='Report output directory (default: sim/reports)'
    )
    
    args = parser.parse_args()
    
    # Set defaults
    if args.config is None:
        args.config = args.workspace / 'sim' / 'regression_tests.json'
    
    if args.output_dir is None:
        args.output_dir = args.workspace / 'sim' / 'reports'
    
    # Validate inputs
    if not args.workspace.exists():
        print(f"Error: Workspace not found: {args.workspace}")
        return 1
    
    if not args.config.exists():
        print(f"Error: Config file not found: {args.config}")
        return 1
    
    # Run regression
    try:
        runner = RegressionRunner(args.workspace, args.config)
        
        # Run either suite or single test
        if args.suite:
            summary = runner.run_suite(args.suite, args.stop_on_failure)
        else:  # args.test is set
            summary = runner.run_single_test_standalone(args.test)
        
        runner.print_summary(summary)
        
        # Generate report
        report_file = runner.generate_report(args.output_dir, args.format)
        print(f"Report generated: {report_file}")
        
        # Exit with appropriate code
        return 0 if summary['failed'] == 0 else 1
    
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
