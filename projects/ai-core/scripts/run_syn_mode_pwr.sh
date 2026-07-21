#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Per-mode dynamic power runs for the baseline (top_NxN) vs square
#   (top_NxN_sqr) comparison, measured on the complete 2x2 grids. Same four
#   passes as run_syn_pwr.sh, but pass C runs each of the 11 modes on its own
#   with NUM_VEC vectors so every mode gets its own activity.vcd and its own
#   power report, instead of one VCD averaged over all modes. The 8x8 and 16x16
#   per-mode figures are then assembled from the per-component unit powers, since
#   gate-level simulation of those grids does not fit in memory. Method and
#   results in the wiki experiment page wiki/experiments/syn_mode_pwr.md.
#
#   MODE_SEL and NUM_STREAM are read from +mode / +vectors at run time, so the
#   whole sweep reuses ONE compiled binary per variant. That matters: the
#   Verilator build takes ~10 min and the simulation itself takes ~2 s, so
#   rebuilding per mode would turn a 35 min sweep into a 4 h one.
#
#   Each activity.vcd is deleted once its power report exists - 22 of them would
#   otherwise be ~3 GB, and any one is regenerated in seconds from the binary.
# -----------------------------------------------------------------------------

cd "$(dirname "$0")/../../.." || exit 1
source sourceme.sh

set -e

PROJ="$REPO_HOME/projects/ai-core"

MODES="1 2 3 5 6 7 8 9 10 11 12"
NUM_VEC=100
CLK=10

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
# Pass B - 2x2 grids
# -----------------------------------------------------------------------------
make syn PROJECT=ai-core TOP_LEVEL=top_NxN OUT_DIR=top_2x2 PARAMS="N=2" \
    BLACKBOX_MODULES="$BB_BAS"

make syn PROJECT=ai-core TOP_LEVEL=top_NxN_sqr OUT_DIR=top_2x2_sqr PARAMS="N=2" \
    BLACKBOX_MODULES="$BB_SQR"

# -----------------------------------------------------------------------------
# Passes C and D - one gate-level simulation and one power run per mode
# -----------------------------------------------------------------------------
sweep () {
    local top=$1 tb=$2 netlist=$3 tag=$4 bb=$5

    make post-syn-sim PROJECT=ai-core TOP_LEVEL="$top" OUT_DIR="pwr_mode_$tag" \
        NETLIST_DIR="$netlist" TB="$tb" CLK_PERIOD_NS=$CLK VCD=1
    rm -f "$PROJ/sim/pwr_mode_$tag/output/activity.vcd"

    local simv="$PROJ/sim/pwr_mode_$tag/build/simv"

    for m in $MODES; do
        local vcd_dir="pwr_mode_${tag}_m${m}"
        mkdir -p "$PROJ/sim/$vcd_dir/output"
        ( cd "$PROJ/sim/$vcd_dir/output" && "$simv" +mode=$m +vectors=$NUM_VEC )

        make post-syn-dpa PROJECT=ai-core TOP_LEVEL="$top" OUT_DIR="dpa_mode_${tag}_m${m}" \
            NETLIST_DIR="$netlist" VCD_DIR="$vcd_dir" TB="$tb" CLK_PERIOD_NS=$CLK \
            BLACKBOX_MODULES="$bb"

        rm -f "$PROJ/sim/$vcd_dir/output/activity.vcd"
    done
}

sweep top_NxN     tb_top_NxN_pwr     top_2x2     2x2     "$BB_BAS"
sweep top_NxN_sqr tb_top_NxN_sqr_pwr top_2x2_sqr 2x2_sqr "$BB_SQR"
