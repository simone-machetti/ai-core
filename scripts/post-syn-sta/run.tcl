# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------

set REPORT_DIR $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/report
file mkdir $REPORT_DIR

# -----------------------------------------------------------------------------
# Libraries (timing models)
# -----------------------------------------------------------------------------
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib

# -----------------------------------------------------------------------------
# Netlist + top-level linking
# -----------------------------------------------------------------------------
read_verilog $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_NETLIST_DIR)/output/netlist.v
link_design  $env(SEL_TOP_LEVEL)

# -----------------------------------------------------------------------------
# Clock definition
# -----------------------------------------------------------------------------
set CLK_PERIOD_PS [expr {$env(SEL_CLK_PERIOD_NS) * 1000}]
create_clock -name clk_i -period $CLK_PERIOD_PS [get_ports clk_i]

# -----------------------------------------------------------------------------
# Reports generation
# -----------------------------------------------------------------------------
report_checks -unconstrained > $REPORT_DIR/unconstrained.rpt
report_checks \
    -path_delay max \
    -fields {slew cap input_pins} \
    -digits 4 \
    -group_count 10 \
    > $REPORT_DIR/critical_paths.rpt
report_wns > $REPORT_DIR/wns.rpt
report_tns > $REPORT_DIR/tns.rpt
# report_units
