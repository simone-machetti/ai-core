# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------

source $::env(REPO_HOME)/scripts/pnr/init_tech.tcl
source $::env(REPO_HOME)/scripts/pnr/checkpoint.tcl
source $::env(REPO_HOME)/scripts/pnr/reports.tcl

# -----------------------------------------------------------------------------
# Technology (physical views)
# -----------------------------------------------------------------------------
read_lef $TECH_LEF
read_lef $SC_LEF

# -----------------------------------------------------------------------------
# Netlist & top-level linking
# -----------------------------------------------------------------------------
read_verilog $::env(REPO_HOME)/projects/$::env(SEL_PROJECT)/imp/$::env(SEL_NETLIST_DIR)/output/netlist.v
link_design $::env(SEL_TOP_LEVEL)

# -----------------------------------------------------------------------------
# Constraints & wire RC
# -----------------------------------------------------------------------------
source $::env(REPO_HOME)/scripts/pnr/constraints.tcl
source $::env(ASAP7_HOME)/setRC.tcl
set_dont_use $DONT_USE

# -----------------------------------------------------------------------------
# Floorplan & routing tracks
# -----------------------------------------------------------------------------
initialize_floorplan \
    -utilization  $::env(SEL_CORE_UTIL) \
    -aspect_ratio $::env(SEL_ASPECT_RATIO) \
    -core_space   $::env(SEL_CORE_MARGIN) \
    -site         $SITE

source $::env(ASAP7_HOME)/openRoad/make_tracks.tcl

# -----------------------------------------------------------------------------
# Pin placement (provisional, refined after global placement)
# -----------------------------------------------------------------------------
place_pins -hor_layers $PIN_LAYER_HOR -ver_layers $PIN_LAYER_VER

# -----------------------------------------------------------------------------
# Tie cells & tap cells
# -----------------------------------------------------------------------------
insert_tiecells $TIEHI_PORT -prefix "TIEHI_"
insert_tiecells $TIELO_PORT -prefix "TIELO_"

tapcell -distance 25 -tapcell_master $TAPCELL -endcap_master $TAPCELL

# -----------------------------------------------------------------------------
# Power distribution network
# -----------------------------------------------------------------------------
source $PDN_CFG
pdngen

report_stage 1_floorplan
save_checkpoint 1_floorplan
