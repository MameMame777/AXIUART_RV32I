#!/usr/bin/env python3
"""
Setup script for DSIM UVM MCP Server
Installs dependencies and configures the environment
"""

import os
import sys
import subprocess
import json
from pathlib import Path

def install_mcp_package():
    """Install MCP package using pip"""
    print("[INFO] Installing MCP package...")
    
    try:
        # Try installing MCP package
        result = subprocess.run([
            sys.executable, "-m", "pip", "install", "mcp"
        ], capture_output=True, text=True, check=True)
        
        print("[OK] MCP package installed successfully")
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"[FAIL] Failed to install MCP package: {e}")
        print(f"STDOUT: {e.stdout}")
        print(f"STDERR: {e.stderr}")
        
        # Try alternative installation methods
        print("[INFO] Trying alternative installation...")
        
        try:
            # Try installing from PyPI with specific version
            result = subprocess.run([
                sys.executable, "-m", "pip", "install", "model-context-protocol"
            ], capture_output=True, text=True, check=True)
            
            print("[OK] Alternative MCP package installed")
            return True
            
        except subprocess.CalledProcessError as e2:
            print(f"[FAIL] Alternative installation also failed: {e2}")
            return False

def install_requirements():
    """Install requirements from requirements.txt"""
    print("[INFO] Installing requirements...")
    
    requirements_file = Path(__file__).parent / "requirements.txt"
    
    if not requirements_file.exists():
        print("[FAIL] requirements.txt not found")
        return False
    
    try:
        result = subprocess.run([
            sys.executable, "-m", "pip", "install", "-r", str(requirements_file)
        ], capture_output=True, text=True, check=True)
        
        print("[OK] Requirements installed successfully")
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"[FAIL] Failed to install requirements: {e}")
        print(f"STDERR: {e.stderr}")
        return False

def verify_dsim_environment():
    """Verify DSIM environment variables"""
    print("[INFO] Verifying DSIM environment...")
    
    dsim_home = os.environ.get('DSIM_HOME')
    
    if not dsim_home:
        print("[WARN] DSIM_HOME not set in environment")
        print("   Please set DSIM_HOME to your DSIM installation directory")
        return False
        
    dsim_path = Path(dsim_home)
    if not dsim_path.exists():
        print(f"[FAIL] DSIM_HOME path does not exist: {dsim_home}")
        return False
        
    dsim_exe = dsim_path / "bin" / "dsim.exe"
    if not dsim_exe.exists():
        print(f"[FAIL] DSIM executable not found: {dsim_exe}")
        return False
        
    print(f"[OK] DSIM environment verified: {dsim_home}")
    return True

def setup_dsim_license():
    """Automatically setup DSIM_LICENSE environment variable if not set"""
    print("[INFO] Checking DSIM license configuration...")
    
    if os.environ.get('DSIM_LICENSE'):
        print(f"[OK] DSIM_LICENSE already set: {os.environ['DSIM_LICENSE']}")
        return True
    
    # Check common license locations
    dsim_home = os.environ.get('DSIM_HOME')
    if not dsim_home:
        print("[WARN] DSIM_HOME not set, cannot auto-configure license")
        return False
        
    license_locations = [
        Path(dsim_home).parent / "dsim-license.json",
        Path(dsim_home) / "dsim-license.json",
        Path("C:/Users/Nautilus/AppData/Local/metrics-ca/dsim-license.json")
    ]
    
    for license_path in license_locations:
        if license_path.exists():
            os.environ['DSIM_LICENSE'] = str(license_path)
            print(f"[OK] Auto-configured DSIM_LICENSE: {license_path}")
            
            # Try to make it persistent for current session
            try:
                # Write to a temporary env file that can be sourced
                env_file = Path(__file__).parent / "dsim_env_setup.bat"
                with open(env_file, 'w') as f:
                    f.write(f"@echo off\n")
                    f.write(f"set DSIM_LICENSE={license_path}\n")
                    f.write(f"echo DSIM_LICENSE set to: {license_path}\n")
                print(f"[INFO] Environment setup script created: {env_file}")
            except Exception as e:
                print(f"[WARN] Could not create environment setup script: {e}")
            
            return True
    
    print("[WARN] No DSIM license file found in common locations")
    print("   You may need to set DSIM_LICENSE manually")
    return False

def create_launcher_script():
    """Create a launcher script for the MCP server"""
    print("📝 Creating launcher script...")
    
    launcher_content = '''@echo off
REM DSIM UVM MCP Server Launcher
REM Created by setup script

echo Starting DSIM UVM MCP Server...

REM Set workspace directory
set WORKSPACE_DIR=%~dp0..

REM Check Python availability
python --version >nul 2>&1
if errorlevel 1 (
    echo Error: Python is not available in PATH
    pause
    exit /b 1
)

REM Check DSIM environment
if not defined DSIM_HOME (
    echo Error: DSIM_HOME environment variable is not set
    pause
    exit /b 1
)

REM Start MCP server
python "%~dp0dsim_uvm_server.py" --workspace "%WORKSPACE_DIR%"

pause
'''
    
    launcher_file = Path(__file__).parent / "start_mcp_server.bat"
    
    try:
        with open(launcher_file, 'w', encoding='utf-8') as f:
            f.write(launcher_content)
        print(f"✅ Launcher script created: {launcher_file}")
        return True
    except Exception as e:
        print(f"❌ Failed to create launcher script: {e}")
        return False

def test_mcp_server():
    """Test MCP server functionality"""
    print("[INFO] Testing MCP server...")
    
    server_file = Path(__file__).parent / "dsim_uvm_server.py"
    
    if not server_file.exists():
        print("[FAIL] MCP server file not found")
        return False
    
    try:
        # Try importing the server module with ASCII-safe output
        test_code = '''
import asyncio
import os
import sys
sys.path.append(r"{server_dir}")
os.environ['PYTHONIOENCODING'] = 'utf-8'

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

try:
    from dsim_uvm_server import setup_workspace, list_available_tests
    workspace = r"{workspace_dir}"
    setup_workspace(workspace)

    async def _probe() -> None:
        await list_available_tests()

    asyncio.run(_probe())
    print("[OK] MCP server module loaded successfully")
except Exception as exc:
    print("[FAIL] Failed to load MCP server: " + str(exc))
    sys.exit(1)
'''.format(server_dir=str(server_file.parent), workspace_dir=str(server_file.parent.parent))
        
        result = subprocess.run([
            sys.executable, "-c", test_code
        ], capture_output=True, text=True, timeout=10, env=dict(os.environ, PYTHONIOENCODING='utf-8'))
        
        if result.returncode == 0:
            print("[OK] MCP server module test passed")
            return True
        else:
            print(f"[FAIL] MCP server module test failed: {result.stderr}")
            return False
            
    except subprocess.TimeoutExpired:
        print("[FAIL] MCP server test timed out")
        return False
    except Exception as e:
        print(f"[FAIL] MCP server test error: {e}")
        return False

def main():
    """Main setup function"""
    print("[INFO] DSIM UVM MCP Server Setup")
    print("=" * 50)
    
    success_count = 0
    total_steps = 6
    
    # Step 1: Install MCP package
    if install_mcp_package():
        success_count += 1
    
    # Step 2: Install requirements
    if install_requirements():
        success_count += 1
    
    # Step 3: Verify DSIM environment
    if verify_dsim_environment():
        success_count += 1
    
    # Step 4: Setup DSIM license (NEW)
    if setup_dsim_license():
        success_count += 1
    
    # Step 5: Create launcher script
    if create_launcher_script():
        success_count += 1
    
    # Step 6: Test MCP server
    if test_mcp_server():
        success_count += 1
    
    # Summary
    print("\n" + "=" * 50)
    print(f"[INFO] Setup Summary: {success_count}/{total_steps} steps completed")
    
    if success_count == total_steps:
        print("[OK] Setup completed successfully!")
        print("\nNext steps:")
        print("1. Run: start_mcp_server.bat")
        print("2. Configure your MCP client to use the server")
        print("3. Test with tools like run_uvm_simulation")
    else:
        print("[WARN] Setup completed with some issues")
        print("   Please review the error messages above")
    
    return success_count == total_steps

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)