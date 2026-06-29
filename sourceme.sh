#!/bin/bash

# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------

# Verilator
export VERILATOR_HOME=/my_tools/verilator
export PATH=$VERILATOR_HOME/bin:$PATH

# Yosys
export YOSYS_HOME=/my_tools/yosys
export PATH=$YOSYS_HOME/bin:$PATH

# Yosys Slang
export YOSYS_SLANG_HOME=/my_tools/yosys-slang
export PATH=$YOSYS_SLANG_HOME/bin:$PATH

# OpenSTA
export OPENSTA_HOME=/my_tools/opensta
export PATH=$OPENSTA_HOME/bin:$PATH

# OpenROAD
export OPENROAD_HOME=/my_tools/openroad
export PATH=$OPENROAD_HOME/bin:$PATH

# Code
export CODE_HOME=/home/simone/work/my_code

# Tools
export TOOLS_HOME=/home/simone/work/my_tools
