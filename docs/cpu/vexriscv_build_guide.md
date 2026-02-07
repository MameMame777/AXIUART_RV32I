# VexRiscv GenSmallOptimized - Build Guide

**Version:** 1.0  
**Date:** 2026-02-07  
**Target:** Generate VexRiscv.v from SpinalHDL Scala configuration  
**Platform:** Windows 10/11 (PowerShell), adaptable to Linux

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Environment Setup](#environment-setup)
4. [Build Process](#build-process)
5. [Customization Guide](#customization-guide)
6. [Verification & Validation](#verification--validation)
7. [Troubleshooting](#troubleshooting)

---

## Overview

### What This Build Does

The VexRiscv build process transforms **SpinalHDL Scala code** into **synthesizable Verilog RTL**:

```
┌─────────────────────────────────────────────────────────┐
│ Input: GenSmallOptimized.scala                          │
│  - CPU configuration (plugins, parameters)              │
│  - Written in Scala/SpinalHDL                           │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ SpinalHDL Compiler (JVM-based)                          │
│  - Parses Scala code                                    │
│  - Elaborates hardware graph                            │
│  - Optimizes & flattens                                 │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ Output: VexRiscv.v                                      │
│  - ~4200 lines of Verilog                               │
│  - Synthesizable RTL for FPGA/ASIC                      │
│  - cpu.yaml (configuration metadata)                    │
└─────────────────────────────────────────────────────────┘
```

### Build Tools

| Tool | Purpose | Required Version |
|------|---------|------------------|
| **JDK** | Java Development Kit (runs Scala compiler) | 8, 11, or 17 |
| **sbt** | Scala Build Tool (dependency manager) | 1.5.0+ |
| **git** | Clone VexRiscv source repository | Any recent version |
| **PowerShell** | Run build scripts (Windows) | 5.1+ or PowerShell Core 7+ |

---

## Prerequisites

### Check Existing Installation

Run this PowerShell script to verify your environment:

```powershell
# tools/setup_vexriscv.ps1 -CheckOnly
.\tools\setup_vexriscv.ps1 -CheckOnly
```

**Expected Output:**
```
=== VexRiscv Build Environment Check ===
✓ Java found: java version "11.0.12"
✓ sbt found: sbt version 1.5.5
✓ VexRiscv source: e:\...\vexriscv_reference\source
✓ Environment ready
```

---

## Environment Setup

### Step 1: Install Java JDK

**Option A: Oracle JDK 11 (Recommended)**
1. Download from: https://www.oracle.com/java/technologies/javase-jdk11-downloads.html
2. Run installer (accept defaults)
3. Verify: `java -version` → Should show `java version "11.x.x"`

**Option B: OpenJDK 11 (Free Alternative)**
```powershell
# Using Chocolatey package manager
choco install openjdk11
```

**Option C: AdoptOpenJDK (Obsolete but works)**
1. Download from: https://adoptopenjdk.net/
2. Select: OpenJDK 11 (LTS), HotSpot JVM

**JAVA_HOME Setup:**
```powershell
# Add to system environment variables
$env:JAVA_HOME = "C:\Program Files\Java\jdk-11.0.12"
$env:PATH += ";$env:JAVA_HOME\bin"

# Persist (run as Administrator)
[Environment]::SetEnvironmentVariable("JAVA_HOME", "C:\Program Files\Java\jdk-11.0.12", "Machine")
```

---

### Step 2: Install sbt (Scala Build Tool)

**Option A: Direct Download (Simplest)**
1. Download MSI installer from: https://www.scala-sbt.org/download.html
2. Run installer (accept defaults)
3. Restart PowerShell
4. Verify: `sbt --version` → Should show `sbt version 1.x.x`

**Option B: Using Chocolatey**
```powershell
choco install sbt
```

**Manual Installation (if installers fail):**
1. Download zip from https://www.scala-sbt.org/download.html
2. Extract to `C:\sbt`
3. Add to PATH: `$env:PATH += ";C:\sbt\bin"`

**First Run (Downloads Dependencies):**
```powershell
# This will take 5-10 minutes first time
sbt about
```

---

### Step 3: Clone VexRiscv Source Repository

**Location:** Project uses a vendored VexRiscv source tree:

```powershell
cd e:\Nautilus\workspace\fpgawork\AXIUART_RV32I

# If vexriscv_reference\source doesn't exist:
git clone https://github.com/SpinalHDL/VexRiscv.git vexriscv_reference\source

# Optional: Lock to known-good commit
cd vexriscv_reference\source
git checkout 2130484fe93c04edc0f17a4991108fdef9db89b3
```

**Directory Structure After Setup:**
```
AXIUART_RV32I/
├── vexriscv_reference/
│   ├── config/
│   │   └── GenSmallOptimized.scala    ← Your custom config
│   ├── source/                        ← VexRiscv git repo
│   │   ├── src/
│   │   │   └── main/scala/vexriscv/
│   │   │       ├── VexRiscv.scala     ← Core CPU generator
│   │   │       ├── plugin/            ← Plugin implementations
│   │   │       └── demo/              ← Example configs
│   │   ├── build.sbt                  ← Scala build config
│   │   └── project/                   ← sbt settings
│   └── generated/                     ← Output directory
│       ├── VexRiscv.v                 ← Generated Verilog
│       └── cpu.yaml                   ← Configuration metadata
```

---

## Build Process

### Automated Build (Recommended)

**Primary Script:** `tools/build_vexriscv.ps1`

**Basic Usage:**
```powershell
cd e:\Nautilus\workspace\fpgawork\AXIUART_RV32I

# Generate RTL from GenSmallOptimized configuration
.\tools\build_vexriscv.ps1

# Clean previous build first
.\tools\build_vexriscv.ps1 -Clean

# Just verify environment (no build)
.\tools\build_vexriscv.ps1 -VerifyOnly
```

**Script Workflow:**
```
1. Verify environment (Java, sbt, VexRiscv source)
2. Copy config/GenSmallOptimized.scala → source/src/main/scala/vexriscv/demo/
3. Run sbt: "runMain vexriscv.demo.GenSmallOptimized vexriscv_reference/generated"
4. sbt downloads dependencies (first run only, ~5 min)
5. sbt compiles Scala → bytecode (~30s)
6. SpinalHDL elaborates → generates Verilog (~10s)
7. Verify outputs: VexRiscv.v, cpu.yaml
8. Check for required pipeline stages (decode/execute/memory/writeBack)
```

**Output:**
```
=== VexRiscv RTL Generator ===
Config: GenSmallOptimized
Output: vexriscv_reference\generated

Verifying build environment...
✓ Environment verification passed

Generating RTL with sbt...
[info] welcome to sbt 1.5.5
[info] loading project definition from ...
[info] compiling 1 Scala source to ...
[info] running vexriscv.demo.GenSmallOptimized vexriscv_reference/generated
VexRiscv GenSmallOptimized generated successfully in vexriscv_reference/generated/

Verifying generated files...
✓ VexRiscv.v generated (4180 lines)
  ✓ Stage found: decode
  ✓ Stage found: execute
  ✓ Stage found: memory
  ✓ Stage found: writeBack
  ✓ IBusSimplePlugin found (fetch/injection)
⚠ cpu.yaml is empty (VexRiscv YamlPlugin may not have generated data)
  This is non-fatal - RTL is still usable

=== RTL Generation Successful ===
```

---

### Manual Build (Step-by-Step)

For debugging or customization:

**Step 1: Copy Configuration**
```powershell
Copy-Item vexriscv_reference\config\GenSmallOptimized.scala `
          vexriscv_reference\source\src\main\scala\vexriscv\demo\GenSmallOptimized.scala `
          -Force
```

**Step 2: Run sbt**
```powershell
cd vexriscv_reference\source

# Interactive sbt shell
sbt

# In sbt shell:
> runMain vexriscv.demo.GenSmallOptimized ..\..\generated
```

**Step 3: Verify Output**
```powershell
Get-ChildItem ..\generated

# Check file size (should be ~150KB)
(Get-Item ..\generated\VexRiscv.v).Length / 1KB

# Count lines
(Get-Content ..\generated\VexRiscv.v).Count
```

**Step 4: Deploy to rtl/cpu/**
```powershell
Copy-Item vexriscv_reference\generated\VexRiscv.v rtl\cpu\VexRiscv.v -Force
```

---

## Customization Guide

### Editing GenSmallOptimized.scala

**File Location:** `vexriscv_reference/config/GenSmallOptimized.scala`

**Example Modifications:**

#### 1. Change Reset Vector

```scala
// Before
new IBusSimplePlugin(
  resetVector = 0x80000000l,
  // ...
)

// After (custom bootloader at 0x00000000)
new IBusSimplePlugin(
  resetVector = 0x00000000l,
  // ...
)
```

#### 2. Add Branch Prediction

```scala
// Before
new IBusSimplePlugin(
  prediction = NONE,
  // ...
)

// After
new IBusSimplePlugin(
  prediction = STATIC,  // or DYNAMIC
  // ...
)
```

#### 3. Enable Illegal Instruction Trap

```scala
// Before
new DecoderSimplePlugin(
  catchIllegalInstruction = false
)

// After
new DecoderSimplePlugin(
  catchIllegalInstruction = true  // Adds ~100 LUTs
)
```

#### 4. Add Hardware Breakpoints

```scala
// Before
new DebugPlugin(
  debugClockDomain = ClockDomain.current,
  hardwareBreakpointCount = 2
)

// After
new DebugPlugin(
  debugClockDomain = ClockDomain.current,
  hardwareBreakpointCount = 4  // More breakpoints
)
```

#### 5. Enable RV32M Extension (Multiply/Divide)

```scala
// Add to plugins list
new MulDivIterativePlugin(
  genMul = true,
  genDiv = true,
  mulUnrollFactor = 32,  // 1-cycle multiply
  divUnrollFactor = 1    // 32-cycle divide
)
```

**After Editing:** Rebuild with `.\tools\build_vexriscv.ps1 -Clean`

---

### Plugin Reference

**Common Plugins & Parameters:**

| Plugin | Key Parameters | Impact |
|--------|----------------|--------|
| `IBusSimplePlugin` | `resetVector`, `prediction`, `compressedGen` | Fetch behavior, reset PC, RV32C support |
| `RegFilePlugin` | `regFileReadyKind` (SYNC/ASYNC) | Timing, area (SYNC is safer) |
| `HazardSimplePlugin` | `bypassExecute`, `bypassMemory`, `bypassWriteBackBuffer` | Performance, hazard handling |
| `LightShifterPlugin` | (no params) | Multi-cycle shifts (low area) |
| `FullBarrelShifterPlugin` | (no params) | 1-cycle shifts (high area) |
| `MulDivIterativePlugin` | `genMul`, `genDiv`, `mulUnrollFactor` | RV32M extension |
| `CsrPlugin` | `CsrPluginConfig(...)` | CSRs, exceptions, interrupts |
| `DebugPlugin` | `hardwareBreakpointCount` | Debug capabilities |

**Area/Performance Trade-offs:**

- **Smallest Area:** GenSmallOptimized as-is (~1500 LUTs)
- **Best Performance:** FullBarrelShifter + Branch Prediction (~2500 LUTs, 1.2x IPC)
- **Linux-Capable:** Add MMU, CSR extensions, full exception handling (~5000 LUTs)

---

## Verification & Validation

### Generated File Checklist

**After successful build:**
```powershell
# 1. Check VexRiscv.v exists
Test-Path vexriscv_reference\generated\VexRiscv.v

# 2. Verify file size (typical: 140-160 KB)
(Get-Item vexriscv_reference\generated\VexRiscv.v).Length

# 3. Count lines (typical: 4000-4500)
(Get-Content vexriscv_reference\generated\VexRiscv.v).Count

# 4. Check for key signals
Select-String -Path vexriscv_reference\generated\VexRiscv.v -Pattern "decode_arbitration_isValid"
Select-String -Path vexriscv_reference\generated\VexRiscv.v -Pattern "IBusSimplePlugin"
Select-String -Path vexriscv_reference\generated\VexRiscv.v -Pattern "HazardSimplePlugin"
```

### Verilog Syntax Check

```powershell
# If you have Verilator installed
verilator --lint-only vexriscv_reference\generated\VexRiscv.v

# If you have Vivado
vivado -mode batch -source scripts/check_syntax.tcl

# If you have ModelSim/QuestaSim
vlog vexriscv_reference\generated\VexRiscv.v
```

### Regression Test

```powershell
# Run Stage 1 UVM tests to verify functionality
.\scripts\run_regression.ps1 -Stage 1 -Verbosity UVM_LOW
```

**Expected:** All 9 tests pass (regfile, pipeline, ALU, hazards, memory).

---

## Troubleshooting

### Problem 1: `java` not found

**Error:**
```
'java' is not recognized as an internal or external command
```

**Solution:**
```powershell
# Install JDK (see Step 1 in Environment Setup)
# Verify installation
java -version

# If installed but not found, add to PATH
$env:PATH += ";C:\Program Files\Java\jdk-11.0.12\bin"
```

---

### Problem 2: `sbt` not found

**Error:**
```
'sbt' is not recognized as an internal or external command
```

**Solution:**
```powershell
# Install sbt (see Step 2)
choco install sbt

# Or download MSI from https://www.scala-sbt.org/download.html
```

---

### Problem 3: sbt Dependency Download Fails

**Error:**
```
[error] Error downloading org.scala-lang:scala-library:2.12.14
```

**Solution:**
```powershell
# Check internet connection

# Try alternative mirror (edit ~/.sbt/repositories or use proxy)
# In project/build.properties, add:
# sbt.repository.config=repositories

# Clear sbt cache and retry
Remove-Item ~\.sbt\cache -Recurse -Force
Remove-Item ~\.ivy2\cache -Recurse -Force
sbt clean
sbt compile
```

---

### Problem 4: Out of Memory Error

**Error:**
```
java.lang.OutOfMemoryError: Java heap space
```

**Solution:**
```powershell
# Increase JVM heap size
# Create/edit vexriscv_reference\source\.jvmopts
# Add:
-Xmx4G
-Xms2G

# Or set environment variable
$env:SBT_OPTS = "-Xmx4G -Xms2G"
```

---

### Problem 5: GenSmallOptimized.scala Not Found

**Error:**
```
[error] not found: object GenSmallOptimized
```

**Verification:**
```powershell
# Check file exists in source tree
Test-Path vexriscv_reference\source\src\main\scala\vexriscv\demo\GenSmallOptimized.scala

# Re-copy from config
Copy-Item vexriscv_reference\config\GenSmallOptimized.scala `
          vexriscv_reference\source\src\main\scala\vexriscv\demo\GenSmallOptimized.scala
```

---

### Problem 6: Empty cpu.yaml

**Symptom:**
```
cpu.yaml contains only: {}
```

**Explanation:** SpinalHDL YamlPlugin sometimes fails to populate YAML (known issue).

**Impact:** **None** - RTL is valid, YAML is optional documentation.

**Workaround (if needed):**
```scala
// In GenSmallOptimized.scala, comment out YamlPlugin
// new YamlPlugin(s"$outputDir/cpu.yaml")  // ← Comment this line
```

---

### Problem 7: Vivado Synthesis Errors

**Error:**
```
[ERROR] Unrecognized case item expression
```

**Cause:** SpinalHDL generates case statements that some tools reject.

**Solution:**
```verilog
// Manually edit VexRiscv.v (not ideal, better to fix in Scala)
// Change:
case(variable)
  default: ...
endcase

// To:
case(variable)
  default: ...
  // Add explicit cases if needed
endcase
```

**Better Solution:** Report to VexRiscv GitHub issues.

---

## Build Performance

### Typical Build Times

| Phase | Time (First Build) | Time (Rebuild) |
|-------|-------------------|----------------|
| sbt dependency download | 5-10 min | 0s (cached) |
| Scala compilation | 30-60s | 10-20s (incremental) |
| SpinalHDL elaboration | 10-15s | 10-15s |
| **Total** | **6-12 min** | **20-35s** |

### Optimization Tips

**1. Keep sbt Running (Interactive Mode):**
```powershell
cd vexriscv_reference\source
sbt

# In sbt shell, rebuild faster:
> ~runMain vexriscv.demo.GenSmallOptimized ..\..\generated
```
The `~` prefix watches for file changes and auto-rebuilds.

**2. Use sbt Server (Persistent JVM):**
```powershell
# Start server once
sbt startServer

# In new terminal, instant commands:
sbt runMain vexriscv.demo.GenSmallOptimized ...
```

**3. Parallelize sbt:**
```powershell
# In ~/.sbt/1.0/global.sbt
Global / concurrentRestrictions := Seq(
  Tags.limit(Tags.CPU, 8)
)
```

---

## Advanced Topics

### Multi-Config Builds

To generate multiple VexRiscv variants:

```powershell
# Build script supports multiple configs
.\tools\build_vexriscv.ps1 -Config GenSmallOptimized
.\tools\build_vexriscv.ps1 -Config GenSmall
.\tools\build_vexriscv.ps1 -Config GenFull
```

### Custom Plugins

Create your own VexRiscv plugin:

```scala
// vexriscv_reference/config/MyCustomPlugin.scala
package vexriscv.plugin

import vexriscv._
import spinal.core._

class MyCustomPlugin extends Plugin[VexRiscv] {
  override def setup(pipeline: VexRiscv): Unit = {
    // Called during pipeline construction
  }
  
  override def build(pipeline: VexRiscv): Unit = {
    // Called during hardware elaboration
  }
}

// In GenSmallOptimized.scala, add to plugins list:
new MyCustomPlugin()
```

### Integration with CI/CD

```yaml
# .github/workflows/vexriscv-build.yml
name: VexRiscv Build
on: [push]
jobs:
  build-rtl:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v2
      - uses: actions/setup-java@v2
        with:
          java-version: '11'
      - run: choco install sbt
      - run: .\tools\build_vexriscv.ps1
      - run: .\scripts\run_regression.ps1 -Stage 1
```

---

## Related Documentation

- **[Architecture Overview](vexriscv_architecture.md)** - Understanding GenSmallOptimized configuration
- **[Pipeline Operation](vexriscv_pipeline_operation.md)** - How generated RTL executes instructions
- **[Signal Reference](vexriscv_signal_reference.md)** - Navigating generated Verilog
- **[Test Plan](vexriscv_test_plan.md)** - Validating generated RTL

---

## External Resources

- **VexRiscv GitHub:** https://github.com/SpinalHDL/VexRiscv
- **SpinalHDL Documentation:** https://spinalhdl.github.io/SpinalDoc-RTD/
- **sbt Reference:** https://www.scala-sbt.org/1.x/docs/
- **Scala Documentation:** https://docs.scala-lang.org/

---

**Document Version:** 1.0  
**Last Updated:** 2026-02-07  
**Author:** Generated from project build infrastructure analysis
