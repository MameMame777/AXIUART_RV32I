#!/bin/bash
# cloud_interactive.sh
# Bash script to simulate design with Altair® DSim™ Cloud

# Set up environment
set -e

# Analyze and Elaborate design
mdc dsim -a '-top work.top -genimage image -uvm 1.2 ../uvm_hello_world.sv'

# Simulate design
mdc dsim -a '-image image -uvm 1.2 +UVM_NO_RELNOTES +UVM_TESTNAME=my_test'
