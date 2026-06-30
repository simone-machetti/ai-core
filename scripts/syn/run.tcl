# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------

source $env(REPO_HOME)/scripts/syn/compile.tcl

# -----------------------------------------------------------------------------
# Elaboration / hierarchy
# -----------------------------------------------------------------------------
yosys "hierarchy -check -top $env(SEL_TOP_LEVEL)"
yosys "check"

# -----------------------------------------------------------------------------
# Synthesis & optimizations
# -----------------------------------------------------------------------------
yosys "proc"
yosys "opt"
yosys "fsm"
yosys "opt"
yosys "memory"
yosys "opt"
yosys "techmap"
yosys "opt"

# -----------------------------------------------------------------------------
# Technology mapping
# -----------------------------------------------------------------------------
yosys "dfflibmap -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib"
yosys "opt"

yosys "abc \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib \
    -script  $env(REPO_HOME)/scripts/syn/abc.tcl"

yosys "opt"
yosys "clean"

# -----------------------------------------------------------------------------
# Generate hierarchical area report
# -----------------------------------------------------------------------------
yosys "tee -o $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/report/area.rpt stat -hierarchy \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib"

# -----------------------------------------------------------------------------
# Flatten full design, optimize and clean for netlist output
# (skipped when SEL_KEEP_HIERARCHY=1)
# -----------------------------------------------------------------------------
if {$env(SEL_KEEP_HIERARCHY) eq "0"} {
    yosys "flatten"
    yosys "opt_clean"
    yosys "rename -hide"
}

# -----------------------------------------------------------------------------
# Write synthesized netlist
# -----------------------------------------------------------------------------
yosys "write_verilog -noattr -noexpr -nodec $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/output/netlist.v"
