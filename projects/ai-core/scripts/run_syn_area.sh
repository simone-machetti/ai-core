#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Area synthesis runs for the baseline (top_NxN) vs square (top_NxN_sqr)
#   comparison at 8x8 and 16x16. Pass A synthesizes every component once on its
#   own and writes its netlist to projects/ai-core/imp/<module>/output/netlist.v.
#   Pass B synthesizes the complete grids, linking those netlists instead of
#   re-elaborating each instance, so the cost stays independent of the grid size.
#   Method, component list, instance counts and results in the wiki experiment
#   page wiki/experiments/syn_area.md - including the swap setup the 16x16 runs
#   need (~26 GB peak, above the RAM of a 30 GB machine).
# -----------------------------------------------------------------------------

cd "$(dirname "$0")/../../.." || exit 1
source sourceme.sh

BB_BAS="pe ctrl disp_array_a disp_array_b icg"
BB_SQR="pe_sqr ctrl_sqr const_sqr disp_array_a_sqr disp_array_b_sqr \
        pe_array_alpha_sqr pe_array_beta_sqr icg"

# -----------------------------------------------------------------------------
# Pass A - per-module runs
# -----------------------------------------------------------------------------
make syn PROJECT=ai-core TOP_LEVEL=ctrl OUT_DIR=ctrl
make syn PROJECT=ai-core TOP_LEVEL=disp_array_a OUT_DIR=disp_array_a
make syn PROJECT=ai-core TOP_LEVEL=disp_array_b OUT_DIR=disp_array_b
make syn PROJECT=ai-core TOP_LEVEL=pe OUT_DIR=pe

make syn PROJECT=ai-core TOP_LEVEL=ctrl_sqr OUT_DIR=ctrl_sqr
make syn PROJECT=ai-core TOP_LEVEL=const_sqr OUT_DIR=const_sqr
make syn PROJECT=ai-core TOP_LEVEL=disp_array_a_sqr OUT_DIR=disp_array_a_sqr
make syn PROJECT=ai-core TOP_LEVEL=disp_array_b_sqr OUT_DIR=disp_array_b_sqr
make syn PROJECT=ai-core TOP_LEVEL=pe_array_alpha_sqr OUT_DIR=pe_array_alpha_sqr
make syn PROJECT=ai-core TOP_LEVEL=pe_array_beta_sqr OUT_DIR=pe_array_beta_sqr
make syn PROJECT=ai-core TOP_LEVEL=pe_sqr OUT_DIR=pe_sqr

make syn PROJECT=ai-core TOP_LEVEL=icg OUT_DIR=icg

# -----------------------------------------------------------------------------
# Pass B - complete grids
# -----------------------------------------------------------------------------
make syn PROJECT=ai-core TOP_LEVEL=top_NxN OUT_DIR=top_8x8 PARAMS="N=8" \
    BLACKBOX_MODULES="$BB_BAS"

make syn PROJECT=ai-core TOP_LEVEL=top_NxN_sqr OUT_DIR=top_8x8_sqr PARAMS="N=8" \
    BLACKBOX_MODULES="$BB_SQR"

make syn PROJECT=ai-core TOP_LEVEL=top_NxN OUT_DIR=top_16x16 PARAMS="N=16" \
    BLACKBOX_MODULES="$BB_BAS"

make syn PROJECT=ai-core TOP_LEVEL=top_NxN_sqr OUT_DIR=top_16x16_sqr PARAMS="N=16" \
    BLACKBOX_MODULES="$BB_SQR"
