# Regression Test System

CI/CD integration ready regression test framework for AXIUART UVM testbench.

## Features

- **JSON-based test suite definition** - Easy to maintain and version control
- **Multiple test suites** - smoke, register, cpu, full
- **Multiple report formats** - JSON, HTML, JUnit XML
- **CI/CD ready** - Jenkins, GitHub Actions, GitLab CI compatible
- **MCP integration** - Can be invoked via MCP tools
- **Configurable timeouts** - Per-test timeout configuration
- **Stop-on-failure** - Optional early termination

## Test Suites

### Smoke Suite (Quick validation)
- `axiuart_reset_test` - Reset behavior verification (~10s)
- `axiuart_basic_test` - Basic UART transactions (~30s)

**Total duration: ~40 seconds**

### Register Suite
- `axiuart_reg_rw_test` - Register read/write operations (~45s)

**Total duration: ~45 seconds**

### CPU Suite (Comprehensive)
- `axiuart_cpu_simple_mem_test` - Simple CPU memory operations (~60s)
- `axiuart_cpu_memory_test` - Comprehensive memory test (~180s)
- `axiuart_cpu_debug_test` - Debug interface test (~90s)

**Total duration: ~330 seconds (5.5 minutes)**

### Full Suite (Complete regression)
All tests from smoke, register, and cpu suites.

**Total duration: ~415 seconds (7 minutes)**

## Configuration

Test suites are defined in [`regression_tests.json`](../sim/regression_tests.json):

```json
{
  "regression_suites": {
    "smoke": {
      "description": "Quick smoke tests",
      "tests": [
        {
          "name": "axiuart_reset_test",
          "description": "Verify reset behavior",
          "timeout": 60,
          "expected_duration": 10
        }
      ]
    }
  },
  "default_config": {
    "verbosity": "UVM_LOW",
    "waves": false,
    "coverage": false
  }
}
```

## Usage

### Command Line

```bash
# Run smoke suite (quick validation)
python mcp_server/run_regression.py --suite smoke

# Run full regression with HTML report
python mcp_server/run_regression.py --suite full --format html

# Stop on first failure
python mcp_server/run_regression.py --suite smoke --stop-on-failure

# Generate JUnit XML for Jenkins
python mcp_server/run_regression.py --suite full --format junit
```

### Via MCP Tool

```bash
# Using MCP client
python mcp_server/mcp_client.py --workspace . --tool run_regression_suite --suite smoke

# With custom options
python mcp_server/mcp_client.py --workspace . --tool run_regression_suite \
    --suite full --stop-on-failure --report-format html
```

### From VS Code

Add task to `.vscode/tasks.json`:

```json
{
    "label": "Run Regression (Smoke)",
    "type": "shell",
    "command": "python",
    "args": [
        "mcp_server/run_regression.py",
        "--suite", "smoke",
        "--format", "html"
    ],
    "problemMatcher": []
}
```

## Reports

Reports are generated in `sim/reports/`:

- **JSON**: `regression_report_YYYYMMDD_HHMMSS.json`
- **HTML**: `regression_report_YYYYMMDD_HHMMSS.html`
- **JUnit XML**: `regression_report_YYYYMMDD_HHMMSS.xml`

### JSON Report Structure

```json
{
  "start_time": "2025-12-28T10:00:00",
  "end_time": "2025-12-28T10:01:30",
  "duration": 90.5,
  "results": [
    {
      "test": "axiuart_reset_test",
      "description": "Verify reset behavior",
      "status": "PASS",
      "duration": 12.3,
      "log_file": "sim/exec/logs/axiuart_reset_test_20251228_100000.log"
    }
  ],
  "summary": {
    "total": 6,
    "passed": 5,
    "failed": 1,
    "skipped": 0,
    "pass_rate": 83.3
  }
}
```

## CI/CD Integration

### Jenkins Pipeline

```groovy
pipeline {
    agent any
    
    stages {
        stage('Regression Tests') {
            steps {
                script {
                    // Run full regression
                    sh '''
                        python mcp_server/run_regression.py \
                            --suite full \
                            --format junit \
                            --output-dir test-results
                    '''
                }
            }
        }
    }
    
    post {
        always {
            // Publish JUnit results
            junit 'test-results/regression_report_*.xml'
            
            // Archive HTML report
            publishHTML([
                reportDir: 'sim/reports',
                reportFiles: 'regression_report_*.html',
                reportName: 'Regression Test Report'
            ])
        }
    }
}
```

### GitHub Actions

```yaml
name: Regression Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup DSIM
        run: |
          # Install DSIM and configure license
          
      - name: Run Smoke Tests
        run: |
          python mcp_server/run_regression.py \
            --suite smoke \
            --format junit
      
      - name: Publish Test Results
        uses: EnricoMi/publish-unit-test-result-action@v2
        if: always()
        with:
          files: sim/reports/regression_report_*.xml
      
      - name: Upload Report
        uses: actions/upload-artifact@v3
        with:
          name: regression-report
          path: sim/reports/
```

### GitLab CI

```yaml
regression_test:
  stage: test
  script:
    - python mcp_server/run_regression.py --suite full --format junit
  artifacts:
    reports:
      junit: sim/reports/regression_report_*.xml
    paths:
      - sim/reports/
    when: always
  only:
    - main
    - merge_requests
```

## Adding New Tests

1. Add test to testbench:
   ```systemverilog
   // sim/tests/my_new_test.sv
   class my_new_test extends axiuart_base_test;
       `uvm_component_utils(my_new_test)
       // ... implementation
   endclass
   ```

2. Add to suite in `regression_tests.json`:
   ```json
   {
     "name": "my_new_test",
     "description": "Description of test",
     "timeout": 120,
     "expected_duration": 30
   }
   ```

3. Run regression to verify:
   ```bash
   python mcp_server/run_regression.py --suite full
   ```

## Timeout Configuration

Tests have two timeout values:

- **`timeout`**: Maximum execution time (test fails if exceeded)
- **`expected_duration`**: Normal execution time (for scheduling/monitoring)

Adjust timeouts based on:
- Test complexity
- Number of transactions
- Waveform dumping enabled/disabled
- Coverage collection

## Best Practices

### Test Development
1. Always add new tests to a suite
2. Set realistic timeouts (2-3x expected duration)
3. Use UVM_LOW verbosity for regression (faster)
4. Disable waves for regression (enable for debug)

### CI/CD
1. Run smoke suite on every commit (~40s)
2. Run full suite on PR merge (~7min)
3. Generate HTML report for review
4. Use JUnit XML for result tracking
5. Archive reports as build artifacts

### Debugging Failures
1. Check HTML report for overview
2. Review individual test logs in `sim/exec/logs/`
3. Re-run single test with UVM_MEDIUM + waves:
   ```bash
   python mcp_server/mcp_client.py --workspace . \
       --tool run_uvm_simulation \
       --test-name axiuart_cpu_memory_test \
       --mode run --verbosity UVM_MEDIUM --waves
   ```

## Exit Codes

- **0**: All tests passed
- **1**: One or more tests failed or error occurred

Used by CI/CD systems to mark build status.

## Performance

Typical execution times:

| Suite | Tests | Duration | Use Case |
|-------|-------|----------|----------|
| smoke | 2 | ~40s | Quick validation, pre-commit |
| register | 1 | ~45s | Register interface validation |
| cpu | 3 | ~330s | CPU functionality validation |
| full | 6 | ~415s | Complete validation, nightly |

Times measured without waveform dumping on typical development machine.

## Troubleshooting

### License Issues
```
Error: DSIM license not obtained
```
- Check `DSIM_LICENSE` environment variable
- Verify license server is running
- Kill any hanging DSIM processes: `Get-Process dsim* | Stop-Process -Force`

### Test Timeouts
```
Status: FAIL - Timeout after 120s
```
- Increase timeout in `regression_tests.json`
- Check test is not hanging (deadlock, infinite loop)
- Review test log for stuck phase

### Report Not Generated
```
Error: Config file not found
```
- Ensure `sim/regression_tests.json` exists
- Check `--workspace` path is correct
- Verify Python can access filesystem

## Future Enhancements

- [ ] Parallel test execution (`--parallel` flag)
- [ ] Test result trending over time
- [ ] Coverage aggregation across suite
- [ ] Email notification on failure
- [ ] Slack/Discord integration
- [ ] Test retry on transient failures
- [ ] Resource usage monitoring (CPU, memory)
