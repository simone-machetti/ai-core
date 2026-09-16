#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------
#
# Hierarchical place-and-route of the baseline top_NxN grid. The pe tile is
# hardened once as a macro with its pin plan and I/O budgets, the parent is
# synthesized with empty pe stubs, then assembled with the N*N macros placed by
# the floorplan script and its boundary pins aligned with them. The tile is
# hardened at a tighter clock than the grid so that the period gap becomes the
# parent's wire budget. Each command lists every relevant parameter (defaults
# included) as a reference. Run directly (not through make). On a 30 GB machine
# the 2x2 assembly takes about 6 hours and 26 GB; the 4x4 does not fit.
# -----------------------------------------------------------------------------

set -e

cd "$(dirname "$0")/../../.."
source sourceme.sh

CLK_PE=1.6
CLK_TOP=2.0
N=2

PINS_PE=projects/unified-core/scripts/pins_pe.tcl
SDC_PE=projects/unified-core/scripts/sdc_pe.tcl
PINS_TOP=projects/unified-core/scripts/pins_top_NxN.tcl
FLOORPLAN=projects/unified-core/scripts/floorplan_top_NxN.tcl
PIN_ARGS="-min_distance 2 -min_distance_in_tracks -corner_avoidance 2"

# -----------------------------------------------------------------------------
# Step 1 - synthesize the pe tile (flat)
# -----------------------------------------------------------------------------
make syn PROJECT=unified-core TOP_LEVEL=pe OUT_DIR=pe_syn CLK_PERIOD_NS=$CLK_PE \
    PARAMS=none KEEP_HIERARCHY=0 KEEP_MODULES=none BLACKBOX_MODULES=none LINK_BLACKBOXES=1

# -----------------------------------------------------------------------------
# Step 2 - harden the pe tile as a macro
# -----------------------------------------------------------------------------
make pnr PROJECT=unified-core TOP_LEVEL=pe OUT_DIR=pe_pnr_u80 NETLIST_DIR=pe_syn CLK_PERIOD_NS=$CLK_PE \
    CORE_UTIL=80 ASPECT_RATIO=1.0 CORE_MARGIN=2 PLACE_DENSITY=0.9 MAX_ROUTE_LAYER=M5 \
    CLK_UNCERTAINTY_PS=50 PNR_STEP=all PNR_THREADS=0 PNR_REPAIR=1 MACRO_DIRS=none FLOORPLAN=none \
    PDN=scripts/pnr/pdn_tile.tcl PINS=$PINS_PE PIN_LAYERS_HOR=M4 PIN_LAYERS_VER="M3 M5" \
    PIN_ARGS="$PIN_ARGS" IO_DELAY_PCT=0 SDC=$SDC_PE

# -----------------------------------------------------------------------------
# Step 3 - synthesize the parent with empty pe stubs
# -----------------------------------------------------------------------------
make syn PROJECT=unified-core TOP_LEVEL=top_NxN OUT_DIR=top_${N}x${N}_syn CLK_PERIOD_NS=$CLK_TOP \
    PARAMS="N=$N" KEEP_HIERARCHY=0 KEEP_MODULES=none BLACKBOX_MODULES="pe" LINK_BLACKBOXES=0

# -----------------------------------------------------------------------------
# Step 4 - assemble: place-and-route the parent with the N*N macros
# -----------------------------------------------------------------------------
make pnr PROJECT=unified-core TOP_LEVEL=top_NxN OUT_DIR=top_${N}x${N}_pnr NETLIST_DIR=top_${N}x${N}_syn CLK_PERIOD_NS=$CLK_TOP \
    CORE_UTIL=25 ASPECT_RATIO=1.0 CORE_MARGIN=2 PLACE_DENSITY=0.60 MAX_ROUTE_LAYER=M9 \
    CLK_UNCERTAINTY_PS=50 PNR_STEP=all PNR_THREADS=4 PNR_REPAIR=1 MACRO_DIRS="pe_pnr_u80" \
    FLOORPLAN=$FLOORPLAN MACRO_CHANNEL=40 MACRO_CHANNEL_Y=60 PDN=none \
    PINS=$PINS_TOP PIN_LAYERS_HOR="M2 M4" PIN_LAYERS_VER="M3 M5" PIN_ARGS="$PIN_ARGS"
