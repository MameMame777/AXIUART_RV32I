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
                print(f"  ✓ PASS ({result['duration']:.1f}s)")
            elif result['status'] == 'FAIL':
                failed += 1
                print(f"  ✗ FAIL ({result['duration']:.1f}s)")
                print(f"    Error: {result['error']}")
                
                if stop_on_failure:
                    print(f"\n⚠ Stopping on failure (--stop-on-failure enabled)")
                    break
            else:
                skipped += 1
                print(f"  ⊘ SKIP - {result['error']}")
        
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
                
                # Check for errors in MCP response
                if output.get('status') == 'error':
                    return {
                        'test': test_name,
                        'status': 'FAIL',
                        'duration': duration,
                        'error': output.get('message', 'Unknown error'),
                        'exit_code': output.get('exit_code', result.returncode)
                    }
                
                # Parse inner result (DSIM execution result)
                if 'result' in output:
                    inner_result = json.loads(output['result'])
                    
                    if inner_result.get('status') == 'success':
                        return {
                            'test': test_name,
                            'status': 'PASS',
                            'duration': duration,
                            'log_file': inner_result.get('log_file', ''),
                            'seed': inner_result.get('seed', 1)
                        }
                    else:
                        return {
                            'test': test_name,
                            'status': 'FAIL',
                            'duration': duration,
                            'error': inner_result.get('error', 'Test failed'),
                            'log_file': inner_result.get('log_file', '')
                        }
                
                # Fallback: check exit code
                if result.returncode == 0:
                    return {
                        'test': test_name,
                        'status': 'PASS',
                        'duration': duration
                    }
                else:
                    return {
                        'test': test_name,
                        'status': 'FAIL',
                        'duration': duration,
                        'error': f"Non-zero exit code: {result.returncode}",
                        'stdout': result.stdout[:500],
                        'stderr': result.stderr[:500]
                    }
                    
            except json.JSONDecodeError:
                # Not JSON output - check exit code
                if result.returncode == 0:
                    return {
                        'test': test_name,
                        'status': 'PASS',
                        'duration': duration
                    }
                else:
                    return {
                        'test': test_name,
                        'status': 'FAIL',
                        'duration': duration,
                        'error': 'Failed to parse output',
                        'stdout': result.stdout[:500],
                        'stderr': result.stderr[:500]
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
            <th>Details</th>
        </tr>
"""
        
        for idx, result in enumerate(self.results, 1):
            status_class = result['status'].lower()
            details = result.get('error', '') if result['status'] == 'FAIL' else ''
            
            html += f"""        <tr>
            <td>{idx}</td>
            <td>{result['test']}</td>
            <td>{result.get('description', '')}</td>
            <td class="{status_class}">{result['status']}</td>
            <td>{result['duration']:.1f}s</td>
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
    
    parser.add_argument(
        '--suite',
        type=str,
        default='smoke',
        help='Test suite to run (smoke, register, cpu, full)'
    )
    
    parser.add_argument(
        '--stop-on-failure',
        action='store_true',
        help='Stop execution on first test failure'
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
        summary = runner.run_suite(args.suite, args.stop_on_failure)
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
