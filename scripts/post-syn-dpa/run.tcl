# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------

set REPORT_DIR $env(CODE_HOME)/ai-core/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/report

# -----------------------------------------------------------------------------
# Libraries (timing/power models)
# -----------------------------------------------------------------------------
read_liberty $env(TOOLS_HOME)/OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib
read_liberty $env(TOOLS_HOME)/OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib
read_liberty $env(TOOLS_HOME)/OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib
read_liberty $env(TOOLS_HOME)/OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib
read_liberty $env(TOOLS_HOME)/OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib

# -----------------------------------------------------------------------------
# Netlist & top-level linking
# -----------------------------------------------------------------------------
read_verilog $env(CODE_HOME)/ai-core/projects/$env(SEL_PROJECT)/imp/$env(SEL_NETLIST_DIR)/output/netlist.v
link_design $env(SEL_TOP_LEVEL)

# -----------------------------------------------------------------------------
# Virtual clock & I/O constraints (required to avoid "No clocks defined")
# -----------------------------------------------------------------------------
set CLK_PERIOD_PS [expr {$env(SEL_CLK_PERIOD_NS) * 1000}]
create_clock -name clk_i -period $CLK_PERIOD_PS [get_ports clk_i]

# -----------------------------------------------------------------------------
# VCD-based switching activity
# -----------------------------------------------------------------------------
set vcd_verilator "$env(CODE_HOME)/ai-core/projects/$env(SEL_PROJECT)/sim/$env(SEL_VCD_DIR)/output/activity.vcd"
read_vcd -scope tb_$env(SEL_TOP_LEVEL)/$env(SEL_TOP_LEVEL)_i $vcd_verilator

report_activity_annotation -report_annotated   > $REPORT_DIR/vcd_annotated.rpt
report_activity_annotation -report_unannotated > $REPORT_DIR/vcd_unannotated.rpt

# -----------------------------------------------------------------------------
# Power reports
# -----------------------------------------------------------------------------
report_power > $REPORT_DIR/power_summary.rpt

if {$env(SEL_KEEP_HIERARCHY) eq "1"} {
    report_power -instances [get_cells -hierarchical *] > $REPORT_DIR/power_hierarchy.rpt
}
# report_units
