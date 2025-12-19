# Makefile for AXIUART Simplified UVM Testbench
# Uses DSIM simulator with UVM

# DSIM variables
DSIM = dsim
DSIM_WORK = work
DSIM_CONFIG = dsim_config.f

# Test names
TEST_NAME = axiuart_basic_test

# Directories
RTL_DIR = ../../rtl
SV_DIR = ../sv
TB_DIR = .

# Targets
.PHONY: all clean compile run waves help

all: compile run

help:
	@echo "AXIUART Simplified UVM Testbench Makefile"
	@echo "==========================================="
	@echo "Targets:"
	@echo "  compile  - Compile RTL and testbench"
	@echo "  run      - Run simulation"
	@echo "  waves    - Open waveform viewer"
	@echo "  clean    - Clean build artifacts"
	@echo "  all      - Compile and run (default)"

compile:
	@echo "Compiling AXIUART Simplified Testbench..."
	$(DSIM) -work $(DSIM_WORK) \
	        -genimage image \
	        -f $(DSIM_CONFIG)

run: compile
	@echo "Running $(TEST_NAME)..."
	$(DSIM) -work $(DSIM_WORK) \
	        -image image \
	        +UVM_TESTNAME=$(TEST_NAME) \
	        +UVM_VERBOSITY=UVM_MEDIUM \
	        -waves

waves:
	@echo "Opening waveform viewer..."
	mxview axiuart_simplified.mxd &

clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(DSIM_WORK)/ image/ *.mxd *.log dsim.env

# Quick test targets
test: all

.DEFAULT_GOAL := all
