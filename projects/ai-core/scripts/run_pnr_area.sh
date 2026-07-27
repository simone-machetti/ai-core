#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------
#
# Hierarchical place-and-route of the baseline top_NxN grid for area estimation.
# The pe tile is hardened once as a macro, the parent is synthesized with empty
# pe stubs, then assembled with the N*N macros placed by the floorplan script.
# Built up one step at a time; each command lists every relevant parameter
# (defaults included) as a reference. Run directly (not through make).
# -----------------------------------------------------------------------------

set -e

cd "$(dirname "$0")/../../.."
source sourceme.sh

CLK=1.5

# -----------------------------------------------------------------------------
# Step 1 - synthesize the pe tile (flat)
# -----------------------------------------------------------------------------
make syn PROJECT=ai-core TOP_LEVEL=pe OUT_DIR=pe_syn CLK_PERIOD_NS=$CLK \
    PARAMS=none KEEP_HIERARCHY=0 KEEP_MODULES=none BLACKBOX_MODULES=none LINK_BLACKBOXES=1

# -----------------------------------------------------------------------------
# Step 2 - harden the pe tile as a macro
# -----------------------------------------------------------------------------
make pnr PROJECT=ai-core TOP_LEVEL=pe OUT_DIR=pe_pnr NETLIST_DIR=pe_syn CLK_PERIOD_NS=$CLK \
    CORE_UTIL=20 ASPECT_RATIO=1.0 CORE_MARGIN=2 PLACE_DENSITY=0.40 MAX_ROUTE_LAYER=M5 \
    CLK_UNCERTAINTY_PS=0 PNR_STEP=all PNR_THREADS=0 MACRO_DIRS=none FLOORPLAN=none \
    PDN=scripts/pnr/pdn_tile.tcl

# -----------------------------------------------------------------------------
# Step 3 - synthesize the parent (N=2) with empty pe stubs
# -----------------------------------------------------------------------------
make syn PROJECT=ai-core TOP_LEVEL=top_NxN OUT_DIR=top_2x2_syn CLK_PERIOD_NS=$CLK \
    PARAMS="N=2" KEEP_HIERARCHY=0 KEEP_MODULES=none BLACKBOX_MODULES="pe" LINK_BLACKBOXES=0

# -----------------------------------------------------------------------------
# Step 4 - assemble: place-and-route the parent with the N*N macros
# -----------------------------------------------------------------------------
make pnr PROJECT=ai-core TOP_LEVEL=top_NxN OUT_DIR=top_2x2_pnr NETLIST_DIR=top_2x2_syn CLK_PERIOD_NS=$CLK \
    CORE_UTIL=50 ASPECT_RATIO=1.0 CORE_MARGIN=2 PLACE_DENSITY=0.60 MAX_ROUTE_LAYER=M7 \
    CLK_UNCERTAINTY_PS=0 PNR_STEP=all PNR_THREADS=4 MACRO_DIRS="pe_pnr" \
    FLOORPLAN=projects/ai-core/scripts/floorplan_top_NxN.tcl MACRO_CHANNEL=40 PDN=none \
    DROUTE_END_ITER=0
