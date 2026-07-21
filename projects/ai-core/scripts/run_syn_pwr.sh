#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Dynamic power runs for the baseline (top_NxN) vs square (top_NxN_sqr)
#   comparison, measured on the complete 2x2 grids. Pass A synthesizes every
#   component once on its own, pass B synthesizes the 2x2 grids linking those
#   netlists, pass C runs gate-level simulation with the power stimulus benches
#   to dump activity.vcd, and pass D annotates that activity onto the netlist in
#   OpenSTA and reports per-instance power. The 8x8 and 16x16 figures are then
#   assembled from the per-component unit powers, since gate-level simulation of
#   those grids does not fit in memory. Method, component list, instance counts
#   and results in the wiki experiment page wiki/experiments/syn_pwr.md.
#
#   Passes A and B duplicate run_syn_area.sh at N=2 - if that script has already
#   run, only pass B (the 2x2 grids) is actually needed here.
# -----------------------------------------------------------------------------

cd "$(dirname "$0")/../../.." || exit 1
source sourceme.sh

BB_BAS="pe ctrl disp_array_a disp_array_b icg"
BB_SQR="pe_sqr ctrl_sqr const_sqr disp_array_a_sqr disp_array_b_sqr \
        pe_array_alpha_sqr pe_array_beta_sqr icg"

CLK=10

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
# Pass B - 2x2 grids
# -----------------------------------------------------------------------------
make syn PROJECT=ai-core TOP_LEVEL=top_NxN OUT_DIR=top_2x2 PARAMS="N=2" \
    BLACKBOX_MODULES="$BB_BAS"

make syn PROJECT=ai-core TOP_LEVEL=top_NxN_sqr OUT_DIR=top_2x2_sqr PARAMS="N=2" \
    BLACKBOX_MODULES="$BB_SQR"

# -----------------------------------------------------------------------------
# Pass C - gate-level simulation, dumps activity.vcd
# -----------------------------------------------------------------------------
make post-syn-sim PROJECT=ai-core TOP_LEVEL=top_NxN OUT_DIR=pwr_2x2 \
    NETLIST_DIR=top_2x2 TB=tb_top_NxN_pwr CLK_PERIOD_NS=$CLK VCD=1

make post-syn-sim PROJECT=ai-core TOP_LEVEL=top_NxN_sqr OUT_DIR=pwr_2x2_sqr \
    NETLIST_DIR=top_2x2_sqr TB=tb_top_NxN_sqr_pwr CLK_PERIOD_NS=$CLK VCD=1

# -----------------------------------------------------------------------------
# Pass D - VCD-annotated power analysis
# -----------------------------------------------------------------------------
make post-syn-dpa PROJECT=ai-core TOP_LEVEL=top_NxN OUT_DIR=dpa_2x2 \
    NETLIST_DIR=top_2x2 VCD_DIR=pwr_2x2 TB=tb_top_NxN_pwr CLK_PERIOD_NS=$CLK \
    BLACKBOX_MODULES="$BB_BAS"

make post-syn-dpa PROJECT=ai-core TOP_LEVEL=top_NxN_sqr OUT_DIR=dpa_2x2_sqr \
    NETLIST_DIR=top_2x2_sqr VCD_DIR=pwr_2x2_sqr TB=tb_top_NxN_sqr_pwr CLK_PERIOD_NS=$CLK \
    BLACKBOX_MODULES="$BB_SQR"
