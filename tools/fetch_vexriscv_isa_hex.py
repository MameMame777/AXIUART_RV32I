#!/usr/bin/env python3
"""
VexRiscv ISA Test Hex File Downloader

Downloads pre-compiled ISA test hex files from the VexRiscv upstream repository
(SpinalHDL/VexRiscv) for use with the AXIUART_RV32I verification environment.

Usage:
    python tools/fetch_vexriscv_isa_hex.py                     # Download smoke tests
    python tools/fetch_vexriscv_isa_hex.py --all                # Download all rv32ui-p-* tests
    python tools/fetch_vexriscv_isa_hex.py --test rv32ui-p-add  # Download specific test
    python tools/fetch_vexriscv_isa_hex.py --list               # List available tests

Output directory: sim/tests/isa_hex/
"""

import argparse
import os
import sys
import urllib.request
import urllib.error

# VexRiscv upstream GitHub raw URL base
GITHUB_RAW_BASE = (
    "https://raw.githubusercontent.com/SpinalHDL/VexRiscv/"
    "master/src/test/resources/hex"
)

# RV32I user-mode physical-address ISA tests (rv32ui-p-*)
RV32UI_P_TESTS = [
    "rv32ui-p-add",
    "rv32ui-p-addi",
    "rv32ui-p-and",
    "rv32ui-p-andi",
    "rv32ui-p-auipc",
    "rv32ui-p-beq",
    "rv32ui-p-bge",
    "rv32ui-p-bgeu",
    "rv32ui-p-blt",
    "rv32ui-p-bltu",
    "rv32ui-p-bne",
    "rv32ui-p-fence_i",
    "rv32ui-p-jal",
    "rv32ui-p-jalr",
    "rv32ui-p-lb",
    "rv32ui-p-lbu",
    "rv32ui-p-lh",
    "rv32ui-p-lhu",
    "rv32ui-p-lui",
    "rv32ui-p-lw",
    "rv32ui-p-or",
    "rv32ui-p-ori",
    "rv32ui-p-sb",
    "rv32ui-p-sh",
    "rv32ui-p-simple",
    "rv32ui-p-sll",
    "rv32ui-p-slli",
    "rv32ui-p-slt",
    "rv32ui-p-slti",
    "rv32ui-p-sltiu",
    "rv32ui-p-sltu",
    "rv32ui-p-sra",
    "rv32ui-p-srai",
    "rv32ui-p-srl",
    "rv32ui-p-srli",
    "rv32ui-p-sub",
    "rv32ui-p-sw",
    "rv32ui-p-xor",
    "rv32ui-p-xori",
]

# Smoke test subset (minimal set for quick validation)
SMOKE_TESTS = [
    "rv32ui-p-add",
    "rv32ui-p-addi",
]

# Default output directory (relative to workspace root)
DEFAULT_OUTPUT_DIR = os.path.join("sim", "tests", "isa_hex")


def get_workspace_root():
    """Find workspace root by looking for tools/ directory."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    workspace = os.path.dirname(script_dir)
    if os.path.isdir(os.path.join(workspace, "tools")):
        return workspace
    return os.getcwd()


def download_hex_file(test_name, output_dir, verbose=False):
    """Download a single hex file from VexRiscv upstream.

    Args:
        test_name: Test name without .hex extension (e.g. 'rv32ui-p-add')
        output_dir: Directory to save the file
        verbose: Print detailed progress

    Returns:
        True if download succeeded, False otherwise
    """
    filename = f"{test_name}.hex"
    url = f"{GITHUB_RAW_BASE}/{filename}"
    output_path = os.path.join(output_dir, filename)

    if os.path.exists(output_path):
        if verbose:
            print(f"  [SKIP] {filename} (already exists)")
        return True

    if verbose:
        print(f"  [GET]  {filename} ... ", end="", flush=True)

    try:
        urllib.request.urlretrieve(url, output_path)
        file_size = os.path.getsize(output_path)
        if verbose:
            print(f"OK ({file_size} bytes)")
        return True
    except urllib.error.HTTPError as e:
        if verbose:
            print(f"FAILED (HTTP {e.code})")
        else:
            print(f"  [FAIL] {filename}: HTTP {e.code}")
        # Remove partial file
        if os.path.exists(output_path):
            os.remove(output_path)
        return False
    except urllib.error.URLError as e:
        if verbose:
            print(f"FAILED ({e.reason})")
        else:
            print(f"  [FAIL] {filename}: {e.reason}")
        if os.path.exists(output_path):
            os.remove(output_path)
        return False


def validate_hex_file(filepath):
    """Basic validation of Intel HEX file format.

    Returns:
        True if file appears to be valid Intel HEX
    """
    try:
        with open(filepath, "r") as f:
            first_line = f.readline().strip()
            if not first_line.startswith(":"):
                return False
            # Check minimum line length (: + 2 byte_count + 4 addr + 2 type + 2 checksum)
            if len(first_line) < 11:
                return False
        return True
    except (IOError, UnicodeDecodeError):
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Download VexRiscv ISA test hex files from upstream"
    )
    parser.add_argument(
        "--test",
        action="append",
        dest="tests",
        help="Download specific test(s) (can be repeated)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Download all rv32ui-p-* tests",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List available tests without downloading",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help=f"Output directory (default: {DEFAULT_OUTPUT_DIR})",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-download even if files already exist",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Verbose output",
    )
    args = parser.parse_args()

    # List mode
    if args.list:
        print(f"Available rv32ui-p-* ISA tests ({len(RV32UI_P_TESTS)}):")
        for test in RV32UI_P_TESTS:
            marker = "*" if test in SMOKE_TESTS else " "
            print(f"  {marker} {test}")
        print(f"\n  * = included in smoke test set")
        return 0

    # Determine output directory
    workspace = get_workspace_root()
    output_dir = args.output_dir or os.path.join(workspace, DEFAULT_OUTPUT_DIR)

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Determine which tests to download
    if args.all:
        tests_to_download = RV32UI_P_TESTS
    elif args.tests:
        tests_to_download = args.tests
    else:
        # Default: smoke tests only
        tests_to_download = SMOKE_TESTS

    # Remove existing files if --force
    if args.force:
        for test_name in tests_to_download:
            filepath = os.path.join(output_dir, f"{test_name}.hex")
            if os.path.exists(filepath):
                os.remove(filepath)

    print(f"Downloading {len(tests_to_download)} ISA test hex file(s)")
    print(f"Source: {GITHUB_RAW_BASE}")
    print(f"Target: {output_dir}")
    print()

    # Download
    success_count = 0
    fail_count = 0

    for test_name in tests_to_download:
        if download_hex_file(test_name, output_dir, verbose=True):
            # Validate downloaded file
            filepath = os.path.join(output_dir, f"{test_name}.hex")
            if validate_hex_file(filepath):
                success_count += 1
            else:
                print(f"  [WARN] {test_name}.hex downloaded but failed validation")
                fail_count += 1
        else:
            fail_count += 1

    # Summary
    print()
    print(f"Results: {success_count} OK, {fail_count} failed")

    if fail_count > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
