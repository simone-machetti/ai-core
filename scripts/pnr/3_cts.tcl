# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------

source $::env(REPO_HOME)/scripts/pnr/init_tech.tcl
source $::env(REPO_HOME)/scripts/pnr/checkpoint.tcl
source $::env(REPO_HOME)/scripts/pnr/reports.tcl

load_checkpoint 2_place

# -----------------------------------------------------------------------------
# Clock tree synthesis
# -----------------------------------------------------------------------------
repair_clock_inverters

clock_tree_synthesis -sink_clustering_enable -repair_clock_nets

set_propagated_clock [all_clocks]

# -----------------------------------------------------------------------------
# Post-CTS timing repair
# -----------------------------------------------------------------------------
estimate_parasitics -placement
repair_timing -setup

# -----------------------------------------------------------------------------
# Legalization
# -----------------------------------------------------------------------------
detailed_placement
check_placement -verbose

report_stage 3_cts
save_checkpoint 3_cts
