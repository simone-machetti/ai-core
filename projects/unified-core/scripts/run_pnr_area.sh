#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
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
#
# BEOL selects the metal stack. On smic-n3 the first coarse layer is M4, so the
# recipe sits one layer lower: the tile is capped at M4 with its clock floor and
# its top and bottom pins on M3 (one vertical pin layer instead of two) and takes
# the smic-n3 tile PDN; the parent takes the smic-n3 macro PDN and routes up to
# M10. Runs on a stack other than asap7 carry its name as a suffix, so the two
# stacks never overwrite each other. Expect detailed routing to take 1.5 to 2
# times longer on smic-n3.
#
# Open point on smic-n3, not yet run: the top edge of the tile carries 1067 pins
# (the A bus and the control). On asap7 they spread over M3 and M5, about 1770
# slots on the 73 um tile at a minimum distance of 2 tracks; with M3 alone at a
# 44 nm pitch there are about 830, so place_pins will refuse the plan as it is.
# The ways out are a minimum distance of 1 track (about 1660 slots), a wider
# tile, or moving part of the A bus to another edge.
# -----------------------------------------------------------------------------

set -e

cd "$(dirname "$0")/../../.."
source sourceme.sh

CLK_PE=1.6
CLK_TOP=2.0
N=2
BEOL=asap7

if [ "$BEOL" = "smic-n3" ]; then
    SUFFIX=_smic-n3
    TILE_MAX_ROUTE_LAYER=M4
    TILE_MIN_CLK_LAYER=M3
    TILE_PIN_LAYERS_VER="M3"
    TILE_PDN=scripts/pnr/pdn_tile_smic-n3.tcl
    TOP_MAX_ROUTE_LAYER=M10
    TOP_PDN=scripts/pnr/pdn_macro_smic-n3.tcl
else
    SUFFIX=
    TILE_MAX_ROUTE_LAYER=M5
    TILE_MIN_CLK_LAYER=M4
    TILE_PIN_LAYERS_VER="M3 M5"
    TILE_PDN=scripts/pnr/pdn_tile.tcl
    TOP_MAX_ROUTE_LAYER=M9
    TOP_PDN=none
fi

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
make pnr PROJECT=unified-core TOP_LEVEL=pe OUT_DIR=pe_pnr_u80$SUFFIX NETLIST_DIR=pe_syn CLK_PERIOD_NS=$CLK_PE BEOL=$BEOL \
    CORE_UTIL=80 ASPECT_RATIO=1.0 CORE_MARGIN=2 PLACE_DENSITY=0.9 MAX_ROUTE_LAYER=$TILE_MAX_ROUTE_LAYER MIN_CLK_LAYER=$TILE_MIN_CLK_LAYER \
    CLK_UNCERTAINTY_PS=50 PNR_STEP=all PNR_THREADS=0 PNR_REPAIR=1 MACRO_DIRS=none FLOORPLAN=none \
    PDN=$TILE_PDN PINS=$PINS_PE PIN_LAYERS_HOR=M4 PIN_LAYERS_VER="$TILE_PIN_LAYERS_VER" \
    PIN_ARGS="$PIN_ARGS" IO_DELAY_PCT=0 SDC=$SDC_PE

# -----------------------------------------------------------------------------
# Step 3 - synthesize the parent with empty pe stubs
# -----------------------------------------------------------------------------
make syn PROJECT=unified-core TOP_LEVEL=top_NxN OUT_DIR=top_${N}x${N}_syn CLK_PERIOD_NS=$CLK_TOP \
    PARAMS="N=$N" KEEP_HIERARCHY=0 KEEP_MODULES=none BLACKBOX_MODULES="pe" LINK_BLACKBOXES=0

# -----------------------------------------------------------------------------
# Step 4 - assemble: place-and-route the parent with the N*N macros
# -----------------------------------------------------------------------------
make pnr PROJECT=unified-core TOP_LEVEL=top_NxN OUT_DIR=top_${N}x${N}_pnr$SUFFIX NETLIST_DIR=top_${N}x${N}_syn CLK_PERIOD_NS=$CLK_TOP BEOL=$BEOL \
    CORE_UTIL=25 ASPECT_RATIO=1.0 CORE_MARGIN=2 PLACE_DENSITY=0.60 MAX_ROUTE_LAYER=$TOP_MAX_ROUTE_LAYER MIN_CLK_LAYER=M4 \
    CLK_UNCERTAINTY_PS=50 PNR_STEP=all PNR_THREADS=4 PNR_REPAIR=1 MACRO_DIRS="pe_pnr_u80$SUFFIX" \
    FLOORPLAN=$FLOORPLAN MACRO_CHANNEL=40 MACRO_CHANNEL_Y=60 PDN=$TOP_PDN \
    PINS=$PINS_TOP PIN_LAYERS_HOR="M2 M4" PIN_LAYERS_VER="M3 M5" PIN_ARGS="$PIN_ARGS"
